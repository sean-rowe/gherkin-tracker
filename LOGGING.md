# Agent Logging System

The gherkin-tracker agent now has comprehensive logging to help you understand what it's doing in real-time.

## Quick Start

### Run agent with logging

```bash
# Basic verbose mode (console only)
python3 agent_claude.py --project CareSync --max-tasks 5 --verbose

# Verbose mode with log file
python3 agent_claude.py --project CareSync --max-tasks 10 --verbose --log-file agent.log

# Run with log file only (no verbose console)
python3 agent_claude.py --project CareSync --max-tasks 10 --log-file agent.log

# Multiple parallel agents with logging
python3 agent_claude.py --project CareSync --parallel 4 --verbose --log-file agent.log
```

### Watch logs in real-time

Open a second terminal and run:

```bash
# Watch the default log file
./watch_agent.sh agent.log

# Or use tail -f if you prefer plain output
tail -f agent.log
```

## What Gets Logged

### INFO Level (default with --verbose)
- Session start/end
- Configuration parameters
- Task assignment (feature, scenario, step)
- Build and test results
- Entity dependency checks (summary)
- Claude Code execution status

### DEBUG Level (with --verbose)
- Full prompt sent to Claude Code (preview)
- Detailed entity scanning results
- Entity paths and file extensions
- Claude Code output (preview)
- Test output previews
- Missing type detection details

### WARNING Level
- Missing entities/dependencies detected
- Build failures
- Pre-existing errors in codebase

### ERROR Level
- Failed entity creation
- Critical build failures
- Database errors
- Configuration errors

## Log Format

```
2025-11-15 14:43:36 | INFO     | WORKING ON TASK: Given database contains 50 common medications
2025-11-15 14:43:36 | INFO     | Feature: 30-Day Offline Capability | Scenario: Seed database
2025-11-15 14:43:36 | DEBUG    | ✓ Found entity: Medication
2025-11-15 14:43:36 | WARNING  | Missing types detected: OfflineDatabase
2025-11-15 14:43:36 | ERROR    | ✗ Failed to create entity: OfflineDatabase
```

Each line includes:
- Timestamp (YYYY-MM-DD HH:MM:SS)
- Log level (INFO, DEBUG, WARNING, ERROR)
- Message

## Real-Time Log Viewer

The `watch_agent.sh` script provides color-coded real-time log viewing:

- **🔴 RED** - Errors and failures
- **🟡 YELLOW** - Warnings
- **🟢 GREEN** - Info messages and successes
- **🔵 CYAN** - Debug messages
- **BOLD** - Separators (===, ---)

## Use Cases

### Debugging Agent Behavior
```bash
# Run with verbose logging
python3 agent_claude.py --project CareSync --max-tasks 1 --verbose --log-file debug.log

# In another terminal, watch the log
./watch_agent.sh debug.log
```

### Production Runs
```bash
# Run multiple parallel agents, log to file only
python3 agent_claude.py --project CareSync --parallel 4 --max-tasks 100 --log-file production.log

# Check progress periodically
grep "WORKING ON TASK" production.log | tail -20
```

### Finding Errors
```bash
# Show all errors
grep "ERROR" agent.log

# Show all warnings
grep "WARNING" agent.log

# Show failed tasks
grep "TASK FAILED" agent.log
```

## Log File Management

Log files can grow large during long runs. Manage them:

```bash
# Check log file size
ls -lh agent.log

# Compress old logs
gzip agent_2025-11-15.log

# Delete old logs
rm agent_2025-*.log.gz
```

## Timestamps

All timestamps are in local time. Sessions are marked with:

```
====================================================================================================
NEW AGENT SESSION STARTED
====================================================================================================
```

This helps you identify when the agent was restarted.

## Performance Notes

- Logging adds minimal overhead (~1-2% CPU)
- File logging is asynchronous (non-blocking)
- Console logging may slow down with --verbose in fast parallel runs
- For maximum performance, use --log-file without --verbose

## Examples

### Watching a Long Run

Terminal 1:
```bash
python3 agent_claude.py \
    --project CareSync \
    --parallel 4 \
    --max-tasks 100 \
    --log-file agent_$(date +%Y%m%d_%H%M%S).log \
    --verbose
```

Terminal 2:
```bash
# Watch in real-time with colors
./watch_agent.sh agent_*.log

# Or grep for specific patterns
tail -f agent_*.log | grep -E "(WORKING ON TASK|Build result|✓|✗)"
```

### Analyzing Completed Run

```bash
# How many tasks completed?
grep "TASK COMPLETED" agent.log | wc -l

# How many failed?
grep "TASK FAILED" agent.log | wc -l

# What entities were created?
grep "Successfully created entity" agent.log

# What were the build errors?
grep -A 5 "Build result: FAILED" agent.log
```

## Troubleshooting

**No logs appearing:**
- Check that --verbose or --log-file is specified
- Verify log file path is writable
- Check for Python logging conflicts

**Too much output:**
- Remove --verbose flag
- Use --log-file only for cleaner console

**Can't see colors in watch_agent.sh:**
- Your terminal may not support ANSI colors
- Use `tail -f` instead for plain output

**Log file too large:**
- Use log rotation (logrotate on Linux)
- Compress old logs with gzip
- Or run with shorter --max-tasks limits
