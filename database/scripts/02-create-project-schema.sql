-- CareSync Project Management Database Schema
-- Execute this after 01-create-project-database.sql

USE CareSyncProject;
GO

-- ============================================================================
-- TABLE: Project
-- Top-level container for all project requirements and specifications
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Project')
BEGIN
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
    PRINT 'Table Project created';
END
GO

-- ============================================================================
-- TABLE: Epic
-- Agile epic containing multiple features
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Epic')
BEGIN
    CREATE TABLE Epic (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        ProjectId UNIQUEIDENTIFIER NOT NULL,
        Name NVARCHAR(500) NOT NULL,
        Description NVARCHAR(MAX) NULL,
        BusinessValue NVARCHAR(MAX) NULL,
        AcceptanceCriteria NVARCHAR(MAX) NULL,
        Priority INT NOT NULL DEFAULT 0,
        Status NVARCHAR(50) NOT NULL DEFAULT 'Pending',
        StartDate DATETIME2 NULL,
        TargetDate DATETIME2 NULL,
        CompletedDate DATETIME2 NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        IsActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT FK_Epic_Project FOREIGN KEY (ProjectId) REFERENCES Project(Id)
    );
    CREATE INDEX IX_Epic_ProjectId ON Epic(ProjectId);
    CREATE INDEX IX_Epic_Status ON Epic(Status);
    CREATE INDEX IX_Epic_Priority ON Epic(Priority);
    PRINT 'Table Epic created';
END
GO

-- ============================================================================
-- TABLE: Feature
-- Gherkin Feature - maps to .feature files
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Feature')
BEGIN
    CREATE TABLE Feature (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        EpicId UNIQUEIDENTIFIER NULL,
        ProjectId UNIQUEIDENTIFIER NOT NULL,
        FileName NVARCHAR(500) NOT NULL,
        FilePath NVARCHAR(1000) NULL,
        FeatureName NVARCHAR(500) NOT NULL,
        AsA NVARCHAR(500) NULL,
        IWant NVARCHAR(1000) NULL,
        SoThat NVARCHAR(1000) NULL,
        Description NVARCHAR(MAX) NULL,
        Background NVARCHAR(MAX) NULL,
        Tags NVARCHAR(1000) NULL,
        Priority INT NOT NULL DEFAULT 0,
        Status NVARCHAR(50) NOT NULL DEFAULT 'Pending',
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        IsActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT FK_Feature_Epic FOREIGN KEY (EpicId) REFERENCES Epic(Id),
        CONSTRAINT FK_Feature_Project FOREIGN KEY (ProjectId) REFERENCES Project(Id),
        CONSTRAINT UQ_Feature_FileName_Project UNIQUE (FileName, ProjectId)
    );
    CREATE INDEX IX_Feature_EpicId ON Feature(EpicId);
    CREATE INDEX IX_Feature_ProjectId ON Feature(ProjectId);
    CREATE INDEX IX_Feature_Status ON Feature(Status);
    PRINT 'Table Feature created';
END
GO

