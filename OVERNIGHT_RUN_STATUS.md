# CueMap Autonomous BDD System - Overnight Run

## Setup Complete - Started at 2025-11-15 22:00 CST (Fixed at 22:05 CST)

### System Configuration

**Cron Jobs (Every 5 minutes):**
- `/Users/srowe/projects/gherkin-tracker/run_cuemap_agent.sh` - BDD Agent
- `/Users/srowe/projects/gherkin-tracker/run_pr_daemon.sh` - PR Review Daemon

**Agent Configuration:**
- Project: CueMap
- Max tasks per run: 10
- Parallel workers: 5
- Total capacity: Up to 5 agents working simultaneously

**Daemon Configuration:**
- Monitors all open PRs with `agent-generated` label
- Auto-fixes CodeRabbit and Gemini Code Assist review comments
- Verifies builds before pushing
- Auto-merges after quiet period (10 min) or immediately after successful fixes

### What to Check in the Morning

**1. Agent Progress (with task details):**
```bash
cd /Users/srowe/projects/gherkin-tracker
# See what tasks are being worked on:
tail -100 cuemap_agent_cron.log
# Or search for specific info:
grep "NEW TASK ASSIGNED\|TASK COMPLETED\|TASK FAILED" cuemap_agent_cron.log | tail -50
```

**2. PR Daemon Activity:**
```bash
tail -100 pr_daemon_cron.log
```

**3. Database Statistics:**
```bash
psql -d gherkin_tracker -c "
SELECT
    COUNT(*) FILTER (WHERE t.status = 'Completed') as completed,
    COUNT(*) FILTER (WHERE t.status = 'Failed') as failed,
    COUNT(*) FILTER (WHERE t.status = 'Pending') as pending
FROM task t
JOIN step s ON t.step_id = s.id
JOIN scenario_step ss ON ss.step_id = s.id
JOIN scenario sc ON ss.scenario_id = sc.id
JOIN feature f ON sc.feature_id = f.id
JOIN project p ON f.project_id = p.id
WHERE p.name = 'CueMap';
"
```

**4. Open PRs:**
```bash
cd /Users/srowe/Projects/cuemap
gh pr list --label agent-generated
```

**5. Merged PRs:**
```bash
gh pr list --state merged --label agent-generated --limit 20
```

### Expected Results

With 5 parallel agents running every 5 minutes for ~8 hours (overnight):
- **Theoretical max**: ~480 tasks (5 agents × 10 tasks × 96 runs)
- **Realistic estimate**: 100-200 tasks completed
  - Each task takes ~3-5 minutes to implement
  - PRs need time for review and merge
  - Some tasks may fail and need manual intervention

### Monitoring Files

All logs are in `/Users/srowe/projects/gherkin-tracker/`:
- `cuemap_agent.log` - Detailed agent activity
- `cuemap_agent_cron.log` - Cron execution log
- `pr_daemon_cron.log` - Daemon execution log

### Current Status (as of start)

**Database:**
- Total tasks: 12,534
- Completed: 41 (0.3%)
- Failed: 15 (0.1%)
- Pending: 12,473 (99.5%)

**Last Successful PR:**
- PR #87 - Merged at 03:45:31Z
- Implemented: Apple Music network restoration step
- Auto-fixed 2 review comments
- Build verified and merged automatically

### System Health Checks

**If things aren't working in the morning:**

1. Check if cron is running:
```bash
crontab -l
ps aux | grep agent_claude
ps aux | grep pr_review_daemon
```

2. Check for errors:
```bash
grep -i error cuemap_agent_cron.log | tail -20
grep -i error pr_daemon_cron.log | tail -20
```

3. Restart manually if needed:
```bash
/Users/srowe/projects/gherkin-tracker/run_cuemap_agent.sh &
/Users/srowe/projects/gherkin-tracker/run_pr_daemon.sh
```

### Notes

- Cron runs every 5 minutes, so even if one run fails, the next will try again
- Agent has duplicate prevention - won't re-do completed tasks
- Daemon is stateless - each run is independent
- All operations are logged for debugging

### Bugs Fixed at 22:05 CST

**Bug #1: PR Daemon Syntax Error**
- Issue: GraphQL query had incorrect string escaping causing SyntaxError
- Fix: Separated query into a variable with proper quote handling
- File: `pr_review_daemon.py` line 665

**Bug #2: Agent Multiprocessing Pickle Error**
- Issue: Local function `worker_process` couldn't be pickled on macOS (spawn mode)
- Fix: Moved worker function to module level as `_parallel_worker`
- File: `agent_claude.py` lines 1581-1627

**Bug #3: Manager.Value() Lock Error**
- Issue: `ValueProxy.get_lock()` doesn't exist - Manager handles synchronization automatically
- Fix: Removed `.get_lock()` calls, direct value assignment works
- File: `agent_claude.py` lines 1619-1623

**Bug #4: Claude Command Not Found in Cron (22:10 CST)**
- Issue: `[Errno 2] No such file or directory: 'claude'` - PATH not set in cron environment
- Fix: Added `export PATH=...` to both wrapper scripts
- Files: `run_cuemap_agent.sh:6`, `run_pr_daemon.sh:6`
- Result: ✅ Fixed - claude command now found

**Bug #5: Claude Code Authentication Failure (22:15 CST)**
- Issue: `Invalid API key · Please run /login` - HOME not set, can't find ~/.claude/ config
- Fix: Added `export HOME="/Users/srowe"` to both wrapper scripts
- Files: `run_cuemap_agent.sh:7`, `run_pr_daemon.sh:7`
- Result: Should succeed on next cron run at 22:20

All fixes applied. Next cron run at 22:20 will test authentication fix.

Good night! The system should make significant progress overnight. 🌙
