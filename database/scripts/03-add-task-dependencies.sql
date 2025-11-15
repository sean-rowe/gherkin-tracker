-- ============================================================================
-- Add Task Dependencies and Ordering
-- Enables agents to understand which tasks must complete before others
-- ============================================================================

-- Add dependency tracking to Task table
ALTER TABLE Task ADD DependsOnTaskIds NVARCHAR(MAX) NULL; -- JSON array of task IDs
ALTER TABLE Task ADD BlockedBy NVARCHAR(MAX) NULL; -- Comma-separated list of blocking task IDs
ALTER TABLE Task ADD BlockedReason NVARCHAR(500) NULL; -- Human-readable reason why blocked
ALTER TABLE Task ADD ExecutionOrder INT NULL; -- Suggested order (lower = earlier)
ALTER TABLE Task ADD IsBlocked BIT NOT NULL DEFAULT 0; -- Quick check if task is blocked

-- Index for finding blocked tasks
CREATE INDEX IX_Task_IsBlocked ON Task(IsBlocked);
CREATE INDEX IX_Task_ExecutionOrder ON Task(ExecutionOrder);

-- ============================================================================
-- TABLE: TaskDependency
-- Explicit task dependencies (Task A must complete before Task B)
-- ============================================================================
CREATE TABLE TaskDependency (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    TaskId UNIQUEIDENTIFIER NOT NULL, -- The task that depends on something
    DependsOnTaskId UNIQUEIDENTIFIER NOT NULL, -- The task it depends on
    DependencyType NVARCHAR(50) NOT NULL DEFAULT 'Required', -- Required, Suggested, Optional
    Reason NVARCHAR(500) NULL, -- Why this dependency exists
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_TaskDependency_Task FOREIGN KEY (TaskId) REFERENCES Task(Id) ON DELETE CASCADE,
    CONSTRAINT FK_TaskDependency_DependsOn FOREIGN KEY (DependsOnTaskId) REFERENCES Task(Id),
    CONSTRAINT CHK_TaskDependency_NotSelf CHECK (TaskId <> DependsOnTaskId),
    CONSTRAINT UQ_TaskDependency_Pair UNIQUE (TaskId, DependsOnTaskId),
    INDEX IX_TaskDependency_TaskId (TaskId),
    INDEX IX_TaskDependency_DependsOnTaskId (DependsOnTaskId),
    INDEX IX_TaskDependency_Type (DependencyType)
);

-- ============================================================================
-- VIEW: AvailableTasks
-- Tasks that are ready to be worked on (not blocked, dependencies met)
-- ============================================================================
CREATE VIEW AvailableTasks AS
SELECT 
    t.*,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM TaskDependency td
            JOIN Task dt ON td.DependsOnTaskId = dt.Id
            WHERE td.TaskId = t.Id 
            AND dt.Status NOT IN ('Completed')
            AND td.DependencyType = 'Required'
        ) THEN 1
        ELSE 0
    END AS HasUnmetDependencies
FROM Task t
WHERE t.Status = 'Pending'
AND t.IsActive = 1
AND NOT EXISTS (
    SELECT 1 FROM TaskDependency td
    JOIN Task dt ON td.DependsOnTaskId = dt.Id
    WHERE td.TaskId = t.Id 
    AND dt.Status NOT IN ('Completed')
    AND td.DependencyType = 'Required'
);

