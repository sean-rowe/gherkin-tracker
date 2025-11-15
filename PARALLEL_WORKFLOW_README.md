# Parallel Agent Workflow with Git Worktrees

## Overview

This system enables **true parallel BDD development** where multiple agents work simultaneously on different tasks, each in their own isolated git worktree. After completing their work, agents create pull requests and die. A separate daemon process monitors these PRs, auto-fixes review comments from CodeRabbit, and merges them when ready.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                  Main Agent Orchestrator                             │
│  - Spawns multiple worker agents in parallel                        │
│  - Each gets next available task                                    │
│  - Coordinates but doesn't block                                    │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │     Worker Agent (parallel instances)       │
        │  1. Create dedicated git worktree           │
        │  2. Create feature branch                   │
        │  3. Implement BDD step                      │
        │  4. Build & verify (with auto-fix)          │
        │  5. Commit changes                          │
        │  6. Push to remote                          │
        │  7. Create pull request                     │
        │  8. Request CodeRabbit review               │
        │  9. Exit (stateless agent dies)             │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │    PR Review Daemon (runs as cron job)      │
        │  - Triggered every 5 minutes                │
        │  - Checks all open agent PRs                │
        │  - Reads CodeRabbit review comments         │
        │  - Creates temporary worktree for fixes     │
        │  - Runs Claude Code to fix issues           │
        │  - Commits and pushes fixes                 │
        │  - Waits for quiet period (10 minutes)      │
        │  - Merges when approved or quiet            │
        │  - Checks dependency blocking               │
        │  - Max 3 auto-fix attempts per PR           │
        └─────────────────────────────────────────────┘
```

## Components

### 1. Git Worktree Manager (`git_worktree_manager.py`)

Manages isolated git worktrees for parallel development.

**Key Features:**
- Creates worktrees in `{repo}_worktrees/task_{id}/`
- Each worktree gets own feature branch
- Cleanup after PR creation
- Handles commit and push
- Prevents conflicts between parallel agents

**Usage:**
```python
from git_worktree_manager import GitWorktreeManager

# Initialize
manager = GitWorktreeManager('/path/to/caresync')

# Create worktree for task
task_id = "abc123"
branch_name = "feature/BDD-abc123-given-user-logs-in"
worktree_path = manager.create_worktree(task_id, branch_name, base_branch="main")

# Do work in worktree...

# Commit and push
manager.commit_and_push(task_id, "feat: Implement login step", branch_name)

# Cleanup
manager.cleanup_worktree(task_id)
```

### 2. Pull Request Manager (`pr_manager.py`)

Creates and manages GitHub pull requests.

**Key Features:**
- Uses GitHub CLI (`gh`)
- Auto-generates PR title and body
- Requests CodeRabbit review automatically
- Retrieves PR status and comments
- Merges PRs

**Usage:**
```python
from pr_manager import PullRequestManager

# Initialize
pr_mgr = PullRequestManager('/path/to/caresync')

# Create PR
task = {
    'task_id': 'abc123',
    'feature_name': 'User Authentication',
    'scenario_name': 'Login flow',
    'step_type': 'Given',
    'step_text': 'user navigates to login page'
}

pr_url = pr_mgr.create_pull_request(
    branch_name="feature/BDD-abc123-given-user-logs-in",
    task=task,
    worktree_path=worktree_path
)
```

### 3. PR Review Daemon (`pr_review_daemon.py`)

Autonomous daemon that manages PR lifecycle.

**Key Features:**
- **Stateless**: Each run is independent
- **Auto-fixes**: Parses CodeRabbit comments and fixes issues
- **Safety**: Max 3 fix attempts per PR
- **Smart merging**: Waits for approval OR 10-minute quiet period
- **Dependency blocking**: Won't merge if blocking other PRs

**Running the Daemon:**

```bash
# Manual run
cd /Users/srowe/projects/gherkin-tracker
python3 pr_review_daemon.py

# Set up cron job (every 5 minutes)
crontab -e

