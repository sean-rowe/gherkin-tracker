#!/usr/bin/env python3
"""
Git Worktree Manager
Manages isolated git worktrees for parallel agent execution
"""

import os
import subprocess
import logging
from pathlib import Path
from typing import Optional
import shutil


class GitWorktreeManager:
    """
    Manages git worktrees for parallel agent execution.

    Each agent gets its own isolated worktree so multiple agents
    can work on different branches simultaneously without conflicts.
    """

    def __init__(self, base_repo_path: str, worktree_base_path: Optional[str] = None):
        """
        Initialize the worktree manager.

        Args:
            base_repo_path: Path to the main git repository
            worktree_base_path: Base directory for all worktrees (default: base_repo/.worktrees)
        """
        self.base_repo = Path(base_repo_path).resolve()

        if not (self.base_repo / '.git').exists():
            raise ValueError(f"Not a git repository: {self.base_repo}")

        # Create worktree base directory
        if worktree_base_path:
            self.worktree_base = Path(worktree_base_path).resolve()
        else:
            self.worktree_base = self.base_repo.parent / f"{self.base_repo.name}_worktrees"

        self.worktree_base.mkdir(exist_ok=True)
        logging.info(f"Worktree base directory: {self.worktree_base}")

    def create_worktree(self, task_id: str, branch_name: str, base_branch: str = "main") -> Path:
        """
        Create a new git worktree for a task.

        Args:
            task_id: Unique identifier for the task
            branch_name: Name of the new branch to create
            base_branch: Base branch to branch from (default: main)

        Returns:
            Path to the created worktree directory
        """
        worktree_path = self.worktree_base / f"task_{task_id}"

        # Clean up if worktree already exists
        if worktree_path.exists():
            logging.warning(f"Worktree already exists for task {task_id}, cleaning up...")
            self.cleanup_worktree(task_id)

        # Ensure we're up to date with remote
        self._run_git_command(["fetch", "origin"], cwd=self.base_repo)

        # Create new worktree with new branch
        logging.info(f"Creating worktree for task {task_id} at {worktree_path}")
        logging.info(f"Branch: {branch_name} (from {base_branch})")

        try:
            # Create worktree and new branch from base_branch
            self._run_git_command([
                "worktree", "add",
                "-b", branch_name,
                str(worktree_path),
                f"origin/{base_branch}"
            ], cwd=self.base_repo)

            logging.info(f"✓ Worktree created successfully: {worktree_path}")
            return worktree_path

        except subprocess.CalledProcessError as e:
            logging.error(f"✗ Failed to create worktree: {e}")
            raise

    def cleanup_worktree(self, task_id: str, force: bool = True):
        """
        Remove a worktree after task completion.

        Args:
            task_id: Task identifier
            force: Force removal even if worktree has uncommitted changes
        """
        worktree_path = self.worktree_base / f"task_{task_id}"

        if not worktree_path.exists():
            logging.debug(f"Worktree doesn't exist: {worktree_path}")
            return

        logging.info(f"Cleaning up worktree for task {task_id}")

        try:
            # Remove worktree
            cmd = ["worktree", "remove", str(worktree_path)]
            if force:
                cmd.append("--force")

            self._run_git_command(cmd, cwd=self.base_repo)

            # Clean up any remaining directory
            if worktree_path.exists():
                shutil.rmtree(worktree_path)

            logging.info(f"✓ Worktree cleaned up: {worktree_path}")

        except subprocess.CalledProcessError as e:
            logging.error(f"✗ Failed to cleanup worktree: {e}")
            # Try to force remove directory anyway
            if worktree_path.exists():
                shutil.rmtree(worktree_path, ignore_errors=True)

    def commit_and_push(self, task_id: str, commit_message: str, branch_name: str) -> bool:
        """
        Commit all changes in worktree and push to remote.

        Args:
            task_id: Task identifier
            commit_message: Commit message
            branch_name: Branch name to push

        Returns:
            True if successful, False otherwise
        """
        worktree_path = self.worktree_base / f"task_{task_id}"

        if not worktree_path.exists():
            logging.error(f"Worktree doesn't exist: {worktree_path}")
            return False

        try:
            # Add all changes
            self._run_git_command(["add", "-A"], cwd=worktree_path)

            # Check if there are changes to commit
            result = subprocess.run(
                ["git", "diff", "--cached", "--quiet"],
                cwd=worktree_path,
                capture_output=True
            )

            if result.returncode == 0:
                logging.warning("No changes to commit")
                return False

            # Commit
            self._run_git_command(["commit", "-m", commit_message], cwd=worktree_path)
            logging.info(f"✓ Changes committed: {commit_message[:60]}...")

            # Push to remote
            self._run_git_command([
                "push", "-u", "origin", branch_name
            ], cwd=worktree_path)

            logging.info(f"✓ Changes pushed to origin/{branch_name}")
            return True

        except subprocess.CalledProcessError as e:
            logging.error(f"✗ Failed to commit and push: {e}")
            return False

    def get_worktree_path(self, task_id: str) -> Optional[Path]:
        """
        Get the path to a worktree by task ID.

        Args:
            task_id: Task identifier

        Returns:
            Path to worktree or None if it doesn't exist
        """
        worktree_path = self.worktree_base / f"task_{task_id}"
        return worktree_path if worktree_path.exists() else None

    def list_active_worktrees(self) -> list:
        """
        List all currently active worktrees.

        Returns:
            List of worktree paths
        """
        try:
            result = self._run_git_command(["worktree", "list"], cwd=self.base_repo)
            worktrees = []

            for line in result.stdout.strip().split('\n'):
                if line:
                    # Format: path branch
                    parts = line.split()
                    if len(parts) >= 1:
                        path = Path(parts[0])
                        if path != self.base_repo:  # Exclude main repo
                            worktrees.append(path)

            return worktrees

        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to list worktrees: {e}")
            return []

    def cleanup_all_worktrees(self, force: bool = True):
        """
        Clean up all worktrees (useful for maintenance).

        Args:
            force: Force removal even with uncommitted changes
        """
        worktrees = self.list_active_worktrees()

        logging.info(f"Cleaning up {len(worktrees)} worktrees")

        for worktree_path in worktrees:
            if worktree_path.parent == self.worktree_base:
                # Extract task_id from path
                task_id = worktree_path.name.replace("task_", "")
                self.cleanup_worktree(task_id, force=force)

    @staticmethod
    def _run_git_command(args: list, cwd: Path) -> subprocess.CompletedProcess:
        """
        Run a git command.

        Args:
            args: Git command arguments (without 'git')
            cwd: Working directory

        Returns:
            CompletedProcess result
        """
        cmd = ["git"] + args
        logging.debug(f"Running: {' '.join(cmd)} (cwd: {cwd})")

        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True
        )

        return result

    def get_branch_name_for_task(self, task: dict) -> str:
        """
        Generate a branch name for a task.

        Args:
            task: Task dictionary from database

        Returns:
            Branch name (e.g., feature/BDD-123-given-user-logs-in)
        """
        # Sanitize step text for branch name
        step_text = task.get('step_text', '')[:50]  # Limit length
        sanitized = step_text.lower()
        sanitized = re.sub(r'[^a-z0-9\s-]', '', sanitized)  # Remove special chars
        sanitized = re.sub(r'\s+', '-', sanitized.strip())  # Replace spaces with hyphens

        task_id = str(task.get('task_id', 'unknown'))[:8]  # Short UUID
        step_type = task.get('step_type', 'step').lower()

        # Format: feature/BDD-{short-id}-{step-type}-{sanitized-text}
        return f"feature/BDD-{task_id}-{step_type}-{sanitized}"
