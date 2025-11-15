# Claude Code Agent System - Usage Guide

## 🚀 Quick Start

The Claude Code agent system uses `claude -p` to automatically implement BDD steps from your Gherkin feature files.

### Prerequisites

1. Claude Code CLI installed and configured
2. PostgreSQL database running with gherkin_tracker
3. CareSync project at `/Users/srowe/RiderProjects/caresync`

### Run the Agent System

```bash
cd ~/projects/gherkin-tracker

# Process 1 task (recommended for first test)
python3 agent_claude.py --max-tasks 1

# Process 5 tasks
python3 agent_claude.py --max-tasks 5

# Process all tasks (use with caution - 11,692 tasks!)
python3 agent_claude.py
```

## 📋 What It Does

For each BDD step, the agent will:

### 1. **Implement BDD Step Definition**
   - Calls: `claude -p "Implement a SpecFlow BDD step definition for..."`
   - Creates/updates `*Steps.cs` file in `tests/CareSync.Specs/StepDefinitions/`
   - Adds `[Given/When/Then]` attribute with step pattern
   - Implements method with REAL code (no placeholders)

### 2. **Implement Business Logic**
   - Calls: `claude -p "Implement the business logic for..."`
   - Creates/updates service class in `src/3-Infrastructure/.../Services/`
   - Adds proper error handling, logging, validation
   - Follows Clean Architecture and DDD principles

### 3. **Run Tests**
   - Executes: `dotnet build`
   - Executes: `dotnet test --no-build`
   - Verifies implementation works

### 4. **Update Database**
   - Marks task as Completed (if tests pass) or Failed
   - Records BDD step file and method name
   - Logs all work accomplished

## 📊 Example Output

```
================================================================================
[Claude-Agent-1] NEW TASK ASSIGNED
================================================================================
Task ID:  123e4567-e89b-12d3-a456-426614174000
Feature:  Translation Services
Scenario: Translate message to recipient's preferred language
Step:     Given user "Maria" has preferred language set to "Spanish"
================================================================================

================================================================================
STEP 1: BDD STEP DEFINITION
================================================================================
[Claude-Agent-1] Implementing BDD step with Claude Code...
[Claude executing: claude -p "Implement a SpecFlow BDD step definition..."]

================================================================================
STEP 2: BUSINESS LOGIC
================================================================================
[Claude-Agent-1] Implementing business logic with Claude Code...
[Claude executing: claude -p "Implement the business logic..."]

================================================================================
STEP 3: BUILD & TEST
================================================================================
[Claude-Agent-1] Running build and tests...
Build: SUCCESS
Tests: PASSED

================================================================================
[Claude-Agent-1] TASK COMPLETED
================================================================================

================================================================================
PROGRESS: 1 completed | 0 failed
================================================================================
```

## 🎯 Current Statistics

Check implementation progress:

```bash
cd ~/projects/gherkin-tracker
python3 agent_system.py stats
```

Example output:
```
Total tasks:              11,692
Completed:                28 (0.2%)
Pending:                  11,664 (99.8%)
BDD steps implemented:    28 (0.2%)
Business logic impl:      0 (0.0%)
Fully implemented:        0 (0.0%)
```

## ⚠️ Important Notes

### Claude Code Prompts

The agent sends two prompts per task:

**Prompt 1 - BDD Step Definition:**
```
Implement a SpecFlow BDD step definition for this Gherkin step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Requirements:
1. Create or update the step definition file
2. Use the appropriate [Given/When/Then] attribute
3. Implement with REAL code (no placeholders)
4. Call appropriate service methods
5. Add proper assertions for Then steps
...
```

**Prompt 2 - Business Logic:**
```
Implement the business logic required for this feature step:

Feature: {feature_name}
Step: {step_text}

Requirements:
1. Identify or create the appropriate service class
2. Implement necessary business logic method
3. REAL implementation (no placeholders)
4. Add proper error handling and logging
...
```

### Execution Time

- Each task takes 1-5 minutes depending on complexity
- Claude Code may need to read existing files to maintain patterns
- Build and test execution adds 30-60 seconds per task

### Monitoring Progress

The agent system tracks:
- Tasks completed vs failed
- BDD step definitions created
- Business logic implemented
- Build and test results
- Time taken per task

