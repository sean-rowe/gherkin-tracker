-- CareSync Audit and Security Configuration Script
-- Creates audit tables, row-level security, and data retention policies

USE CareSync;
GO

-- =============================================
-- Audit Schema Tables
-- =============================================

-- Comprehensive audit log table
CREATE TABLE [Audit].[AuditLog] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [EntityType] NVARCHAR(100) NOT NULL,
    [EntityId] UNIQUEIDENTIFIER NOT NULL,
    [UserId] UNIQUEIDENTIFIER NULL,
    [UserName] NVARCHAR(256) NULL,
    [Action] NVARCHAR(50) NOT NULL, -- Insert, Update, Delete, Select
    [TableName] NVARCHAR(128) NOT NULL,
    [PrimaryKeyValue] NVARCHAR(256) NOT NULL,
    [OldValues] NVARCHAR(MAX) NULL,
    [NewValues] NVARCHAR(MAX) NULL,
    [ChangedColumns] NVARCHAR(MAX) NULL,
    [IPAddress] NVARCHAR(45) NULL,
    [UserAgent] NVARCHAR(1000) NULL,
    [SessionId] NVARCHAR(256) NULL,
    [CorrelationId] NVARCHAR(256) NULL,
    [Timestamp] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [ApplicationName] NVARCHAR(128) NULL,
    [DatabaseName] NVARCHAR(128) NOT NULL DEFAULT DB_NAME(),
    [HostName] NVARCHAR(128) NULL,
    [AdditionalInfo] NVARCHAR(MAX) NULL
);

-- Partitioning by month for audit logs
CREATE PARTITION FUNCTION [PF_AuditLog_Timestamp] (DATETIMEOFFSET)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', '2024-05-01', '2024-06-01',
    '2024-07-01', '2024-08-01', '2024-09-01', '2024-10-01', '2024-11-01', '2024-12-01',
    '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01', '2025-05-01', '2025-06-01',
    '2025-07-01', '2025-08-01', '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01',
    '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01', '2026-05-01', '2026-06-01',
    '2026-07-01', '2026-08-01', '2026-09-01', '2026-10-01', '2026-11-01', '2026-12-01'
);

CREATE PARTITION SCHEME [PS_AuditLog_Timestamp]
AS PARTITION [PF_AuditLog_Timestamp] ALL TO ([PRIMARY]);

-- Create partitioned clustered index
CREATE CLUSTERED INDEX [IX_AuditLog_Partitioned] 
ON [Audit].[AuditLog] ([Timestamp], [Id])
ON [PS_AuditLog_Timestamp] ([Timestamp]);

CREATE INDEX [IX_AuditLog_TenantId] ON [Audit].[AuditLog] ([TenantId], [Timestamp]);
CREATE INDEX [IX_AuditLog_EntityType] ON [Audit].[AuditLog] ([EntityType], [EntityId]);
CREATE INDEX [IX_AuditLog_UserId] ON [Audit].[AuditLog] ([UserId], [Timestamp]);
CREATE INDEX [IX_AuditLog_Action] ON [Audit].[AuditLog] ([Action], [TableName]);
CREATE INDEX [IX_AuditLog_SessionId] ON [Audit].[AuditLog] ([SessionId]);
GO

-- Security events log for HIPAA compliance
CREATE TABLE [Audit].[SecurityEvents] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [EventType] NVARCHAR(100) NOT NULL, -- Login, Logout, AccessDenied, DataExport, etc.
    [Severity] NVARCHAR(20) NOT NULL DEFAULT 'Information',
    [UserId] UNIQUEIDENTIFIER NULL,
    [UserName] NVARCHAR(256) NULL,
    [IPAddress] NVARCHAR(45) NULL,
    [UserAgent] NVARCHAR(1000) NULL,
    [SessionId] NVARCHAR(256) NULL,
    [Resource] NVARCHAR(500) NULL,
    [Action] NVARCHAR(100) NULL,
    [Result] NVARCHAR(50) NOT NULL, -- Success, Failure, Warning
    [ErrorCode] NVARCHAR(50) NULL,
    [ErrorMessage] NVARCHAR(1000) NULL,
    [AdditionalData] NVARCHAR(MAX) NULL,
    [Timestamp] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [ApplicationName] NVARCHAR(128) NULL,
    [DatabaseName] NVARCHAR(128) NOT NULL DEFAULT DB_NAME()
);

-- Partitioned clustered index for security events
CREATE CLUSTERED INDEX [IX_SecurityEvents_Partitioned] 
ON [Audit].[SecurityEvents] ([Timestamp], [Id])
ON [PS_AuditLog_Timestamp] ([Timestamp]);

CREATE INDEX [IX_SecurityEvents_TenantId] ON [Audit].[SecurityEvents] ([TenantId], [Timestamp]);
CREATE INDEX [IX_SecurityEvents_EventType] ON [Audit].[SecurityEvents] ([EventType], [Severity]);
CREATE INDEX [IX_SecurityEvents_UserId] ON [Audit].[SecurityEvents] ([UserId], [Timestamp]);
CREATE INDEX [IX_SecurityEvents_Result] ON [Audit].[SecurityEvents] ([Result], [Timestamp]);
GO