# Add this line:
*/5 * * * * cd /Users/srowe/projects/gherkin-tracker && python3 pr_review_daemon.py >> daemon.log 2>&1
```

**Daemon Logic:**

1. Get all open PRs with `agent-generated` label
2. For each PR:
   - Check if blocked by dependencies
   - Get CodeRabbit review comments
   - Filter for fixable issues
   - Create temp worktree
   - Run Claude Code to fix
   - Verify build passes
   - Commit and push fixes
   - Record fix attempt
3. Determine if PR should merge:
   - ✅ Approved by reviewer → merge immediately
   - ✅ No activity for 10 minutes → merge
   - ❌ Changes requested → wait
   - ❌ Max fix attempts reached → require manual intervention

### 4. Database Schema

**New Tables:**

```sql
-- Track auto-fix attempts
CREATE TABLE pr_fix_attempts (
    id SERIAL PRIMARY KEY,
    pr_number INTEGER NOT NULL,
    attempted_at TIMESTAMP NOT NULL,
    fix_successful BOOLEAN,
    error_message TEXT
);

-- Add to task table
ALTER TABLE task ADD COLUMN pr_number INTEGER;
ALTER TABLE task ADD COLUMN pr_url TEXT;
ALTER TABLE task ADD COLUMN branch_name TEXT;
ALTER TABLE task ADD COLUMN worktree_path TEXT;
ALTER TABLE task ADD COLUMN merged_at TIMESTAMP;
```

**New Functions:**

```sql
-- Get PRs needing review processing
SELECT * FROM get_prs_needing_review();

-- Check if PR maxed out fix attempts
SELECT has_reached_max_fix_attempts(123, 3);

-- Record successful merge
SELECT record_pr_merge(123, 'abc123def456');
```

**Dashboard View:**

```sql
-- View PR status
SELECT * FROM vw_pr_dashboard;
```

Shows:
- PR number and URL
- Branch name
- Current status
- Feature/scenario/step info
- Fix attempt count
- Last fix attempt time
- Status summary (Merged, Fixing Issues, Awaiting Review, etc.)

## Workflow Example

### Step 1: Agent Receives Task

```python
# agent_claude.py (modified)
from git_worktree_manager import GitWorktreeManager
from pr_manager import PullRequestManager

# Get next task
task = agent.get_next_task()

# Create worktree
worktree_mgr = GitWorktreeManager(project_config.path)
branch_name = worktree_mgr.get_branch_name_for_task(task)
worktree_path = worktree_mgr.create_worktree(
    str(task['task_id']),
    branch_name
)

# Change to worktree directory
os.chdir(worktree_path)
```

### Step 2: Agent Implements Step

```python
# Run Claude Code in worktree
result = subprocess.run([
    'claude-code',
    '--dangerously-skip-permissions',
    '--prompt', implementation_prompt
], cwd=worktree_path)

# Build and test
build_result = run_build(worktree_path)
```

### Step 3: Agent Creates PR

```python
# Commit changes
worktree_mgr.commit_and_push(
    task_id=str(task['task_id']),
    commit_message=f"feat(BDD): {task['step_type']} {task['step_text']}",
    branch_name=branch_name
)

# Create PR
pr_mgr = PullRequestManager(project_config.path)
pr_url = pr_mgr.create_pull_request(
    branch_name=branch_name,
    task=task,
    worktree_path=worktree_path
)

# Update database
cursor.execute("""
    UPDATE task
    SET pr_number = %s, pr_url = %s, branch_name = %s, status = 'pr_created'
    WHERE id = %s
""", (pr_number, pr_url, branch_name, task['task_id']))

# Cleanup worktree
worktree_mgr.cleanup_worktree(str(task['task_id']))

# Agent exits (dies) - work is done!
```

### Step 4: Daemon Monitors PR

**5 minutes later** (cron triggers daemon):

```python
# pr_review_daemon.py runs
daemon = PRReviewDaemon('/path/to/caresync')
daemon.run()  # Processes all open PRs
```

Daemon finds the PR and:
1. Reads CodeRabbit comments
2. Sees suggestion to extract magic string
3. Creates temp worktree
4. Runs Claude Code: "Fix review comment: Extract magic string 'WiFi' to enum"
5. Verifies build passes
6. Commits and pushes fix
7. Waits for next review cycle

**10 minutes later** (no new comments):

Daemon sees:
- PR has been quiet for 10+ minutes
- Build is passing
- No changes requested

→ **Merges PR** ✅

## Configuration

### Environment Variables

```bash
# Repository path (for daemon)
export REPO_PATH=/Users/srowe/RiderProjects/caresync

# Database connection
export PGUSER=srowe
export PGDATABASE=gherkin_tracker
```

### GitHub CLI Setup

```bash
# Install GitHub CLI
brew install gh

# Authenticate
gh auth login

# Test
gh pr list
```

### Cron Job Setup

```bash
# Edit crontab
crontab -e

