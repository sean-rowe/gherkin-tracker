# BDD Agent Usage Guide

## Overview

The CueMap BDD Agent system automatically implements BDD scenarios by:
1. Creating individual feature branches for each task
2. Implementing the step definition and business logic
3. Running builds/tests and auto-fixing errors
4. Creating pull requests for code review
5. Monitoring PRs via daemon and auto-merging when ready

**CRITICAL**: Each task creates its own branch and PR. Never batch-commit multiple tasks to a single branch.

## Architecture

```
┌─────────────────────┐
│  agent_claude.py    │  ← Main agent: implements BDD steps
│  (Task Executor)    │     Creates 1 branch + 1 PR per task
└──────────┬──────────┘
           │
           ├──→ PostgreSQL (gherkin_tracker DB)
           ├──→ Claude Code CLI
           └──→ GitHub (creates PRs)
                    │
                    ↓
┌─────────────────────┐
│ pr_review_daemon.py │  ← Monitors PRs, fixes issues, merges
│  (PR Manager)       │     Runs as cron job every 5 minutes
└─────────────────────┘
```

## Normal Workflow (Individual PRs)

### 1. Running the Agent

```bash
# Start the agent for the cuemap project
cd /Users/srowe/Projects/gherkin-tracker
python3 agent_claude.py --project cuemap

# With verbose logging
python3 agent_claude.py --project cuemap --verbose

# With log file
python3 agent_claude.py --project cuemap --log agent_run.log
```

### 2. What the Agent Does (Per Task)

For each BDD scenario step:

#### Step 0: Create Feature Branch
- Checks current branch (safeguard against batch commits)
- Checks out `main` and pulls latest
- Creates unique branch: `feat/bdd-{feature-slug}-{step-slug}`
- Example: `feat/bdd-band-collaboration-given-user-creates-band`

#### Step 1: Implementation
- Sends prompt to Claude Code CLI
- Implements step definition file
- Implements necessary business logic
- Ensures no placeholder/TODO code

#### Step 2: Build & Test
- Runs CMake build
- Runs tests
- Auto-fixes build errors (up to 2 attempts)
- Detects regressions in existing tests

#### Step 3: Git Workflow (Only if Build Passes)
- Commits all changes with descriptive message
- Pushes branch to origin
- Creates PR via `gh pr create`
- **SAFEGUARD**: If PR creation fails → Agent STOPS with error

### 3. PR Review Daemon

The daemon runs continuously (typically via cron):

```bash
# Run daemon once (for testing)
cd /Users/srowe/Projects/gherkin-tracker
python3 pr_review_daemon.py /Users/srowe/Projects/cuemap

# Set up as cron job (every 5 minutes)
*/5 * * * * cd /Users/srowe/Projects/gherkin-tracker && python3 pr_review_daemon.py /Users/srowe/Projects/cuemap >> pr_daemon.log 2>&1
```

The daemon:
1. Finds all open PRs with `agent-generated` label
2. Reads CodeRabbit review comments
3. Auto-fixes Critical/Major issues
4. Waits for quiet period (10 min after last review)
5. Auto-merges when ready

## Safeguards Against Batch Commits

### Safeguard 1: Branch Check Before Task
```python
# In create_feature_branch()
if current_branch.startswith('feat/bdd-'):
    raise RuntimeError("Still on feature branch - refusing to reuse")
```

If the agent is still on a feature branch from a previous task, it will **immediately fail** rather than adding more commits to the same branch.

### Safeguard 2: Hard Stop on PR Failure
```python
# In work_on_task()
if not git_result['success']:
    raise RuntimeError("PR creation failed - stopping agent")
```

If PR creation fails (e.g., `gh` not authenticated), the agent **stops completely** rather than continuing to the next task.

### Safeguard 3: Auto-Checkout Main After Failures
```python
# After task failure
subprocess.run(['git', 'checkout', 'main'], cwd=project_path)
```

