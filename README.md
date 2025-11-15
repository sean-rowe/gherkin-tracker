# Gherkin Tracker with Claude Code Agent System

A complete BDD implementation system that uses Claude Code CLI to automatically implement Gherkin features with proper step definitions and business logic.

## 🎯 What This Is

An autonomous agent system that:
1. Reads Gherkin feature files from your project (102 features with 100% CLAUDE.md coverage)
2. Uses Claude Code (`claude -p`) to implement BDD step definitions
3. Uses Claude Code to implement business logic (services/controllers)
4. Runs builds and tests to verify implementations
5. Tracks progress in PostgreSQL database
6. **Supports multiple projects** in different languages (C#, C++, Python, etc.)

**Current Status:**
- **102 features** imported
- **1,895 scenarios** defined
- **11,692 BDD steps** ready to implement
- **28 steps** currently implemented (0.2%)

## 🚀 Quick Start

```bash
cd ~/projects/gherkin-tracker

# Process 1 task (recommended first test)
python3 agent_claude.py --max-tasks 1

# Process 5 tasks
python3 agent_claude.py --max-tasks 5

# Check statistics
python3 agent_system.py stats
```

## 📚 Documentation

- **[USAGE.md](USAGE.md)** - Complete usage guide with examples
- **[AGENT_SYSTEM.md](AGENT_SYSTEM.md)** - Architecture and database schema details
- **[QUICKSTART.md](QUICKSTART.md)** - Database setup instructions
- **[MULTI_PROJECT.md](MULTI_PROJECT.md)** - Multi-project and multi-language support

## 📁 System Files

### Agent Systems
- `agent_claude.py` - **Claude Code integrated agent** (uses `claude -p`)
- `agent_system.py` - Framework-only agent (stub implementation)

### Database Tools
- `import_gherkin.py` - Import Gherkin features into database
- `mark_completed_tasks.py` - Scan codebase for completed tasks
- `verify_bdd_implementations.py` - Verify BDD step implementations

### Database Scripts
- `scripts/01-create-database.sql` - Create PostgreSQL database
- `scripts/02-create-schema.sql` - Create tables, views, functions
- `scripts/03-add-bdd-tracking.sql` - Add BDD vs business logic tracking

## 🔧 How It Works

For each BDD step, the Claude Code agent:

### 1. **Implements BDD Step + Business Logic** (OPTIMIZED - Single Call)
```bash
claude -p "Implement BOTH the SpecFlow BDD step definition AND business logic for:
Feature: Translation Services
Step: Given user \"Maria\" has preferred language set to \"Spanish\"
..."
```

Creates/updates both `*Steps.cs` file AND service class with real implementation in one call.

**Optimization**: Previously this was 2 separate calls. Combining them saves ~12-15 seconds per task.

### 2. **Runs Tests**
```bash
dotnet build
dotnet test --no-build
```

Verifies implementation works correctly.

### 3. **Updates Database**
Marks task as Completed or Failed, records BDD file/method, logs work accomplished.

## ⚡ Performance

- **~90-120 seconds per task** (optimized with combined prompts)
- **~12,534 tasks** total
- **Estimated time**: ~12-15 days continuous running
- See [OPTIMIZATION.md](OPTIMIZATION.md) for further speedup strategies

## 📊 Database Schema

**9 Tables:**
- `project` - Top-level project container
- `epic` - Agile epics (optional)
- `feature` - Gherkin features (.feature files)
- `scenario` - Scenarios within features
- `step` - Reusable Gherkin steps (deduplicated)
- `scenario_step` - Maps scenarios to steps
- `task` - Implementation tasks (1:1 with steps)
- `agent` - Autonomous agents
- `agent_task_history` - Work logs

**7 Views:**
- `vw_feature_complete` - Full feature hierarchy
- `vw_task_work_queue` - Prioritized task queue
- `vw_bdd_implementation_status` - Implementation status breakdown
- `vw_tasks_needing_bdd` - Tasks needing BDD steps
- `vw_feature_bdd_progress` - Per-feature completion %
- `vw_agent_workload` - Current agent assignments
- `vw_feature_progress` - Overall progress

**3 Stored Procedures:**
- `sp_get_next_task(agent_type)` - Get next task from queue
- `sp_assign_task_to_agent(task_id, agent_id)` - Assign task
- `sp_complete_task(...)` - Mark task complete/failed

## 📈 Progress Tracking

```sql
-- View overall progress
SELECT * FROM vw_feature_bdd_progress
ORDER BY full_completion_pct DESC;

-- View implementation status
SELECT implementation_status, COUNT(*)
FROM vw_bdd_implementation_status
GROUP BY implementation_status;

-- View agent performance
SELECT a.name, COUNT(h.id) as tasks_completed
FROM agent a
JOIN agent_task_history h ON a.id = h.agent_id
GROUP BY a.name;
```

## 🛠️ Setup

### Prerequisites
- PostgreSQL 17 installed (`brew install postgresql@17`)
- Claude Code CLI installed and configured
- CareSync project at `/Users/srowe/RiderProjects/caresync`

### Database Setup
```bash
cd ~/projects/gherkin-tracker
brew services start postgresql@17
./setup.sh
```

### Import Features
```bash
python3 import_gherkin.py CareSync /Users/srowe/RiderProjects/caresync/tests/CareSync.Specs/Features
```

### Check Status
```bash
python3 agent_system.py stats
```

## 🎮 Running Agents

```bash
# Test with 1 task
python3 agent_claude.py --max-tasks 1

# Run multiple tasks
python3 agent_claude.py --max-tasks 10

# Run until complete (11,692 tasks!)
python3 agent_claude.py
```

## 📝 Example Output

```
================================================================================
[Claude-Agent-1] NEW TASK ASSIGNED
================================================================================
Feature:  Translation Services
Scenario: Translate message to recipient's preferred language
Step:     Given user "Maria" has preferred language set to "Spanish"
================================================================================

================================================================================
STEP 1: BDD STEP DEFINITION
================================================================================
[Claude Code implementing step definition...]

================================================================================
STEP 2: BUSINESS LOGIC
================================================================================
[Claude Code implementing business logic...]

================================================================================
STEP 3: BUILD & TEST
================================================================================
Build: SUCCESS
Tests: PASSED

================================================================================
[Claude-Agent-1] TASK COMPLETED
================================================================================
```

## 🔄 Workflow

1. Agent gets next task from database (prioritized queue)
2. Agent calls Claude Code to implement BDD step definition
3. Agent calls Claude Code to implement business logic
4. Agent runs `dotnet build` and `dotnet test`
5. Agent updates database with results
6. Repeat for next task

## ⚠️ Important Notes

- Each task takes 1-5 minutes (Claude Code + build/test)
- All work is tracked in database with full history
- Failed tasks are marked and can be retried
- Agent can be stopped/resumed at any time (Ctrl+C)
- Original Gherkin features are never modified

## 🎯 Features Created

This system has **100% CLAUDE.md requirements coverage** including:

**High Priority Features:**
- Translation Services (10 scenarios)
- Scheduled Messaging (16 scenarios)
- Natural Language Processing (20 scenarios)
- Extended Wearable Integration (23 scenarios)
- Multi-Language Support (24 scenarios)
- Gesture Controls & Haptics (27 scenarios)
- 30-Day Offline Capability (26 scenarios)
- Battery Optimization (24 scenarios)

**Moderate Priority Features:**
- Simplified UI Mode (23 scenarios)
- Data Migration & Upgrade (23 scenarios)
- Clinical Trial Support (23 scenarios)

Plus 91 other features covering all CareSync requirements.

## 📚 Learn More

- [Full Usage Guide](USAGE.md) - Detailed usage examples
- [Architecture Docs](AGENT_SYSTEM.md) - Database schema and design
- [Quick Start](QUICKSTART.md) - Setup instructions

## 🚧 Next Steps

The agent system is fully functional and ready to use. Just run:

```bash
cd ~/projects/gherkin-tracker
python3 agent_claude.py --max-tasks 1
```

This will implement your first BDD step using Claude Code!

## 📊 Database Connection

**Host:** localhost:5432
**Database:** gherkin_tracker
**User:** $USER

Connect:
```bash
psql -d gherkin_tracker
```

## 🎓 Credits

Built for the CareSync project - a multi-platform health tracking application with complete BDD test coverage.
