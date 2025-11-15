# CareSync Project Management Database

This database tracks Gherkin features, scenarios, steps, and implementation tasks for the CareSync project. It enables automated agent-based development where AI agents can pick up tasks, work on them, and track progress.

## Quick Start

### 1. Install Docker

If Docker is not installed:
```bash
brew install --cask docker
```

Start Docker Desktop from Applications.

### 2. Setup Database

```bash
cd database
./setup-project-db.sh
```

This will:
- Start MSSQL Server in Docker
- Create the `CareSyncProject` database
- Create all tables, views, and stored procedures

## Database Schema

### Tables

#### Project
Top-level project container with requirements and specifications.

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| Name | NVARCHAR(255) | Project name (unique) |
| Description | NVARCHAR(MAX) | Project description |
| TechnicalSpecs | NVARCHAR(MAX) | Technical specifications |
| BusinessRequirements | NVARCHAR(MAX) | Business requirements |
| TargetPlatforms | NVARCHAR(500) | Target platforms (iOS, Android, Web) |
| TechnologyStack | NVARCHAR(MAX) | Technology stack details |

#### Epic
Agile epic containing multiple features.

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| ProjectId | UNIQUEIDENTIFIER | Foreign key to Project |
| Name | NVARCHAR(500) | Epic name |
| Description | NVARCHAR(MAX) | Epic description |
| Priority | INT | Priority (higher = more important) |
| Status | NVARCHAR(50) | Pending, InProgress, Completed, Blocked |

#### Feature
Gherkin feature mapping to .feature files.

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| EpicId | UNIQUEIDENTIFIER | Foreign key to Epic (optional) |
| ProjectId | UNIQUEIDENTIFIER | Foreign key to Project |
| FileName | NVARCHAR(500) | Feature file name |
| FilePath | NVARCHAR(1000) | Relative path in project |
| FeatureName | NVARCHAR(500) | Feature name |
| AsA | NVARCHAR(500) | "As a <role>" |
| IWant | NVARCHAR(1000) | "I want <goal>" |
| SoThat | NVARCHAR(1000) | "So that <benefit>" |
| Description | NVARCHAR(MAX) | Feature documentation |
| Background | NVARCHAR(MAX) | Gherkin background steps |
| Tags | NVARCHAR(1000) | Comma-separated tags |

#### Scenario
Gherkin scenario within a feature.

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| FeatureId | UNIQUEIDENTIFIER | Foreign key to Feature |
| ScenarioName | NVARCHAR(500) | Scenario name |
| Description | NVARCHAR(MAX) | Business perspective description |
| ScenarioType | NVARCHAR(50) | Scenario or ScenarioOutline |
| Tags | NVARCHAR(1000) | Comma-separated tags |
| DisplayOrder | INT | Order within feature file |

#### Step
Reusable Gherkin steps (Given/When/Then/And/But).

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| StepType | NVARCHAR(20) | Given, When, Then, And, But, Example |
| StepText | NVARCHAR(2000) | Parameterized step text with <placeholders> |
| Description | NVARCHAR(MAX) | Technical description |
| IsReusable | BIT | Whether step can be reused |
| UsageCount | INT | How many scenarios use this step |

#### ScenarioStep
Maps scenarios to steps in order (enables step reuse).

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| ScenarioId | UNIQUEIDENTIFIER | Foreign key to Scenario |
| StepId | UNIQUEIDENTIFIER | Foreign key to Step |
| DisplayOrder | INT | Order within scenario |
| Parameters | NVARCHAR(MAX) | Parameter values for this instance |
| ExampleValues | NVARCHAR(MAX) | For Scenario Outlines |

#### Task
Implementation task for a step (1:1 relationship).

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| StepId | UNIQUEIDENTIFIER | Foreign key to Step (unique) |
| TaskName | NVARCHAR(500) | Task name |
| Description | NVARCHAR(MAX) | Task description |
| ImplementationDetails | NVARCHAR(MAX) | Detailed implementation instructions |
| CodeLocation | NVARCHAR(1000) | File path where implementation exists |
| Status | NVARCHAR(50) | Pending, InProgress, Completed, Blocked, Failed |
| AssignedAgentId | UNIQUEIDENTIFIER | Currently assigned agent |
| Notes | NVARCHAR(MAX) | Working notes from agents |

