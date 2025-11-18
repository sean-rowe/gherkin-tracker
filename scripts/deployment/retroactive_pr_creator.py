#!/usr/bin/env python3
"""
Retroactive PR Creator for Overnight BDD Tasks

This script takes the staged changes from the overnight run and splits them
into individual branches and PRs, one per completed BDD step.
"""

import os
import sys
import subprocess
import re
from pathlib import Path

# Read the completed tasks
TASKS_FILE = "/tmp/completed_cuemap_tasks.tsv"
PROJECT_PATH = "/Users/srowe/Projects/cuemap"

def read_completed_tasks():
    """Read completed tasks from TSV file"""
    tasks = []
    with open(TASKS_FILE, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 5:
                tasks.append({
                    'id': parts[0],
                    'feature_name': parts[1],
                    'scenario_name': parts[2],
                    'step_type': parts[3],
                    'step_text': parts[4],
                    'completed_at': parts[5] if len(parts) > 5 else None
                })
    return tasks

def create_branch_name(task):
    """Generate a branch name from task"""
    feature_slug = re.sub(r'[^a-z0-9]+', '-', task['feature_name'].lower()).strip('-')[:30]
    step_slug = re.sub(r'[^a-z0-9]+', '-', task['step_text'][:40].lower()).strip('-')
    return f"feat/bdd-{feature_slug}-{step_slug}"

def get_staged_files():
    """Get list of all currently staged files"""
    result = subprocess.run(
        ['git', 'diff', '--cached', '--name-only'],
        cwd=PROJECT_PATH,
        capture_output=True,
        text=True,
        check=True
    )
    return set(result.stdout.strip().split('\n'))

def guess_files_for_task(task, all_staged_files):
    """
    Guess which files belong to this task based on naming patterns.
    This is a heuristic - we'll look for files that match the feature/scenario.
    """
    # Convert feature/scenario names to possible file name patterns
    feature_slug = re.sub(r'[^a-z0-9]+', '_', task['feature_name'].lower())
    scenario_slug = re.sub(r'[^a-z0-9]+', '_', task['scenario_name'].lower())
    step_words = re.findall(r'\w+', task['step_text'].lower())

    # Patterns to match
    patterns = [
        feature_slug,
        scenario_slug,
    ] + step_words[:3]  # First 3 words from step

    matching_files = []
    for file_path in all_staged_files:
        file_lower = file_path.lower()
        # Check if any pattern matches
        for pattern in patterns:
            if len(pattern) > 3 and pattern in file_lower:
                matching_files.append(file_path)
                break

    return matching_files

def create_pr_for_task(task, task_num, total_tasks):
    """Create a branch, commit, and PR for a single task"""
    print(f"\n{'='*80}")
    print(f"Processing Task {task_num}/{total_tasks}")
    print(f"Feature: {task['feature_name']}")
    print(f"Step: {task['step_type']} {task['step_text']}")
    print(f"{'='*80}")

    try:
        # Get all staged files
        all_staged_files = get_staged_files()

        # Guess which files belong to this task
        task_files = guess_files_for_task(task, all_staged_files)

        if not task_files:
            print(f"⚠️  No files found for this task, skipping...")
            return False

        print(f"Found {len(task_files)} potential files:")
        for f in task_files[:5]:
            print(f"  - {f}")
        if len(task_files) > 5:
            print(f"  ... and {len(task_files) - 5} more")

        # Ask for confirmation
        response = input(f"\nCreate PR with these files? (y/n/s=skip/q=quit): ").lower()
        if response == 'q':
            sys.exit(0)
        if response in ['n', 's']:
            print("Skipping...")
            return False
        if response != 'y':
            print("Invalid response, skipping...")
            return False

        # Create branch name
        branch_name = create_branch_name(task)

        # Check if branch exists
        result = subprocess.run(
            ['git', 'rev-parse', '--verify', branch_name],
            cwd=PROJECT_PATH,
            capture_output=True
        )

        if result.returncode == 0:
            # Branch exists, add random suffix
            import random
            branch_name = f"{branch_name}-{random.randint(1000, 9999)}"

        # Checkout main and pull latest
        print("Checking out main branch...")
        subprocess.run(['git', 'checkout', 'main'], cwd=PROJECT_PATH, check=True)
        subprocess.run(['git', 'pull'], cwd=PROJECT_PATH, check=True)

        # Create new branch
        print(f"Creating branch: {branch_name}")
        subprocess.run(['git', 'checkout', '-b', branch_name], cwd=PROJECT_PATH, check=True)

        # Checkout the specific files from the overnight branch
        print("Checking out files from overnight branch...")
        subprocess.run(
            ['git', 'checkout', 'feat/agent-overnight-implementations-20251116', '--'] + task_files,
            cwd=PROJECT_PATH,
            check=True
        )

        # Add files
        subprocess.run(['git', 'add'] + task_files, cwd=PROJECT_PATH, check=True)

        # Create commit message
        commit_msg = f"""feat(bdd): {task['step_type']} {task['step_text']}

Feature: {task['feature_name']}
Scenario: {task['scenario_name']}

Implemented by autonomous BDD agent (retroactive PR).

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
"""

        # Commit
        print("Creating commit...")
        subprocess.run(['git', 'commit', '-m', commit_msg], cwd=PROJECT_PATH, check=True)

        # Push
        print("Pushing to remote...")
        subprocess.run(['git', 'push', '-u', 'origin', branch_name], cwd=PROJECT_PATH, check=True)

        # Create PR
        pr_title = f"feat(bdd): {task['step_type']} {task['step_text'][:60]}"
        pr_body = f"""## BDD Step Implementation (Retroactive)

**Feature:** {task['feature_name']}
**Scenario:** {task['scenario_name']}
**Step:** {task['step_type']} {task['step_text']}

### Implementation Details

This PR was created retroactively from the overnight agent run. The code was implemented by the autonomous BDD agent but needed to be split into individual PRs for review.

### Files Changed

{len(task_files)} files modified/created for this step.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
"""

        print("Creating PR...")
        pr_result = subprocess.run(
            ['gh', 'pr', 'create',
             '--title', pr_title,
             '--body', pr_body,
             '--label', 'agent-generated',
             '--label', 'bdd',
             '--label', 'retroactive'],
            cwd=PROJECT_PATH,
            capture_output=True,
            text=True,
            check=True
        )

        pr_url = pr_result.stdout.strip()
        print(f"✅ Created PR: {pr_url}")

        # Go back to the overnight branch for next iteration
        subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH, check=True)

        return True

    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e}")
        print(f"stderr: {e.stderr if hasattr(e, 'stderr') else 'N/A'}")
        # Try to recover
        subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH)
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH)
        return False

def main():
    print("Retroactive PR Creator for Overnight BDD Tasks")
    print("=" * 80)

    # Read tasks
    tasks = read_completed_tasks()
    print(f"Found {len(tasks)} completed tasks")

    # Make sure we're on the overnight branch
    subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH, check=True)

    # Process each task
    success_count = 0
    skip_count = 0

    for i, task in enumerate(tasks, 1):
        if create_pr_for_task(task, i, len(tasks)):
            success_count += 1
        else:
            skip_count += 1

    print(f"\n{'='*80}")
    print(f"SUMMARY")
    print(f"{'='*80}")
    print(f"Total tasks: {len(tasks)}")
    print(f"PRs created: {success_count}")
    print(f"Skipped: {skip_count}")
    print(f"{'='*80}")

if __name__ == '__main__':
    main()
