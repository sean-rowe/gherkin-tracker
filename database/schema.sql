-- CareSync Project Management Database Schema
-- Tracks Gherkin features, scenarios, steps, and implementation tasks

-- ============================================================================
-- TABLE: Project
-- Top-level container for all project requirements and specifications
-- ============================================================================
CREATE TABLE Project (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    Name NVARCHAR(255) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    TechnicalSpecs NVARCHAR(MAX) NULL,
    BusinessRequirements NVARCHAR(MAX) NULL,
    TargetPlatforms NVARCHAR(500) NULL,
    TechnologyStack NVARCHAR(MAX) NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy NVARCHAR(255) NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT UQ_Project_Name UNIQUE (Name)
);

-- ============================================================================
-- TABLE: Epic
-- Agile epic containing multiple features
-- ============================================================================
CREATE TABLE Epic (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProjectId UNIQUEIDENTIFIER NOT NULL,
    Name NVARCHAR(500) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    BusinessValue NVARCHAR(MAX) NULL,
    AcceptanceCriteria NVARCHAR(MAX) NULL,
    Priority INT NOT NULL DEFAULT 0, -- Higher number = higher priority
    Status NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked
    StartDate DATETIME2 NULL,
    TargetDate DATETIME2 NULL,
    CompletedDate DATETIME2 NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_Epic_Project FOREIGN KEY (ProjectId) REFERENCES Project(Id),
    INDEX IX_Epic_ProjectId (ProjectId),
    INDEX IX_Epic_Status (Status),
    INDEX IX_Epic_Priority (Priority)
);

-- ============================================================================
-- TABLE: Feature
-- Gherkin Feature - maps to .feature files
-- Contains: Feature: <name> / As a <role> I want <goal> So that <benefit>
-- ============================================================================
CREATE TABLE Feature (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    EpicId UNIQUEIDENTIFIER NULL, -- Optional: may not belong to an epic
    ProjectId UNIQUEIDENTIFIER NOT NULL,
    FileName NVARCHAR(500) NOT NULL, -- e.g., "UserAuthentication.feature"
    FilePath NVARCHAR(1000) NULL, -- Relative path in project
    FeatureName NVARCHAR(500) NOT NULL,
    AsA NVARCHAR(500) NULL, -- "As a <role>"
    IWant NVARCHAR(1000) NULL, -- "I want <goal>"
    SoThat NVARCHAR(1000) NULL, -- "So that <benefit>"
    Description NVARCHAR(MAX) NULL, -- Additional feature documentation
    Background NVARCHAR(MAX) NULL, -- Gherkin Background steps (common setup)
    Tags NVARCHAR(1000) NULL, -- Comma-separated tags (e.g., "@smoke, @critical")
    Priority INT NOT NULL DEFAULT 0,
    Status NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_Feature_Epic FOREIGN KEY (EpicId) REFERENCES Epic(Id),
    CONSTRAINT FK_Feature_Project FOREIGN KEY (ProjectId) REFERENCES Project(Id),
    CONSTRAINT UQ_Feature_FileName_Project UNIQUE (FileName, ProjectId),
    INDEX IX_Feature_EpicId (EpicId),
    INDEX IX_Feature_ProjectId (ProjectId),
    INDEX IX_Feature_Status (Status)
);

-- ============================================================================
-- TABLE: Scenario
-- Gherkin Scenario - business-level user interaction
-- Written as user actions: "the user does X", "the system is in X state"
-- ============================================================================
CREATE TABLE Scenario (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    FeatureId UNIQUEIDENTIFIER NOT NULL,
    ScenarioName NVARCHAR(500) NOT NULL,
    Description NVARCHAR(MAX) NULL, -- Business perspective description
    ScenarioType NVARCHAR(50) NOT NULL DEFAULT 'Scenario', -- Scenario, ScenarioOutline
    Tags NVARCHAR(1000) NULL, -- Comma-separated tags
    DisplayOrder INT NOT NULL, -- Order within the feature file
    Priority INT NOT NULL DEFAULT 0,
    Status NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked, Failed
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_Scenario_Feature FOREIGN KEY (FeatureId) REFERENCES Feature(Id) ON DELETE CASCADE,
    INDEX IX_Scenario_FeatureId (FeatureId),
    INDEX IX_Scenario_Status (Status),
    INDEX IX_Scenario_DisplayOrder (DisplayOrder)
);