#### Agent
Autonomous agents working on tasks.

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| AgentName | NVARCHAR(255) | Agent name |
| AgentType | NVARCHAR(100) | Agent type (general-purpose, Explore, Plan) |
| CurrentTaskId | UNIQUEIDENTIFIER | Currently assigned task |
| Status | NVARCHAR(50) | Idle, Working, Completed, Failed, Terminated |
| LastHeartbeat | DATETIME2 | Track if agent is still alive |
| WorkLog | NVARCHAR(MAX) | Detailed log of work accomplished |
| ResultSummary | NVARCHAR(MAX) | Summary for next agent |

#### AgentTaskHistory
Historical record of agent task assignments.

| Column | Type | Description |
|--------|------|-------------|
| Id | UNIQUEIDENTIFIER | Primary key |
| AgentId | UNIQUEIDENTIFIER | Foreign key to Agent |
| TaskId | UNIQUEIDENTIFIER | Foreign key to Task |
| StartedAt | DATETIME2 | When agent started |
| CompletedAt | DATETIME2 | When agent finished |
| Status | NVARCHAR(50) | InProgress, Completed, Failed, Abandoned |
| WorkAccomplished | NVARCHAR(MAX) | What the agent did |
| NextSteps | NVARCHAR(MAX) | Notes for next agent |
| FilesModified | NVARCHAR(MAX) | List of files changed |
| BuildSucceeded | BIT | Whether build passed |
| TestsPassed | BIT | Whether tests passed |

### Views

#### vw_FeatureComplete
Complete feature view with all scenarios and steps.

#### vw_TaskWorkQueue
Incomplete tasks ordered by priority.

#### vw_AgentWorkload
Current agent assignments and workload.

#### vw_FeatureProgress
Feature completion statistics.

### Stored Procedures

#### sp_AssignTaskToAgent
```sql
EXEC sp_AssignTaskToAgent
    @TaskId = '<task-guid>',
    @AgentId = '<agent-guid>';
```

#### sp_CompleteTask
```sql
EXEC sp_CompleteTask
    @TaskId = '<task-guid>',
    @AgentId = '<agent-guid>',
    @WorkAccomplished = 'Summary of work',
    @BuildSucceeded = 1,
    @TestsPassed = 1;
```

#### sp_GetNextTask
```sql
EXEC sp_GetNextTask @AgentType = 'general-purpose';
```

## Connection Details

**Server:** localhost,1434
**Database:** CareSyncProject
**Username:** sa
**Password:** CareSync_2024_Strong!

### Connect using sqlcmd:
```bash
docker exec -it caresync-mssql /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P 'CareSync_2024_Strong!' \
    -d CareSyncProject
```

### Connect from C#:
```csharp
string connectionString = "Server=localhost,1434;Database=CareSyncProject;User Id=sa;Password=CareSync_2024_Strong!;TrustServerCertificate=True;";
```

## Workflow

### 1. Import Gherkin Features
Parse .feature files and import into database:
- Create Project record
- Create Feature records from .feature files
- Create Scenario records
- Create Step records (deduplicated)
- Create ScenarioStep mappings
- Create Task records for each step

### 2. Mark Completed Tasks
Scan codebase for implemented features and mark tasks as completed.

### 3. Agent Execution
Agents pick up tasks from the work queue:
1. Get next task: `sp_GetNextTask`
2. Assign to agent: `sp_AssignTaskToAgent`
3. Agent works on task
4. Complete task: `sp_CompleteTask`

## Next Steps

1. **Install Docker** (if not already installed)
2. **Run `./setup-project-db.sh`** to create database
3. **Import Gherkin features** from `tests/CareSync.Specs/Features/`
4. **Mark completed tasks** based on implementation status
5. **Start agent execution** system

## Management Commands

### Start Database
```bash
cd database
docker-compose up -d
```

### Stop Database
```bash
cd database
docker-compose down
```

### Stop and Remove All Data
```bash
cd database
docker-compose down -v
```

### View Logs
```bash
docker logs caresync-mssql
```

### Backup Database
```bash
docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P 'CareSync_2024_Strong!' \
    -Q "BACKUP DATABASE CareSyncProject TO DISK='/var/opt/mssql/backup/CareSyncProject.bak'"
```

### Restore Database
```bash
docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P 'CareSync_2024_Strong!' \
    -Q "RESTORE DATABASE CareSyncProject FROM DISK='/var/opt/mssql/backup/CareSyncProject.bak' WITH REPLACE"
```