-- ============================================================================
-- STORED PROCEDURE: GetNextAvailableTask
-- Returns the highest priority task that has all dependencies met
-- ============================================================================
CREATE PROCEDURE GetNextAvailableTask
    @AgentId UNIQUEIDENTIFIER = NULL,
    @PreferredStepType NVARCHAR(20) = NULL -- 'Given', 'When', 'Then'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Find best task:
    -- 1. No unmet dependencies
    -- 2. Highest priority
    -- 3. Lowest execution order
    -- 4. Preferably matches step type (Given before When before Then)
    
    SELECT TOP 1 
        t.*,
        s.StepType,
        s.StepText,
        sc.ScenarioName,
        f.FeatureName
    FROM Task t
    JOIN Step s ON t.StepId = s.Id
    JOIN ScenarioStep ss ON s.Id = ss.StepId
    JOIN Scenario sc ON ss.ScenarioId = sc.Id
    JOIN Feature f ON sc.FeatureId = f.Id
    WHERE t.Status = 'Pending'
    AND t.IsActive = 1
    AND t.IsBlocked = 0
    AND NOT EXISTS (
        SELECT 1 FROM TaskDependency td
        JOIN Task dt ON td.DependsOnTaskId = dt.Id
        WHERE td.TaskId = t.Id 
        AND dt.Status NOT IN ('Completed')
        AND td.DependencyType = 'Required'
    )
    ORDER BY 
        t.Priority DESC,
        CASE s.StepType 
            WHEN 'Given' THEN 1 
            WHEN 'When' THEN 2 
            WHEN 'Then' THEN 3 
            ELSE 4 
        END ASC,
        t.ExecutionOrder ASC,
        t.CreatedAt ASC;
END;
GO

-- ============================================================================
-- STORED PROCEDURE: AddTaskDependency
-- Adds a dependency between tasks and updates blocked status
-- ============================================================================
CREATE PROCEDURE AddTaskDependency
    @TaskId UNIQUEIDENTIFIER,
    @DependsOnTaskId UNIQUEIDENTIFIER,
    @DependencyType NVARCHAR(50) = 'Required',
    @Reason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Insert dependency
    INSERT INTO TaskDependency (TaskId, DependsOnTaskId, DependencyType, Reason)
    VALUES (@TaskId, @DependsOnTaskId, @DependencyType, @Reason);
    
    -- Update blocked status if dependency is Required and not met
    IF @DependencyType = 'Required'
    BEGIN
        UPDATE Task
        SET IsBlocked = CASE 
            WHEN EXISTS (
                SELECT 1 FROM Task WHERE Id = @DependsOnTaskId AND Status <> 'Completed'
            ) THEN 1
            ELSE 0
        END,
        BlockedReason = CASE 
            WHEN EXISTS (
                SELECT 1 FROM Task WHERE Id = @DependsOnTaskId AND Status <> 'Completed'
            ) THEN 'Waiting for dependency: ' + @Reason
            ELSE NULL
        END
        WHERE Id = @TaskId;
    END;
END;
GO

-- ============================================================================
-- TRIGGER: UpdateBlockedStatus
-- Automatically updates blocked status when dependency tasks complete
-- ============================================================================
CREATE TRIGGER TR_Task_UpdateBlockedStatus
ON Task
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- When a task completes, unblock tasks that depend on it
    IF UPDATE(Status)
    BEGIN
        UPDATE t
        SET IsBlocked = CASE 
            WHEN EXISTS (
                SELECT 1 FROM TaskDependency td
                JOIN Task dt ON td.DependsOnTaskId = dt.Id
                WHERE td.TaskId = t.Id 
                AND dt.Status <> 'Completed'
                AND td.DependencyType = 'Required'
            ) THEN 1
            ELSE 0
        END,
        BlockedReason = CASE 
            WHEN EXISTS (
                SELECT 1 FROM TaskDependency td
                JOIN Task dt ON td.DependsOnTaskId = dt.Id
                WHERE td.TaskId = t.Id 
                AND dt.Status <> 'Completed'
                AND td.DependencyType = 'Required'
            ) THEN 'Has unmet dependencies'
            ELSE NULL
        END
        FROM Task t
        WHERE EXISTS (
            SELECT 1 FROM TaskDependency td
            JOIN inserted i ON td.DependsOnTaskId = i.Id
            WHERE td.TaskId = t.Id
        );
    END;
END;
GO