-- Data access log for PHI access tracking
CREATE TABLE [Audit].[DataAccessLog] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [UserId] UNIQUEIDENTIFIER NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [AccessType] NVARCHAR(50) NOT NULL, -- View, Export, Print, Download
    [DataType] NVARCHAR(100) NOT NULL, -- Symptoms, Medications, Behaviors, etc.
    [RecordCount] INT NOT NULL DEFAULT 1,
    [Purpose] NVARCHAR(200) NULL,
    [IPAddress] NVARCHAR(45) NULL,
    [UserAgent] NVARCHAR(1000) NULL,
    [SessionId] NVARCHAR(256) NULL,
    [Timestamp] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [ApplicationName] NVARCHAR(128) NULL
);

-- Partitioned clustered index for data access log
CREATE CLUSTERED INDEX [IX_DataAccessLog_Partitioned] 
ON [Audit].[DataAccessLog] ([Timestamp], [Id])
ON [PS_AuditLog_Timestamp] ([Timestamp]);

CREATE INDEX [IX_DataAccessLog_TenantId] ON [Audit].[DataAccessLog] ([TenantId], [Timestamp]);
CREATE INDEX [IX_DataAccessLog_UserId] ON [Audit].[DataAccessLog] ([UserId], [Timestamp]);
CREATE INDEX [IX_DataAccessLog_PatientId] ON [Audit].[DataAccessLog] ([PatientId], [Timestamp]);
CREATE INDEX [IX_DataAccessLog_AccessType] ON [Audit].[DataAccessLog] ([AccessType], [DataType]);
GO

-- =============================================
-- Row-Level Security Implementation
-- =============================================

-- Create security predicate function for tenant isolation
CREATE FUNCTION [Security].[fn_TenantAccessPredicate](@TenantId NVARCHAR(128))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS AccessResult
    WHERE 
        @TenantId = CAST(SESSION_CONTEXT(N'TenantId') AS NVARCHAR(128))
        OR IS_MEMBER('CareSync_Admin') = 1
        OR IS_MEMBER('db_owner') = 1
);
GO

-- Create security policies for all tenant-enabled tables
CREATE SECURITY POLICY [Security].[TenantSecurityPolicy]
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Identity].[Users],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Identity].[DeviceRegistrations],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Care].[Patients],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Care].[CareTeams],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Care].[CareTeamMembers],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Care].[CareTeamInvitations],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Care].[EmergencyContacts],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Care].[MedicalHistory],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[TrackingEntries],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[TrackingEntryEdits],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[Symptoms],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[SymptomTriggers],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[Medications],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[MedicationAdherence],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[Behaviors],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Clinical].[ABCEntries],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[Messages],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[Notifications],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[Attachments],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[MessageTranslations],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[EmailTemplates],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[EmailQueue],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Communication].[PushNotificationQueue],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Audit].[AuditLog],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Audit].[SecurityEvents],
ADD FILTER PREDICATE [Security].[fn_TenantAccessPredicate]([TenantId]) ON [Audit].[DataAccessLog]
WITH (STATE = ON);
GO

-- =============================================
-- Audit Triggers for Change Data Capture
-- =============================================

-- Generic audit trigger function
CREATE OR ALTER FUNCTION [Audit].[fn_GetAuditData]
(
    @TableName NVARCHAR(128),
    @Action NVARCHAR(50),
    @OldValues NVARCHAR(MAX),
    @NewValues NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        @TableName AS TableName,
        @Action AS Action,
        @OldValues AS OldValues,
        @NewValues AS NewValues,
        CAST(SESSION_CONTEXT(N'TenantId') AS NVARCHAR(128)) AS TenantId,
        CAST(SESSION_CONTEXT(N'UserId') AS UNIQUEIDENTIFIER) AS UserId,
        CAST(SESSION_CONTEXT(N'UserName') AS NVARCHAR(256)) AS UserName,
        CAST(SESSION_CONTEXT(N'IPAddress') AS NVARCHAR(45)) AS IPAddress,
        CAST(SESSION_CONTEXT(N'UserAgent') AS NVARCHAR(1000)) AS UserAgent,
        CAST(SESSION_CONTEXT(N'SessionId') AS NVARCHAR(256)) AS SessionId,
        CAST(SESSION_CONTEXT(N'CorrelationId') AS NVARCHAR(256)) AS CorrelationId,
        APP_NAME() AS ApplicationName,
        HOST_NAME() AS HostName
);
GO

