# Gherkin Tracker - Quick Start Guide

## What This Is

A project-agnostic system for tracking Gherkin features, scenarios, steps, and their implementation status. Enables AI agents to autonomously work on implementing BDD scenarios.

## Setup (One-Time)

### 1. Install PostgreSQL (if not already installed)

```bash
brew install postgresql@17
brew services start postgresql@17
```

### 2. Run Setup Script

```bash
cd ~/projects/gherkin-tracker
./setup.sh
```

This creates:
- PostgreSQL database `gherkin_tracker`
- All tables (9), views (4), and functions (3)

## Connection Info

**Database:** gherkin_tracker
**Username:** Your macOS username
**Host:** localhost
**Port:** 5432

## Quick Commands

### Connect to Database
```bash
psql -d gherkin_tracker
```

Or with full path:
```bash
/usr/local/opt/postgresql@17/bin/psql -d gherkin_tracker
```

### Stop Database
```bash
brew services stop postgresql@17
```

### Start Database (if stopped)
```bash
brew services start postgresql@17
```

### View Database Status
```bash
brew services list | grep postgresql
```

## Next Steps for CareSync Project

1. **Audit Gherkin Files**
   - Compare `tests/CareSync.Specs/Features/*.feature` against `CLAUDE.md` requirements
   - Identify missing scenarios

2. **Import Gherkin Data**
   - Parse all `.feature` files
   - Import to database:
     - Project: CareSync
     - Features from each .feature file
     - Scenarios from each feature
     - Steps (deduplicated)
     - Tasks (one per step)

3. **Mark Completed Tasks**
   - Scan `src/` directory for implementations
   - Match step definitions to code
   - Mark tasks as "Completed" where implementation exists

4. **Start Agent System**
   - Create agent orchestration system
   - Agents query `sp_GetNextTask`
   - Assign via `sp_AssignTaskToAgent`
   - Work on implementation
   - Complete via `sp_CompleteTask`

## Database Schema Overview

```
Project
  └─ Epic
      └─ Feature (.feature file)
          └─ Scenario
              └─ ScenarioStep (ordered)
                  └─ Step (reusable)
                      └─ Task (1:1 with Step)
                          └─ Agent (assigned worker)
```

## Key Features

- **Step Deduplication**: "Given I am logged in" only stored once
- **Reusability**: Steps shared across scenarios
- **Agent Continuity**: Agents leave notes for next worker
- **Progress Tracking**: See completion % per feature
- **Priority Queue**: Work highest-priority tasks first

## Functions (PostgreSQL)

### Get Next Task
```sql
SELECT * FROM sp_get_next_task('general-purpose');
```

### Assign Task to Agent
```sql
SELECT sp_assign_task_to_agent(
    '<task-uuid>'::uuid,
    '<agent-uuid>'::uuid
);
```

### Complete Task
```sql
SELECT sp_complete_task(
    '<task-uuid>'::uuid,
    '<agent-uuid>'::uuid,
    'Implemented authentication service',
    TRUE,
    TRUE
);
```

## Useful Views

### Feature Progress
```sql
SELECT * FROM vw_feature_progress;
```

### Task Work Queue
```sql
SELECT * FROM vw_task_work_queue
ORDER BY priority DESC, task_name ASC;
```

### Agent Workload
```sql
SELECT * FROM vw_agent_workload;
```

### Complete Feature View
```sql
SELECT * FROM vw_feature_complete
WHERE feature_name LIKE '%Authentication%';
```

## Troubleshooting

### "Cannot connect to database"
```bash
# Check if PostgreSQL is running
brew services list | grep postgresql

# If not running, start it
brew services start postgresql@17

# Check PostgreSQL logs
tail -f /usr/local/var/log/postgresql@17.log
```

### "Database does not exist"
```bash
# Re-run setup script
cd ~/projects/gherkin-tracker
./setup.sh
```

### Reset Everything
```bash
# Drop and recreate database
/usr/local/opt/postgresql@17/bin/psql -d postgres -c "DROP DATABASE IF EXISTS gherkin_tracker;"

# Re-run setup
cd ~/projects/gherkin-tracker
./setup.sh
```