-- ============================================================================
-- TABLE: Scenario
-- Gherkin Scenario - business-level user interaction
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Scenario')
BEGIN
    CREATE TABLE Scenario (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        FeatureId UNIQUEIDENTIFIER NOT NULL,
        ScenarioName NVARCHAR(500) NOT NULL,
        Description NVARCHAR(MAX) NULL,
        ScenarioType NVARCHAR(50) NOT NULL DEFAULT 'Scenario',
        Tags NVARCHAR(1000) NULL,
        DisplayOrder INT NOT NULL,
        Priority INT NOT NULL DEFAULT 0,
        Status NVARCHAR(50) NOT NULL DEFAULT 'Pending',
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        IsActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT FK_Scenario_Feature FOREIGN KEY (FeatureId) REFERENCES Feature(Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_Scenario_FeatureId ON Scenario(FeatureId);
    CREATE INDEX IX_Scenario_Status ON Scenario(Status);
    CREATE INDEX IX_Scenario_DisplayOrder ON Scenario(DisplayOrder);
    PRINT 'Table Scenario created';
END
GO

-- ============================================================================
-- TABLE: Step
-- Reusable Gherkin steps
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Step')
BEGIN
    CREATE TABLE Step (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        StepType NVARCHAR(20) NOT NULL,
        StepText NVARCHAR(2000) NOT NULL,
        Description NVARCHAR(MAX) NULL,
        IsReusable BIT NOT NULL DEFAULT 1,
        ImplementationNotes NVARCHAR(MAX) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UsageCount INT NOT NULL DEFAULT 0,
        CONSTRAINT CHK_Step_StepType CHECK (StepType IN ('Given', 'When', 'Then', 'And', 'But', 'Example'))
    );
    CREATE INDEX IX_Step_StepType ON Step(StepType);
    CREATE INDEX IX_Step_UsageCount ON Step(UsageCount);
    PRINT 'Table Step created';
END
GO

-- ============================================================================
-- TABLE: ScenarioStep
-- Maps scenarios to steps in order
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ScenarioStep')
BEGIN
    CREATE TABLE ScenarioStep (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        ScenarioId UNIQUEIDENTIFIER NOT NULL,
        StepId UNIQUEIDENTIFIER NOT NULL,
        DisplayOrder INT NOT NULL,
        Parameters NVARCHAR(MAX) NULL,
        ExampleValues NVARCHAR(MAX) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_ScenarioStep_Scenario FOREIGN KEY (ScenarioId) REFERENCES Scenario(Id) ON DELETE CASCADE,
        CONSTRAINT FK_ScenarioStep_Step FOREIGN KEY (StepId) REFERENCES Step(Id),
        CONSTRAINT UQ_ScenarioStep_Order UNIQUE (ScenarioId, DisplayOrder)
    );
    CREATE INDEX IX_ScenarioStep_ScenarioId ON ScenarioStep(ScenarioId);
    CREATE INDEX IX_ScenarioStep_StepId ON ScenarioStep(StepId);
    PRINT 'Table ScenarioStep created';
END
GO

-- ============================================================================
-- TABLE: Task
-- Implementation task for a step
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Task')
BEGIN
    CREATE TABLE Task (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        StepId UNIQUEIDENTIFIER NOT NULL,
        TaskName NVARCHAR(500) NOT NULL,
        Description NVARCHAR(MAX) NULL,
        ImplementationDetails NVARCHAR(MAX) NULL,
        CodeLocation NVARCHAR(1000) NULL,
        Status NVARCHAR(50) NOT NULL DEFAULT 'Pending',
        Priority INT NOT NULL DEFAULT 0,
        AssignedAgentId UNIQUEIDENTIFIER NULL,
        StartedAt DATETIME2 NULL,
        CompletedAt DATETIME2 NULL,
        EstimatedMinutes INT NULL,
        ActualMinutes INT NULL,
        Notes NVARCHAR(MAX) NULL,
        ErrorLog NVARCHAR(MAX) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_Task_Step FOREIGN KEY (StepId) REFERENCES Step(Id),
        CONSTRAINT UQ_Task_StepId UNIQUE (StepId)
    );
    CREATE INDEX IX_Task_Status ON Task(Status);
    CREATE INDEX IX_Task_AssignedAgentId ON Task(AssignedAgentId);
    CREATE INDEX IX_Task_Priority ON Task(Priority);
    PRINT 'Table Task created';
END
GO

-- ============================================================================
-- TABLE: Agent
-- Tracks autonomous agents
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Agent')
BEGIN
    CREATE TABLE Agent (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        AgentName NVARCHAR(255) NOT NULL,
        AgentType NVARCHAR(100) NOT NULL,
        CurrentTaskId UNIQUEIDENTIFIER NULL,
        Status NVARCHAR(50) NOT NULL DEFAULT 'Idle',
        StartedAt DATETIME2 NULL,
        CompletedAt DATETIME2 NULL,
        LastHeartbeat DATETIME2 NULL,
        WorkLog NVARCHAR(MAX) NULL,
        ResultSummary NVARCHAR(MAX) NULL,
        ErrorMessage NVARCHAR(MAX) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX IX_Agent_Status ON Agent(Status);
    CREATE INDEX IX_Agent_CurrentTaskId ON Agent(CurrentTaskId);
    PRINT 'Table Agent created';
END
GO

-- ============================================================================
-- TABLE: AgentTaskHistory
-- Historical record of agent task assignments
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AgentTaskHistory')
BEGIN
    CREATE TABLE AgentTaskHistory (
        Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        AgentId UNIQUEIDENTIFIER NOT NULL,
        TaskId UNIQUEIDENTIFIER NOT NULL,
        StartedAt DATETIME2 NOT NULL,
        CompletedAt DATETIME2 NULL,
        Status NVARCHAR(50) NOT NULL,
        WorkAccomplished NVARCHAR(MAX) NULL,
        NextSteps NVARCHAR(MAX) NULL,
        FilesModified NVARCHAR(MAX) NULL,
        BuildSucceeded BIT NULL,
        TestsPassed BIT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_AgentTaskHistory_Agent FOREIGN KEY (AgentId) REFERENCES Agent(Id),
        CONSTRAINT FK_AgentTaskHistory_Task FOREIGN KEY (TaskId) REFERENCES Task(Id)
    );
    CREATE INDEX IX_AgentTaskHistory_AgentId ON AgentTaskHistory(AgentId);
    CREATE INDEX IX_AgentTaskHistory_TaskId ON AgentTaskHistory(TaskId);
    CREATE INDEX IX_AgentTaskHistory_Status ON AgentTaskHistory(Status);
    PRINT 'Table AgentTaskHistory created';
END
GO

-- Add foreign keys that require both tables to exist
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_Task_Agent')
BEGIN
    ALTER TABLE Task
    ADD CONSTRAINT FK_Task_Agent FOREIGN KEY (AssignedAgentId) REFERENCES Agent(Id);
    PRINT 'FK_Task_Agent created';
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_Agent_Task')
BEGIN
    ALTER TABLE Agent
    ADD CONSTRAINT FK_Agent_Task FOREIGN KEY (CurrentTaskId) REFERENCES Task(Id);
    PRINT 'FK_Agent_Task created';
END
GO

PRINT 'Schema creation completed successfully';
GO