-- ============================================================================
-- TABLE: Step
-- Reusable Gherkin steps (Given/When/Then/And/But)
-- Deduplicated to enable step reuse across scenarios
-- ============================================================================
CREATE TABLE Step (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    StepType NVARCHAR(20) NOT NULL, -- Given, When, Then, And, But
    StepText NVARCHAR(2000) NOT NULL, -- Parameterized step text with <placeholders>
    Description NVARCHAR(MAX) NULL, -- Technical description of what this step does
    IsReusable BIT NOT NULL DEFAULT 1, -- Whether this step can be reused
    ImplementationNotes NVARCHAR(MAX) NULL, -- Notes on how to implement
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UsageCount INT NOT NULL DEFAULT 0, -- Track how many scenarios use this step
    CONSTRAINT CHK_Step_StepType CHECK (StepType IN ('Given', 'When', 'Then', 'And', 'But', 'Example')),
    INDEX IX_Step_StepType (StepType),
    INDEX IX_Step_UsageCount (UsageCount)
);

-- ============================================================================
-- TABLE: ScenarioStep
-- Maps scenarios to steps in order
-- Enables step reuse while maintaining scenario-specific order
-- ============================================================================
CREATE TABLE ScenarioStep (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ScenarioId UNIQUEIDENTIFIER NOT NULL,
    StepId UNIQUEIDENTIFIER NOT NULL,
    DisplayOrder INT NOT NULL, -- Order of step within the scenario
    Parameters NVARCHAR(MAX) NULL, -- JSON or delimited string of parameter values
    ExampleValues NVARCHAR(MAX) NULL, -- For Scenario Outlines: example data
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_ScenarioStep_Scenario FOREIGN KEY (ScenarioId) REFERENCES Scenario(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ScenarioStep_Step FOREIGN KEY (StepId) REFERENCES Step(Id),
    CONSTRAINT UQ_ScenarioStep_Order UNIQUE (ScenarioId, DisplayOrder),
    INDEX IX_ScenarioStep_ScenarioId (ScenarioId),
    INDEX IX_ScenarioStep_StepId (StepId)
);

-- ============================================================================
-- TABLE: Task
-- Implementation task for a step
-- One task per step (1:1 relationship)
-- ============================================================================
CREATE TABLE Task (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    StepId UNIQUEIDENTIFIER NOT NULL,
    TaskName NVARCHAR(500) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    ImplementationDetails NVARCHAR(MAX) NULL, -- Detailed implementation instructions
    CodeLocation NVARCHAR(1000) NULL, -- File path where implementation exists
    Status NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked, Failed
    Priority INT NOT NULL DEFAULT 0,
    AssignedAgentId UNIQUEIDENTIFIER NULL, -- Currently assigned agent
    StartedAt DATETIME2 NULL,
    CompletedAt DATETIME2 NULL,
    EstimatedMinutes INT NULL,
    ActualMinutes INT NULL,
    Notes NVARCHAR(MAX) NULL, -- Working notes from agents
    ErrorLog NVARCHAR(MAX) NULL, -- Any errors encountered during implementation
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_Task_Step FOREIGN KEY (StepId) REFERENCES Step(Id),
    CONSTRAINT UQ_Task_StepId UNIQUE (StepId), -- One task per step
    INDEX IX_Task_Status (Status),
    INDEX IX_Task_AssignedAgentId (AssignedAgentId),
    INDEX IX_Task_Priority (Priority)
);

-- ============================================================================
-- TABLE: Agent
-- Tracks autonomous agents working on tasks
-- ============================================================================
CREATE TABLE Agent (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    AgentName NVARCHAR(255) NOT NULL,
    AgentType NVARCHAR(100) NOT NULL, -- e.g., "general-purpose", "Explore", "Plan"
    CurrentTaskId UNIQUEIDENTIFIER NULL,
    Status NVARCHAR(50) NOT NULL DEFAULT 'Idle', -- Idle, Working, Completed, Failed, Terminated
    StartedAt DATETIME2 NULL,
    CompletedAt DATETIME2 NULL,
    LastHeartbeat DATETIME2 NULL, -- Track if agent is still alive
    WorkLog NVARCHAR(MAX) NULL, -- Detailed log of what the agent accomplished
    ResultSummary NVARCHAR(MAX) NULL, -- Summary of results for next agent
    ErrorMessage NVARCHAR(MAX) NULL, -- Error if agent failed
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_Agent_Task FOREIGN KEY (CurrentTaskId) REFERENCES Task(Id),
    INDEX IX_Agent_Status (Status),
    INDEX IX_Agent_CurrentTaskId (CurrentTaskId)
);

-- ============================================================================
-- TABLE: AgentTaskHistory
-- Historical record of agent task assignments
-- ============================================================================
CREATE TABLE AgentTaskHistory (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    AgentId UNIQUEIDENTIFIER NOT NULL,
    TaskId UNIQUEIDENTIFIER NOT NULL,
    StartedAt DATETIME2 NOT NULL,
    CompletedAt DATETIME2 NULL,
    Status NVARCHAR(50) NOT NULL, -- InProgress, Completed, Failed, Abandoned
    WorkAccomplished NVARCHAR(MAX) NULL,
    NextSteps NVARCHAR(MAX) NULL, -- Notes for next agent
    FilesModified NVARCHAR(MAX) NULL, -- List of files changed
    BuildSucceeded BIT NULL,
    TestsPassed BIT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_AgentTaskHistory_Agent FOREIGN KEY (AgentId) REFERENCES Agent(Id),
    CONSTRAINT FK_AgentTaskHistory_Task FOREIGN KEY (TaskId) REFERENCES Task(Id),
    INDEX IX_AgentTaskHistory_AgentId (AgentId),
    INDEX IX_AgentTaskHistory_TaskId (TaskId),
    INDEX IX_AgentTaskHistory_Status (Status)
);

-- ============================================================================
-- Add foreign key from Task to Agent (after Agent table is created)
-- ============================================================================
ALTER TABLE Task
ADD CONSTRAINT FK_Task_Agent FOREIGN KEY (AssignedAgentId) REFERENCES Agent(Id);

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Complete Feature with all scenarios and steps
GO
CREATE VIEW vw_FeatureComplete AS
SELECT
    f.Id AS FeatureId,
    f.FeatureName,
    f.FileName,
    f.AsA,
    f.IWant,
    f.SoThat,
    s.Id AS ScenarioId,
    s.ScenarioName,
    s.DisplayOrder AS ScenarioOrder,
    st.Id AS StepId,
    st.StepType,
    st.StepText,
    ss.DisplayOrder AS StepOrder,
    ss.Parameters,
    t.Id AS TaskId,
    t.Status AS TaskStatus,
    t.AssignedAgentId
FROM Feature f
LEFT JOIN Scenario s ON f.Id = s.FeatureId
LEFT JOIN ScenarioStep ss ON s.Id = ss.ScenarioId
LEFT JOIN Step st ON ss.StepId = st.Id
LEFT JOIN Task t ON st.Id = t.StepId
WHERE f.IsActive = 1;

GO
-- View: Task work queue (incomplete tasks ordered by priority)
CREATE VIEW vw_TaskWorkQueue AS
SELECT
    t.Id AS TaskId,
    t.TaskName,
    t.Status,
    t.Priority,
    t.AssignedAgentId,
    st.StepType,
    st.StepText,
    s.ScenarioName,
    f.FeatureName,
    f.FileName
FROM Task t
INNER JOIN Step st ON t.StepId = st.Id
INNER JOIN ScenarioStep ss ON st.Id = ss.StepId
INNER JOIN Scenario s ON ss.ScenarioId = s.Id
INNER JOIN Feature f ON s.FeatureId = f.Id
WHERE t.Status IN ('Pending', 'InProgress', 'Blocked')
AND f.IsActive = 1;

GO
-- View: Agent current workload
CREATE VIEW vw_AgentWorkload AS
SELECT
    a.Id AS AgentId,
    a.AgentName,
    a.AgentType,
    a.Status,
    a.StartedAt,
    a.LastHeartbeat,
    t.TaskName,
    t.Status AS TaskStatus,
    DATEDIFF(MINUTE, a.StartedAt, GETUTCDATE()) AS MinutesWorking
FROM Agent a
LEFT JOIN Task t ON a.CurrentTaskId = t.Id
WHERE a.Status IN ('Working', 'Idle');

GO
-- View: Feature completion statistics
CREATE VIEW vw_FeatureProgress AS
SELECT
    f.Id AS FeatureId,
    f.FeatureName,
    f.FileName,
    COUNT(DISTINCT s.Id) AS TotalScenarios,
    COUNT(DISTINCT CASE WHEN s.Status = 'Completed' THEN s.Id END) AS CompletedScenarios,
    COUNT(DISTINCT t.Id) AS TotalTasks,
    COUNT(DISTINCT CASE WHEN t.Status = 'Completed' THEN t.Id END) AS CompletedTasks,
    CAST(COUNT(DISTINCT CASE WHEN t.Status = 'Completed' THEN t.Id END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT t.Id), 0) * 100 AS CompletionPercentage
FROM Feature f
LEFT JOIN Scenario s ON f.Id = s.FeatureId
LEFT JOIN ScenarioStep ss ON s.Id = ss.ScenarioId
LEFT JOIN Step st ON ss.StepId = st.Id
LEFT JOIN Task t ON st.Id = t.StepId
WHERE f.IsActive = 1
GROUP BY f.Id, f.FeatureName, f.FileName;

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

GO
-- Procedure: Assign task to agent
CREATE PROCEDURE sp_AssignTaskToAgent
    @TaskId UNIQUEIDENTIFIER,
    @AgentId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    -- Update task
    UPDATE Task
    SET AssignedAgentId = @AgentId,
        Status = 'InProgress',
        StartedAt = GETUTCDATE(),
        UpdatedAt = GETUTCDATE()
    WHERE Id = @TaskId;

    -- Update agent
    UPDATE Agent
    SET CurrentTaskId = @TaskId,
        Status = 'Working',
        StartedAt = GETUTCDATE(),
        LastHeartbeat = GETUTCDATE(),
        UpdatedAt = GETUTCDATE()
    WHERE Id = @AgentId;

    -- Create history record
    INSERT INTO AgentTaskHistory (AgentId, TaskId, StartedAt, Status)
    VALUES (@AgentId, @TaskId, GETUTCDATE(), 'InProgress');

    COMMIT TRANSACTION;
END;

GO
-- Procedure: Complete task
CREATE PROCEDURE sp_CompleteTask
    @TaskId UNIQUEIDENTIFIER,
    @AgentId UNIQUEIDENTIFIER,
    @WorkAccomplished NVARCHAR(MAX),
    @BuildSucceeded BIT,
    @TestsPassed BIT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    -- Update task
    UPDATE Task
    SET Status = 'Completed',
        CompletedAt = GETUTCDATE(),
        UpdatedAt = GETUTCDATE(),
        ActualMinutes = DATEDIFF(MINUTE, StartedAt, GETUTCDATE())
    WHERE Id = @TaskId;

    -- Update agent
    UPDATE Agent
    SET Status = 'Completed',
        CurrentTaskId = NULL,
        CompletedAt = GETUTCDATE(),
        UpdatedAt = GETUTCDATE()
    WHERE Id = @AgentId;

    -- Update history
    UPDATE AgentTaskHistory
    SET CompletedAt = GETUTCDATE(),
        Status = 'Completed',
        WorkAccomplished = @WorkAccomplished,
        BuildSucceeded = @BuildSucceeded,
        TestsPassed = @TestsPassed
    WHERE AgentId = @AgentId AND TaskId = @TaskId AND CompletedAt IS NULL;

    COMMIT TRANSACTION;
END;

GO
-- Procedure: Get next available task
CREATE PROCEDURE sp_GetNextTask
    @AgentType NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        t.*,
        st.StepType,
        st.StepText,
        s.ScenarioName,
        f.FeatureName
    FROM Task t
    INNER JOIN Step st ON t.StepId = st.Id
    INNER JOIN ScenarioStep ss ON st.Id = ss.StepId
    INNER JOIN Scenario s ON ss.ScenarioId = s.Id
    INNER JOIN Feature f ON s.FeatureId = f.Id
    WHERE t.Status = 'Pending'
    AND t.AssignedAgentId IS NULL
    AND f.IsActive = 1
    ORDER BY t.Priority DESC, t.CreatedAt ASC;
END;