All work is logged in the database:
```sql
SELECT * FROM agent_task_history
ORDER BY started_at DESC
LIMIT 10;
```

## 🛠️ Troubleshooting

### "No more tasks available"

Check pending tasks:
```sql
SELECT COUNT(*) FROM task WHERE status = 'Pending';
```

### Claude Code errors

Check Claude Code is working:
```bash
cd /Users/srowe/RiderProjects/caresync
claude -p "Show me the project structure"
```

### Build failures

The agent records build output in `agent_task_history.work_accomplished`.

View failed tasks:
```sql
SELECT
    t.task_name,
    h.work_accomplished,
    h.build_succeeded,
    h.tests_passed
FROM task t
JOIN agent_task_history h ON t.id = h.task_id
WHERE t.status = 'Failed'
ORDER BY h.started_at DESC;
```

### Database connection issues

Verify PostgreSQL is running:
```bash
/usr/local/opt/postgresql@17/bin/pg_isready
```

Start if needed:
```bash
brew services start postgresql@17
```

## 📈 Progress Tracking

### View Feature Progress

```sql
SELECT * FROM vw_feature_bdd_progress
ORDER BY full_completion_pct DESC;
```

### View Implementation Status

```sql
SELECT
    implementation_status,
    COUNT(*) as count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 1) as pct
FROM vw_bdd_implementation_status
GROUP BY implementation_status;
```

### View Agent Performance

```sql
SELECT
    a.name,
    COUNT(h.id) as tasks_completed,
    ROUND(AVG(h.actual_minutes), 1) as avg_minutes,
    SUM(CASE WHEN h.tests_passed THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN NOT h.tests_passed THEN 1 ELSE 0 END) as failed
FROM agent a
JOIN agent_task_history h ON a.id = h.agent_id
WHERE h.status = 'Completed'
GROUP BY a.name;
```

## 🎮 Advanced Usage

### Custom Agent Name

Modify `agent_claude.py` to set custom agent name:
```python
agent_name = "My-Custom-Agent"
```

### Adjust Timeout

Claude Code timeout per prompt (default 300 seconds):
```python
result = self.run_claude(prompt, timeout=600)  # 10 minutes
```

### Filter by Feature

To only implement specific features, modify the database:
```sql
-- Only process Translation Services feature
UPDATE task SET priority = 100
WHERE step_id IN (
    SELECT st.id FROM step st
    JOIN scenario_step ss ON st.id = ss.step_id
    JOIN scenario sc ON ss.scenario_id = sc.id
    JOIN feature f ON sc.feature_id = f.id
    WHERE f.feature_name = 'Translation Services'
);
```

## 🔄 Resuming Work

The agent system automatically resumes from where it left off:
- Picks up next pending task
- Skips already completed tasks
- Can be stopped and restarted anytime (Ctrl+C)

## 📝 Logging

All Claude Code output is captured in the database:
```sql
SELECT
    task_name,
    work_accomplished,
    started_at,
    completed_at,
    actual_minutes
FROM agent_task_history
ORDER BY started_at DESC
LIMIT 5;
```

## 🚨 Safety Features

- Database transactions ensure no partial updates
- Failed tasks are marked and can be retried
- Build/test failures don't stop the agent
- Original Gherkin features are never modified
- All work is version controlled in Git

## 🎯 Next Steps

After running the agent:

1. **Review Generated Code**
   - Check step definitions in `tests/CareSync.Specs/StepDefinitions/`
   - Review services in `src/3-Infrastructure/.../Services/`

2. **Run Full Test Suite**
   ```bash
   cd /Users/srowe/RiderProjects/caresync
   dotnet test
   ```

3. **Check Coverage**
   ```bash
   cd ~/projects/gherkin-tracker
   python3 agent_system.py stats
   ```

4. **Commit Changes**
   ```bash
   cd /Users/srowe/RiderProjects/caresync
   git status
   git add .
   git commit -m "feat: Implement BDD steps via Claude Code agent"
   ```

## 📚 References

- Agent System: `~/projects/gherkin-tracker/agent_claude.py`
- Database Schema: `~/projects/gherkin-tracker/scripts/02-create-schema.sql`
- BDD Tracking: `~/projects/gherkin-tracker/scripts/03-add-bdd-tracking.sql`
- Documentation: `~/projects/gherkin-tracker/AGENT_SYSTEM.md`