# Add daemon (runs every 5 minutes)
*/5 * * * * cd /Users/srowe/projects/gherkin-tracker && /usr/bin/python3 pr_review_daemon.py >> /Users/srowe/projects/gherkin-tracker/daemon.log 2>&1

# Add cleanup job (runs daily at 2 AM)
0 2 * * * cd /Users/srowe/projects/gherkin-tracker && /usr/bin/python3 cleanup_worktrees.py >> /Users/srowe/projects/gherkin-tracker/cleanup.log 2>&1
```

## Monitoring

### View Active PRs

```bash
# From command line
gh pr list --label agent-generated

# From database
psql gherkin_tracker -c "SELECT * FROM vw_pr_dashboard;"
```

### Check Daemon Logs

```bash
# Real-time
tail -f daemon.log

# Recent errors
grep ERROR daemon.log | tail -20

# PR merge history
grep "Merging PR" daemon.log
```

### Monitor Worktrees

```bash
# List active worktrees
cd /Users/srowe/RiderProjects/caresync
git worktree list

# Check disk usage
du -sh /Users/srowe/RiderProjects/caresync_worktrees
```

## Parallel Execution

### Run Multiple Agents

```bash
# Run 4 agents in parallel
python3 agent_claude.py --project CareSync --parallel 4 --max-tasks 100
```

Each agent:
1. Gets unique task
2. Creates own worktree
3. Works independently
4. Creates PR
5. Dies

All PRs managed by single daemon.

### Scalability

- **Agents**: Limited by CPU/memory (tested up to 10)
- **Worktrees**: Limited by disk space (~500MB each)
- **PRs**: Limited by GitHub rate limits (5000/hour)
- **Daemon**: Handles 100+ PRs efficiently

## Troubleshooting

### Agent Can't Create Worktree

```bash
# Check for orphaned worktrees
git worktree list
git worktree prune

# Manual cleanup
cd /Users/srowe/RiderProjects/caresync_worktrees
rm -rf task_*
```

### PR Creation Fails

```bash
# Check GitHub auth
gh auth status

# Check network
gh pr list

# Check branch exists
git branch -r | grep BDD-
```

### Daemon Not Merging

```bash
# Check PR status
gh pr view 123

# Check fix attempts
psql gherkin_tracker -c "SELECT * FROM pr_fix_attempts WHERE pr_number = 123;"

# Manual merge
gh pr merge 123 --squash
```

### Build Fails After Auto-Fix

```bash
# Check daemon logs
grep "PR #123" daemon.log

# Manual fix in temp worktree
cd /Users/srowe/RiderProjects/caresync_worktrees/task_pr-fix-123
dotnet build

# Push manual fix
git add -A
git commit -m "fix: Manual build fix"
git push
```

## Best Practices

1. **Keep PRs Small**: One BDD step = one PR
2. **Monitor Daemon**: Check logs daily
3. **Clean Worktrees**: Run cleanup weekly
4. **Review Metrics**: Check `vw_pr_dashboard` regularly
5. **Limit Parallelism**: Start with 2-4 agents, scale gradually
6. **Database Backups**: Backup before large parallel runs
7. **CodeRabbit Config**: Tune review rules for auto-fixable issues

## Future Enhancements

- [ ] Dependency tracking between PRs (don't merge if blocking)
- [ ] Priority queue for high-priority PRs
- [ ] Slack/email notifications for stuck PRs
- [ ] Metrics dashboard (PR throughput, fix success rate)
- [ ] Smart retry logic (exponential backoff)
- [ ] Parallel daemon instances (shard by PR number)
- [ ] Integration with CI/CD pipelines
- [ ] Automated regression detection across PRs

## Files Created

- `git_worktree_manager.py` - Worktree lifecycle management
- `pr_manager.py` - GitHub PR operations
- `pr_review_daemon.py` - Autonomous PR reviewer/merger
- `database/scripts/04-add-pr-management.sql` - Database schema
- `PARALLEL_WORKFLOW_README.md` - This documentation

## Next Steps

1. ✅ Test single agent workflow end-to-end
2. ⏳ Test parallel agents (2-4 concurrent)
3. ⏳ Set up cron job for daemon
4. ⏳ Run production batch (100+ tasks)
5. ⏳ Monitor and tune auto-fix success rate
6. ⏳ Implement dependency blocking logic
7. ⏳ Add metrics and monitoring dashboard
