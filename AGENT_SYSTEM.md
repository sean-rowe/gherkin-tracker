# BDD Implementation Agent System

## Overview

The agent system is an autonomous task execution framework that manages the implementation of BDD (Behavior-Driven Development) steps from Gherkin feature files.

**Current Status:**
- **Total Tasks**: 11,692
- **Completed**: 28 (0.2%)
- **Pending**: 11,664 (99.8%)

## Architecture

### Components

1. **Agent**: Autonomous worker that implements BDD steps
   - Retrieves tasks from queue
   - Implements BDD step definitions
   - Implements business logic
   - Runs tests
   - Reports results

2. **AgentOrchestrator**: Manages multiple agents
   - Creates and coordinates agents
   - Tracks progress
   - Provides statistics

3. **Database**: PostgreSQL tracking system
   - 102 features
   - 1,895 scenarios
   - 11,692 unique steps/tasks

### Task Workflow

```
1. Get Next Task (sp_get_next_task)
   ↓
2. Assign to Agent (sp_assign_task_to_agent)
   ↓
3. Implement BDD Step Definition
   - Create/update *Steps.cs file
   - Add [Given/When/Then] attribute
   - Implement method with real code
   ↓
4. Implement Business Logic
   - Create/update Service class
   - Implement business method
   - Add error handling
   ↓
5. Run Tests
   - dotnet build
   - dotnet test
   ↓
6. Complete Task (sp_complete_task)
   - Mark as Completed or Failed
   - Record BDD file and method
   - Update agent status
```

## Usage

### Check Statistics

```bash
cd ~/projects/gherkin-tracker
python3 agent_system.py stats
```

Output:
```
Total tasks:              11,692
Completed:                28 (0.2%)
Pending:                  11,664 (99.8%)
BDD steps implemented:    28 (0.2%)
Business logic impl:      0 (0.0%)
Fully implemented:        0 (0.0%)
```

### Run Agents (Test Mode)

Process 5 tasks as a test:

```bash
python3 agent_system.py test
```

### Run Sequential Execution

Process all tasks with a single agent:

```bash
python3 agent_system.py run
```

Process specific number of tasks:

```bash
python3 agent_system.py run --max-tasks 100
```

### Run Parallel Execution (Simulated)

Process tasks with multiple agents:

```bash
python3 agent_system.py run --parallel --agents 4 --max-tasks 100
```

## Database Schema

### Key Tables

**task**
- `id`: Task UUID
- `step_id`: Reference to Gherkin step
- `status`: Pending | In Progress | Completed | Failed
- `bdd_implemented`: TRUE if BDD step definition exists
- `business_logic_implemented`: TRUE if service/controller exists
- `bdd_step_file`: Path to step definition file
- `bdd_method_name`: Method name in step definition
- `service_location`: Path to service implementing logic

**agent**
- `id`: Agent UUID
- `name`: Agent name
- `type`: BDD_IMPLEMENTER | other types
- `status`: Idle | Working | Completed | Failed
- `current_task_id`: Currently assigned task

**agent_task_history**
- Tracks all work done by agents
- Includes work accomplished, build/test results
- Continuation notes for resuming work

### Key Views

**vw_bdd_implementation_status**
- Shows implementation status per step
- Categories: FULLY_IMPLEMENTED, BDD_ONLY, BUSINESS_LOGIC_ONLY, NOT_IMPLEMENTED

**vw_tasks_needing_bdd**
- Lists all tasks needing BDD step implementations
- Ordered by priority

**vw_feature_bdd_progress**
- Progress statistics per feature
- BDD completion %, business logic completion %, full completion %

### Stored Procedures

**sp_get_next_task(agent_type)**
- Returns highest priority pending task
- Considers feature, scenario, and step order

**sp_assign_task_to_agent(task_id, agent_id)**
- Assigns task to agent
- Updates task and agent status
- Creates history record

**sp_complete_task(task_id, agent_id, work_accomplished, build_succeeded, tests_passed, bdd_step_file, bdd_method_name)**
- Marks task as complete or failed
- Requires BDD step file and method name for completion
- Updates agent status
- Records work in history

## Implementation Details

### BDD Step Definition

For a step like:
```gherkin
Given user "John" has preferred language set to "English"
```

