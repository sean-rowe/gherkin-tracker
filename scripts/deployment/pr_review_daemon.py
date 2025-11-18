#!/usr/bin/env python3
"""
PR Review Daemon
Monitors open pull requests, auto-fixes CodeRabbit review comments, and merges when ready.

This runs as a cron job (every 5 minutes) and is stateless - each run is independent.
"""

import os
import sys
import subprocess
import logging
import json
import psycopg2
import psycopg2.extras
from psycopg2.extras import RealDictCursor
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Dict, Optional
import re
import time

from pr_manager import PullRequestManager
from git_worktree_manager import GitWorktreeManager


# Setup logging for daemon
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)-8s | %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

# Database connection parameters
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}


class PRReviewDaemon:
    """
    Daemon that monitors and manages pull requests.

    Runs as a cron job to:
    1. Check all open PRs
    2. Read CodeRabbit review comments
    3. Auto-fix issues
    4. Wait for approval or quiet period
    5. Merge when ready
    6. Handle dependency blocking
    """

    def __init__(self, repo_path: str):
        """
        Initialize the daemon.

        Args:
            repo_path: Path to the main repository
        """
        self.repo_path = Path(repo_path).resolve()
        self.pr_manager = PullRequestManager(repo_path)
        self.worktree_manager = GitWorktreeManager(repo_path)

        # Connect to database
        self.conn = psycopg2.connect(**DB_PARAMS)

        # Configuration
        self.quiet_period_minutes = 10  # Wait 10 min after last review before merging
        self.max_fix_attempts = 3  # Maximum auto-fix attempts per PR

    def run(self):
        """
        Main daemon loop - processes all open PRs.

        This is called by cron every 5 minutes.
        """
        logging.info("=" * 80)
        logging.info("PR REVIEW DAEMON - Starting run")
        logging.info("=" * 80)

        try:
            # Get all open PRs
            open_prs = self._get_open_prs()

            if not open_prs:
                logging.info("No open pull requests to process")
                return

            logging.info(f"Found {len(open_prs)} open pull requests")

            # Process each PR
            for pr in open_prs:
                self._process_pr(pr)

            logging.info("=" * 80)
            logging.info("PR REVIEW DAEMON - Run completed")
            logging.info("=" * 80)

        except Exception as e:
            logging.error(f"Daemon error: {e}", exc_info=True)

        finally:
            self.conn.close()

    def _get_open_prs(self) -> List[Dict]:
        """
        Get all open pull requests created by agents.

        Returns:
            List of PR dictionaries
        """
        try:
            result = subprocess.run(
                [
                    "gh", "pr", "list",
                    "--label", "agent-generated",
                    "--state", "open",
                    "--json", "number,title,headRefName,updatedAt,labels,mergeable,reviewDecision"
                ],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True
            )

            prs = json.loads(result.stdout)
            return prs

        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to get open PRs: {e}")
            return []

    def _process_pr(self, pr: Dict):
        """
        Process a single pull request.

        Args:
            pr: PR dictionary from GitHub
        """
        pr_number = pr['number']
        branch_name = pr['headRefName']
        title = pr['title']

        logging.info("─" * 80)
        logging.info(f"Processing PR #{pr_number}: {title}")
        logging.info(f"Branch: {branch_name}")

        # Check if PR is blocked by dependencies
        if self._is_blocked_by_dependencies(pr):
            logging.info(f"⏸  PR #{pr_number} is blocked by dependencies, skipping for now")
            return

        # Get review comments
        review_comments = self.pr_manager.get_review_comments(str(pr_number))

        if not review_comments:
            logging.info(f"No review comments found for PR #{pr_number}")

            # Check if we should merge
            if self._should_merge_pr(pr):
                self._merge_pr(pr)
            return

        # Filter for CodeRabbit comments that need fixing
        fixable_comments = self._filter_fixable_comments(review_comments)

        if not fixable_comments:
            logging.info(f"No fixable comments for PR #{pr_number}")

            # Check if we should merge
            if self._should_merge_pr(pr):
                self._merge_pr(pr)
            return

        # Check how many fix attempts we've made
        fix_count = self._get_fix_attempt_count(pr_number)

        if fix_count >= self.max_fix_attempts:
            logging.warning(f"⚠ PR #{pr_number} has reached max fix attempts ({self.max_fix_attempts})")
            logging.warning("Manual intervention required")
            self._add_pr_comment(pr_number, "Maximum auto-fix attempts reached. Manual review required.")
            return

        # Auto-fix the comments
        logging.info(f"Found {len(fixable_comments)} fixable comments, attempting auto-fix...")
        self._auto_fix_comments(pr, fixable_comments)

    def _filter_fixable_comments(self, comments: List[Dict]) -> List[Dict]:
        """
        Filter review comments to find ones we can auto-fix.

        Args:
            comments: List of review comments

        Returns:
            List of fixable comments
        """
        fixable = []

        for comment in comments:
            body = comment.get('body', '')
            user = comment.get('user', {}).get('login', '')

            # Only process CodeRabbit or Gemini Code Assist comments
            if 'coderabbit' not in user.lower() and 'gemini' not in user.lower():
                continue

            # Skip already resolved comments
            if comment.get('in_reply_to_id'):
                continue

            # Look for actionable feedback
            if any(keyword in body.lower() for keyword in [
                'suggest', 'recommend', 'should', 'consider',
                'magic string', 'magic number', 'extract', 'refactor',
                'documentation', 'comment', 'complexity'
            ]):
                fixable.append(comment)

        return fixable

    def _auto_fix_comments(self, pr: Dict, comments: List[Dict]):
        """
        Auto-fix review comments using Claude Code.

        Args:
            pr: PR dictionary
            comments: List of comments to fix
        """
        pr_number = pr['number']
        branch_name = pr['headRefName']

        # Create a temporary worktree for fixes
        task_id = f"pr-fix-{pr_number}"
        worktree_path = None

        try:
            # Create worktree from PR branch
            logging.info(f"Creating worktree for PR #{pr_number} fixes...")
            worktree_path = self.worktree_manager.worktree_base / f"task_{task_id}"

            # Clean up existing worktree if it exists
            if worktree_path.exists():
                logging.info(f"Cleaning up existing worktree at {worktree_path}")
                self.worktree_manager.cleanup_worktree(task_id, force=True)

            # Fetch latest changes
            subprocess.run(
                ["git", "fetch", "origin"],
                cwd=self.repo_path,
                check=True,
                capture_output=True
            )

            # Delete local branch if it exists and recreate from remote
            subprocess.run(
                ["git", "branch", "-D", branch_name],
                cwd=self.repo_path,
                capture_output=True  # Don't fail if branch doesn't exist
            )

            # Create worktree from remote branch
            subprocess.run(
                [
                    "git", "worktree", "add",
                    str(worktree_path),
                    f"origin/{branch_name}"
                ],
                cwd=self.repo_path,
                check=True,
                capture_output=True
            )

            # Create local tracking branch
            subprocess.run(
                ["git", "checkout", "-b", branch_name, f"origin/{branch_name}"],
                cwd=worktree_path,
                check=True,
                capture_output=True
            )

            # Copy vendor directory from main repo (faster than submodule init)
            logging.info("Copying vendor dependencies from main repo...")
            import shutil
            main_vendor = self.repo_path / "vendor"
            worktree_vendor = worktree_path / "vendor"

            # Remove existing vendor dir (it's a git submodule ref, we need the actual files)
            if worktree_vendor.exists():
                shutil.rmtree(worktree_vendor)

            if main_vendor.exists():
                shutil.copytree(main_vendor, worktree_vendor, symlinks=True)
                logging.info("✓ Vendor dependencies copied")
            else:
                logging.warning("Main repo vendor directory not found")

            # Build fix prompt from comments
            fix_prompt = self._build_fix_prompt(comments)

            # Run Claude Code to fix issues
            logging.info("Running Claude Code to fix review comments...")
            result = subprocess.run(
                [
                    "claude",
                    "-p",
                    "--dangerously-skip-permissions",
                    fix_prompt
                ],
                cwd=worktree_path,
                capture_output=True,
                text=True,
                timeout=300
            )

            if result.returncode != 0:
                logging.error(f"Claude Code failed: {result.stderr}")
                return

            logging.info("✓ Claude Code completed fixes")

            # Verify build still passes
            if not self._verify_build(worktree_path):
                logging.error("Build failed after fixes, aborting")
                return

            # Commit and push fixes
            fix_message = f"fix: Address CodeRabbit review comments\n\nAuto-fixed {len(comments)} review comments"

            if self.worktree_manager.commit_and_push(task_id, fix_message, branch_name):
                logging.info(f"✓ Fixes committed and pushed to {branch_name}")

                # Record fix attempt
                self._record_fix_attempt(pr_number)

                # Add comment to PR
                self._add_pr_comment(
                    pr_number,
                    f"🤖 Auto-fixed {len(comments)} review comments. Build verified successful."
                )

                # After fixing, check if we should merge immediately
                # Since we just fixed the issues and verified build, skip quiet period
                logging.info("Checking if PR should be merged after fixes...")
                if self._should_merge_pr(pr, skip_quiet_period=True):
                    self._merge_pr(pr)

        except Exception as e:
            logging.error(f"Error during auto-fix: {e}", exc_info=True)

        finally:
            # Cleanup worktree
            if worktree_path and worktree_path.exists():
                self.worktree_manager.cleanup_worktree(task_id, force=True)

    def _build_fix_prompt(self, comments: List[Dict]) -> str:
        """
        Build a Claude Code prompt from review comments.

        Args:
            comments: List of review comments

        Returns:
            Prompt string
        """
        prompt_parts = [
            "Fix the following code review comments:\n\n"
        ]

        for i, comment in enumerate(comments, 1):
            file_path = comment.get('path', 'unknown')
            body = comment.get('body', '')
            line = comment.get('line', 'N/A')

            prompt_parts.append(f"{i}. **File: {file_path}:{line}**")
            prompt_parts.append(f"   {body}\n")

        prompt_parts.append("\n**Requirements:**")
        prompt_parts.append("- Fix ALL issues mentioned above")
        prompt_parts.append("- Follow CLAUDE.md coding standards")
        prompt_parts.append("- Ensure build passes")
        prompt_parts.append("- Do not introduce regressions")
        prompt_parts.append("- Use enums/constants instead of magic values")
        prompt_parts.append("- Add XML documentation where missing")

        return "\n".join(prompt_parts)

    def _verify_build(self, worktree_path: Path) -> bool:
        """
        Verify build passes in worktree.

        Args:
            worktree_path: Path to worktree

        Returns:
            True if build passes, False otherwise
        """
        try:
            logging.info("Verifying build...")

            # Detect project type and use appropriate build command
            if Path(worktree_path / "CMakeLists.txt").exists():
                # C++ project with CMake - need to configure first
                logging.info("Configuring CMake build...")
                build_dir = worktree_path / "build"
                build_dir.mkdir(exist_ok=True)

                # Configure CMake
                config_result = subprocess.run(
                    ["cmake", "-S", ".", "-B", "build", "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Debug"],
                    cwd=worktree_path,
                    capture_output=True,
                    text=True,
                    timeout=60
                )

                if config_result.returncode != 0:
                    logging.error(f"✗ CMake configuration failed:\n{config_result.stdout}\n{config_result.stderr}")
                    return False

                logging.info("✓ CMake configured")

                # Build
                build_cmd = ["cmake", "--build", "build", "-j4"]
            elif list(Path(worktree_path).glob("*.csproj")):
                # C# project
                build_cmd = ["dotnet", "build", "--no-restore", "--warnaserror"]
            else:
                # Default to cmake
                logging.info("Configuring CMake build...")
                build_dir = worktree_path / "build"
                build_dir.mkdir(exist_ok=True)

                config_result = subprocess.run(
                    ["cmake", "-S", ".", "-B", "build", "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Debug"],
                    cwd=worktree_path,
                    capture_output=True,
                    text=True,
                    timeout=60
                )

                if config_result.returncode != 0:
                    logging.error(f"✗ CMake configuration failed:\n{config_result.stdout}\n{config_result.stderr}")
                    return False

                build_cmd = ["cmake", "--build", "build", "-j4"]

            logging.info(f"Running build command: {' '.join(build_cmd)}")
            result = subprocess.run(
                build_cmd,
                cwd=worktree_path,
                capture_output=True,
                text=True,
                timeout=300  # 5 minutes for C++ builds
            )

            if result.returncode == 0:
                logging.info("✓ Build passed")
                return True
            else:
                logging.error(f"✗ Build failed:\n{result.stdout}\n{result.stderr}")
                return False

        except Exception as e:
            logging.error(f"Build verification error: {e}")
            return False

    def _should_merge_pr(self, pr: Dict, skip_quiet_period: bool = False) -> bool:
        """
        Determine if a PR should be merged.

        Args:
            pr: PR dictionary
            skip_quiet_period: If True, skip the quiet period check (used after auto-fixes)

        Returns:
            True if PR should be merged, False otherwise
        """
        pr_number = pr['number']
        review_decision = pr.get('reviewDecision')
        mergeable = pr.get('mergeable')
        updated_at = pr.get('updatedAt')

        # Must be mergeable
        if mergeable != 'MERGEABLE':
            logging.info(f"PR #{pr_number} is not mergeable (state: {mergeable})")
            return False

        # If approved, merge immediately
        if review_decision == 'APPROVED':
            logging.info(f"✓ PR #{pr_number} is approved")
            return True

        # If we just fixed issues and verified build, merge immediately
        if skip_quiet_period:
            logging.info(f"✓ PR #{pr_number} auto-fixes verified, merging immediately")
            return True

        # If no review decision, check quiet period
        if review_decision is None or review_decision == 'REVIEW_REQUIRED':
            # Calculate time since last update
            updated_time = datetime.fromisoformat(updated_at.replace('Z', '+00:00'))
            now = datetime.now(updated_time.tzinfo)
            time_since_update = now - updated_time

            quiet_period = timedelta(minutes=self.quiet_period_minutes)

            if time_since_update >= quiet_period:
                logging.info(f"✓ PR #{pr_number} has been quiet for {time_since_update.total_seconds()/60:.1f} minutes")
                return True
            else:
                remaining = (quiet_period - time_since_update).total_seconds() / 60
                logging.info(f"⏱  PR #{pr_number} needs {remaining:.1f} more minutes of quiet time")
                return False

        # Changes requested - don't merge
        if review_decision == 'CHANGES_REQUESTED':
            logging.info(f"⚠ PR #{pr_number} has changes requested")
            return False

        return False

    def _merge_pr(self, pr: Dict):
        """
        Merge a pull request.

        Args:
            pr: PR dictionary
        """
        pr_number = pr['number']
        title = pr['title']

        logging.info(f"🔀 Merging PR #{pr_number}: {title}")

        if self.pr_manager.merge_pull_request(str(pr_number), method="squash"):
            logging.info(f"✓ PR #{pr_number} merged successfully")

            # Update database to mark task as fully complete
            self._mark_task_completed(pr)
        else:
            logging.error(f"✗ Failed to merge PR #{pr_number}")

    def _is_blocked_by_dependencies(self, pr: Dict) -> bool:
        """
        Check if PR is blocked by dependencies.

        A PR is blocked if it modifies files that are also modified by
        other open PRs with lower PR numbers (created earlier).

        Args:
            pr: PR dictionary

        Returns:
            True if blocked, False otherwise
        """
        # TODO: Implement dependency checking logic
        # For now, return False (no blocking)
        return False

    def _get_fix_attempt_count(self, pr_number: int) -> int:
        """
        Get the number of fix attempts made for a PR.

        Args:
            pr_number: PR number

        Returns:
            Number of fix attempts
        """
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT COUNT(*) FROM pr_fix_attempts
            WHERE pr_number = %s
        """, (pr_number,))

        count = cursor.fetchone()[0]
        cursor.close()

        return count

    def _record_fix_attempt(self, pr_number: int):
        """
        Record a fix attempt for a PR.

        Args:
            pr_number: PR number
        """
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO pr_fix_attempts (pr_number, attempted_at)
            VALUES (%s, NOW())
        """, (pr_number,))

        self.conn.commit()
        cursor.close()

    def _mark_task_completed(self, pr: Dict):
        """
        Mark task as fully completed in database.

        Args:
            pr: PR dictionary
        """
        # Extract task ID from PR title or branch name
        # Format: feature/BDD-{task-id}-...
        branch_name = pr['headRefName']
        match = re.search(r'BDD-([a-f0-9-]+)', branch_name)

        if not match:
            logging.warning("Could not extract task ID from branch name")
            return

        task_id = match.group(1)

        cursor = self.conn.cursor()
        cursor.execute("""
            UPDATE tasks
            SET status = 'merged', merged_at = NOW()
            WHERE task_id::text LIKE %s
        """, (f"{task_id}%",))

        self.conn.commit()
        cursor.close()

        logging.info(f"✓ Task {task_id} marked as merged")

    def _add_pr_comment(self, pr_number: int, comment: str):
        """
        Add a comment to a PR.

        Args:
            pr_number: PR number
            comment: Comment text
        """
        try:
            subprocess.run(
                ["gh", "pr", "comment", str(pr_number), "--body", comment],
                cwd=self.repo_path,
                capture_output=True,
                check=True
            )
            logging.info(f"✓ Added comment to PR #{pr_number}")
        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to add comment: {e}")

    def _resolve_comments(self, pr_number: int, comments: List[Dict]):
        """
        Resolve (mark as resolved) review comments that were fixed.

        Args:
            pr_number: PR number
            comments: List of comment dicts to resolve
        """
        for comment in comments:
            comment_id = comment.get('id')
            if not comment_id:
                continue

            try:
                # Use GitHub GraphQL API to resolve the comment thread
                # First get the thread ID from the comment
                query = f'query {{ node(id: "{comment_id}") {{ ... on PullRequestReviewComment {{ id pullRequestReview {{ id }} }} }} }}'
                result = subprocess.run(
                    [
                        "gh", "api", "graphql",
                        "-f", f"query={query}"
                    ],
                    cwd=self.repo_path,
                    capture_output=True,
                    text=True
                )

                if result.returncode == 0:
                    # Mark as resolved by adding a reply
                    self._reply_to_comment(pr_number, comment_id, "✅ Fixed by automated daemon")
                    logging.info(f"✓ Resolved comment {comment_id}")
                else:
                    logging.warning(f"Could not resolve comment {comment_id}")

            except Exception as e:
                logging.warning(f"Failed to resolve comment {comment_id}: {e}")

    def _reply_to_comment(self, pr_number: int, comment_id: int, body: str):
        """
        Reply to a review comment.

        Args:
            pr_number: PR number
            comment_id: Comment ID to reply to
            body: Reply body
        """
        try:
            subprocess.run(
                [
                    "gh", "pr", "comment", str(pr_number),
                    "--body", body
                ],
                cwd=self.repo_path,
                capture_output=True,
                check=True
            )
        except subprocess.CalledProcessError as e:
            logging.warning(f"Failed to reply to comment: {e}")


def main():
    """Main entry point for daemon."""
    # Get repo path from environment or use default
    repo_path = os.getenv('REPO_PATH', '/Users/srowe/RiderProjects/caresync')

    if not Path(repo_path).exists():
        logging.error(f"Repository path does not exist: {repo_path}")
        sys.exit(1)

    daemon = PRReviewDaemon(repo_path)
    daemon.run()


if __name__ == '__main__':
    main()