-- Create audit trigger for Users table
CREATE OR ALTER TRIGGER [Identity].[TR_Users_Audit]
ON [Identity].[Users]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Action NVARCHAR(50);
    DECLARE @OldValues NVARCHAR(MAX);
    DECLARE @NewValues NVARCHAR(MAX);
    
    IF EXISTS(SELECT * FROM inserted) AND EXISTS(SELECT * FROM deleted)
        SET @Action = 'Update';
    ELSE IF EXISTS(SELECT * FROM inserted)
        SET @Action = 'Insert';
    ELSE
        SET @Action = 'Delete';
    
    SELECT @OldValues = (SELECT * FROM deleted FOR JSON AUTO);
    SELECT @NewValues = (SELECT * FROM inserted FOR JSON AUTO);
    
    INSERT INTO [Audit].[AuditLog] 
    (
        TenantId, EntityType, EntityId, UserId, UserName, Action, 
        TableName, PrimaryKeyValue, OldValues, NewValues,
        IPAddress, UserAgent, SessionId, CorrelationId,
        ApplicationName, HostName
    )
    SELECT 
        COALESCE(i.TenantId, d.TenantId),
        'User',
        COALESCE(i.Id, d.Id),
        ad.UserId,
        ad.UserName,
        @Action,
        'Identity.Users',
        CAST(COALESCE(i.Id, d.Id) AS NVARCHAR(256)),
        @OldValues,
        @NewValues,
        ad.IPAddress,
        ad.UserAgent,
        ad.SessionId,
        ad.CorrelationId,
        ad.ApplicationName,
        ad.HostName
    FROM 
        (SELECT * FROM inserted UNION ALL SELECT * FROM deleted) u
        FULL OUTER JOIN inserted i ON u.Id = i.Id
        FULL OUTER JOIN deleted d ON u.Id = d.Id
        CROSS APPLY [Audit].[fn_GetAuditData]('Identity.Users', @Action, @OldValues, @NewValues) ad;
END;
GO

-- =============================================
-- Data Retention Policies
-- =============================================

-- Create data retention configuration table
CREATE TABLE [Audit].[DataRetentionPolicies] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TableName] NVARCHAR(128) NOT NULL,
    [RetentionPeriodMonths] INT NOT NULL,
    [ArchiveBeforeDelete] BIT NOT NULL DEFAULT 1,
    [IsEnabled] BIT NOT NULL DEFAULT 1,
    [LastProcessedDate] DATETIMEOFFSET NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [CreatedBy] NVARCHAR(128) NOT NULL
);

-- Insert default retention policies
INSERT INTO [Audit].[DataRetentionPolicies] (TableName, RetentionPeriodMonths, CreatedBy)
VALUES 
    ('Audit.AuditLog', 84, 'SYSTEM'), -- 7 years for audit logs
    ('Audit.SecurityEvents', 84, 'SYSTEM'), -- 7 years for security events
    ('Audit.DataAccessLog', 84, 'SYSTEM'), -- 7 years for access logs
    ('Clinical.TrackingEntries', 24, 'SYSTEM'), -- 2 years for tracking data
    ('Communication.Messages', 12, 'SYSTEM'), -- 1 year for messages
    ('Communication.Notifications', 6, 'SYSTEM'), -- 6 months for notifications
    ('Communication.EmailQueue', 3, 'SYSTEM'), -- 3 months for email queue
    ('Communication.PushNotificationQueue', 1, 'SYSTEM'); -- 1 month for push notifications
GO

-- Create stored procedure for data archival and cleanup
CREATE OR ALTER PROCEDURE [Audit].[sp_ProcessDataRetention]
    @TableName NVARCHAR(128) = NULL,
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RetentionDate DATETIMEOFFSET;
    DECLARE @RowsAffected INT;
    
    DECLARE retention_cursor CURSOR FOR
    SELECT 
        TableName, 
        DATEADD(MONTH, -RetentionPeriodMonths, SYSDATETIMEOFFSET()) AS RetentionDate
    FROM [Audit].[DataRetentionPolicies]
    WHERE IsEnabled = 1
    AND (@TableName IS NULL OR TableName = @TableName);
    
    OPEN retention_cursor;
    
    FETCH NEXT FROM retention_cursor INTO @TableName, @RetentionDate;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Archive data older than retention period
        SET @SQL = N'
        IF OBJECT_ID(''' + @TableName + '_Archive'') IS NOT NULL
        BEGIN
            INSERT INTO ' + @TableName + '_Archive
            SELECT * FROM ' + @TableName + '
            WHERE CreatedAt < @RetentionDate;
            
            SET @RowsAffected = @@ROWCOUNT;
            
            IF @DryRun = 0
            BEGIN
                DELETE FROM ' + @TableName + '
                WHERE CreatedAt < @RetentionDate;
                
                UPDATE [Audit].[DataRetentionPolicies]
                SET LastProcessedDate = SYSDATETIMEOFFSET()
                WHERE TableName = ''' + @TableName + ''';
            END;
            
            PRINT ''Table: ' + @TableName + ', Rows processed: '' + CAST(@RowsAffected AS NVARCHAR(10)) + '', Dry run: '' + CASE WHEN @DryRun = 1 THEN ''Yes'' ELSE ''No'' END;
        END;';
        
        EXEC sp_executesql @SQL, N'@RetentionDate DATETIMEOFFSET, @RowsAffected INT OUTPUT, @DryRun BIT', 
             @RetentionDate, @RowsAffected OUTPUT, @DryRun;
        
        FETCH NEXT FROM retention_cursor INTO @TableName, @RetentionDate;
    END;
    
    CLOSE retention_cursor;
    DEALLOCATE retention_cursor;
END;
GO

PRINT 'Audit schema and security configuration created successfully';
GO