The agent creates:
```csharp
// File: tests/CareSync.Specs/StepDefinitions/TranslationServicesSteps.cs

[Given(@"user ""(.*)"" has preferred language set to ""(.*)""")]
public void GivenUserHasPreferredLanguageSetTo(string userName, string language)
{
    var user = _userContext.GetUser(userName);
    var languageService = _serviceProvider.GetService<ILanguageService>();
    languageService.SetUserLanguage(user.Id, language);

    // Verify it was set
    var userPrefs = languageService.GetUserLanguagePreference(user.Id);
    userPrefs.Should().Be(language);
}
```

### Business Logic Implementation

The agent also implements the service:
```csharp
// File: src/3-Infrastructure/CareSync.Infrastructure/Services/LanguageService.cs

public class LanguageService : ILanguageService
{
    private readonly IUserRepository _userRepository;
    private readonly ILogger<LanguageService> _logger;

    public void SetUserLanguage(Guid userId, string languageCode)
    {
        var user = await _userRepository.GetByIdAsync(userId);
        if (user == null)
        {
            throw new NotFoundException($"User {userId} not found");
        }

        user.PreferredLanguage = languageCode;
        await _userRepository.UpdateAsync(user);

        _logger.LogInformation(
            "Updated language preference for user {UserId} to {Language}",
            userId, languageCode);
    }
}
```

## Current Limitations

**Note**: The current agent system is a FRAMEWORK ONLY. The actual code generation is stubbed out.

To make it fully functional, you would need to integrate:

1. **LLM Integration** (Claude, GPT-4, etc.)
   - Generate actual C# code for step definitions
   - Generate service implementations
   - Analyze existing code patterns

2. **Build System Integration**
   - Execute `dotnet build`
   - Execute `dotnet test`
   - Parse build/test output

3. **Code Analysis**
   - Parse existing step definitions
   - Detect duplicate implementations
   - Suggest refactoring

4. **Git Integration**
   - Commit implementations
   - Create branches
   - Create pull requests

## Future Enhancements

1. **Parallel Execution**: True multi-processing with worker pool
2. **Incremental Building**: Only rebuild changed projects
3. **Test Isolation**: Run only affected tests
4. **Code Review**: Automated review before marking complete
5. **Continuation Support**: Resume failed/interrupted work
6. **Priority Queue**: Implement feature-based priority
7. **Dependency Detection**: Handle step dependencies
8. **Metrics Dashboard**: Web-based progress monitoring

## Database Queries

### Check Feature Progress

```sql
SELECT * FROM vw_feature_bdd_progress
ORDER BY full_completion_pct DESC;
```

### Find Tasks Needing Work

```sql
SELECT * FROM vw_tasks_needing_bdd
WHERE feature_name = 'Translation Services'
ORDER BY priority DESC, display_order;
```

### Check Implementation Status

```sql
SELECT
    implementation_status,
    COUNT(*) as count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 1) as percentage
FROM vw_bdd_implementation_status
GROUP BY implementation_status;
```

### Agent Performance

```sql
SELECT
    a.name,
    COUNT(h.id) as tasks_completed,
    AVG(h.actual_minutes) as avg_time_minutes,
    SUM(CASE WHEN h.tests_passed THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN NOT h.tests_passed THEN 1 ELSE 0 END) as failed
FROM agent a
JOIN agent_task_history h ON a.id = h.agent_id
GROUP BY a.name
ORDER BY tasks_completed DESC;
```

## Troubleshooting

### Agent shows "No tasks available"

Check if tasks exist:
```sql
SELECT COUNT(*) FROM task WHERE status = 'Pending';
```

### Tasks stuck "In Progress"

Reset stuck tasks:
```sql
UPDATE task SET status = 'Pending', assigned_agent_id = NULL
WHERE status = 'In Progress' AND updated_at < NOW() - INTERVAL '1 hour';
```

### View agent history

```sql
SELECT * FROM agent_task_history
ORDER BY started_at DESC
LIMIT 20;
```

## Contributing

This agent system is designed to be extended. Key extension points:

1. **Agent.implement_bdd_step()**: Replace stub with actual code generation
2. **Agent.implement_business_logic()**: Replace stub with actual implementation
3. **Agent.run_tests()**: Replace stub with actual build/test execution
4. **AgentOrchestrator.run_parallel()**: Implement true parallel execution

## License

Part of the CareSync project. See main project LICENSE.