If a task fails (build doesn't pass), the agent checks out `main` to ensure the next task starts clean.

## What NOT to Do

### ❌ WRONG: Batch/Overnight Mode
```bash
# DO NOT manually commit all changes to one branch
git checkout -b feat/agent-overnight-run
# ... agent runs for hours ...
git add -A
git commit -m "feat: All 256 files"
git push
```

This creates a massive PR with hundreds of files that's impossible to review properly.

### ❌ WRONG: Bypassing PR Creation
```bash
# DO NOT skip PR creation and merge directly
git checkout main
git merge feat/bdd-some-feature
git push
```

Every change MUST go through a PR for CodeRabbit review.

### ❌ WRONG: Running Without gh Auth
```bash
# This will cause agent to create commits without PRs
python3 agent_claude.py --project cuemap
# ... PR creation fails silently ...
```

Always check authentication first:
```bash
gh auth status
# If not authenticated:
gh auth login
```

## ✅ CORRECT: Individual PR Workflow

### Example: Agent Processes 3 Tasks

```bash
python3 agent_claude.py --project cuemap --max-tasks 3
```

**Task 1: "Given user creates a band"**
1. Creates branch: `feat/bdd-band-collaboration-given-user-creates-band`
2. Implements step + business logic
3. Build passes
4. Commits and pushes
5. Creates PR #101
6. Checks out `main` ✓

**Task 2: "When user invites member"**
1. Creates branch: `feat/bdd-band-collaboration-when-user-invites-member`
2. Implements step + business logic
3. Build passes
4. Commits and pushes
5. Creates PR #102
6. Checks out `main` ✓

**Task 3: "Then member receives notification"**
1. Creates branch: `feat/bdd-band-collaboration-then-member-receives-notif`
2. Implements step + business logic
3. Build FAILS
4. Auto-fix attempt 1: Success
5. Build passes
6. Commits and pushes
7. Creates PR #103
8. Checks out `main` ✓

**Result**: 3 individual PRs for review, each focused on one scenario step.

## Monitoring & Debugging

### Check Agent Status
```bash
# View recent agent logs
tail -100 /Users/srowe/Projects/gherkin-tracker/cuemap_agent.log

# Check database for task status
psql -U $(whoami) -d gherkin_tracker -c "
SELECT status, COUNT(*)
FROM task
WHERE project_name = 'CueMap'
GROUP BY status;
"
```

### Check PR Daemon Status
```bash
# View daemon logs
tail -100 /Users/srowe/Projects/gherkin-tracker/pr_daemon.log

# Check open PRs
gh pr list --label agent-generated
```

### Common Issues

#### Issue: Agent Creates Multiple Commits on Same Branch
**Symptom**: Multiple tasks committed to one branch
**Cause**: PR creation failed but agent continued
**Fix**: Safeguards now prevent this - agent will stop with clear error

#### Issue: PRs Not Being Created
**Symptom**: Commits pushed but no PRs
**Cause**: `gh` CLI not authenticated
**Fix**:
```bash
gh auth status
gh auth login
```

#### Issue: Daemon Not Merging PRs
**Symptom**: PRs approved by CodeRabbit but not merged
**Cause**: Daemon not running or quiet period not elapsed
**Fix**:
```bash
# Run daemon manually
python3 pr_review_daemon.py /Users/srowe/Projects/cuemap

# Check daemon is in cron
crontab -l | grep pr_review_daemon
```

## Database Schema

The agent tracks work in PostgreSQL:

```sql
-- Check pending tasks
SELECT feature_name, scenario_name, step_text
FROM task_view
WHERE status = 'Pending'
AND project_name = 'CueMap'
LIMIT 10;

-- Check completed tasks
SELECT COUNT(*) as completed_count
FROM task
WHERE status = 'Completed'
AND project_name = 'CueMap';

-- Check failed tasks
SELECT feature_name, scenario_name, work_log
FROM task_view
WHERE status = 'Failed'
AND project_name = 'CueMap';
```

## Best Practices

### 1. Run Agent in Small Batches
```bash
# Process 10 tasks at a time
python3 agent_claude.py --project cuemap --max-tasks 10
```

This allows you to:
- Monitor progress
- Catch issues early
- Review PRs in manageable batches

### 2. Monitor PR Queue
```bash
# Check how many PRs are open
gh pr list --label agent-generated | wc -l

# If queue is large (>20), pause agent and let daemon catch up
```

### 3. Check Auth Before Overnight Runs
```bash
# Verify gh auth
gh auth status

# Verify database connection
psql -U $(whoami) -d gherkin_tracker -c "SELECT 1;"

# Verify Claude Code CLI
claude --version
```

### 4. Use Log Files for Long Runs
```bash
# Start agent with log file
nohup python3 agent_claude.py \
  --project cuemap \
  --log cuemap_agent_$(date +%Y%m%d).log \
  > agent_stdout.log 2>&1 &

# Monitor progress
tail -f cuemap_agent_*.log
```

## Recovery from Batch Commit Scenario

If the agent accidentally batch-commits (e.g., overnight run created 256 files on one branch):

### Option 1: Retroactive PR Creation (Already Done)
```bash
# Use create_thematic_prs.py to split into themed PRs
python3 create_thematic_prs.py
```

This groups files by feature area and creates multiple PRs retroactively.

### Option 2: Manual Split
```bash
# Checkout the batch commit branch
git checkout feat/agent-overnight-run

# Create individual branches for each feature area
git checkout -b feat/bdd-accessibility
git checkout feat/agent-overnight-run -- src/backend/Application/Accessibility/*
git commit -m "feat(bdd): Accessibility features"
gh pr create --title "..." --body "..."

# Repeat for each feature area
```

## Success Metrics

Monitor these to ensure healthy agent operation:

- **PR:Task Ratio**: Should be ~1:1 (one PR per task)
- **Build Pass Rate**: Should be >80% after auto-fixes
- **PR Merge Rate**: Should be >90% after CodeRabbit review
- **Average PR Size**: Should be <10 files per PR

Check with:
```bash
# PR count vs task count
gh pr list --label agent-generated --state all | wc -l
psql -U $(whoami) -d gherkin_tracker -c "SELECT COUNT(*) FROM task WHERE status='Completed';"

# Should be approximately equal
```

## Summary

✅ **DO**:
- Run agent in small batches (10-50 tasks)
- Ensure `gh auth` before running
- Let PR daemon handle review/merge
- Monitor logs and PR queue
- Check database for task status

❌ **DON'T**:
- Manually batch-commit multiple tasks
- Bypass PR creation
- Run without authentication
- Let PR queue grow beyond 50 PRs
- Merge PRs manually (let daemon do it)

The safeguards in `agent_claude.py` now enforce these practices automatically.
