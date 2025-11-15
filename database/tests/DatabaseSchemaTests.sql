-- CareSync Database Schema tSQLt Tests
-- BDD-driven tests for database schema validation

USE CareSync;
GO

-- Create test class schema
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'DatabaseSchemaTests')
BEGIN
    EXEC('CREATE SCHEMA [DatabaseSchemaTests]');
END
GO

-- ==============================================
-- Database Configuration Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_database_should_have_hipaa_compliant_configuration]
AS
BEGIN
    -- Given a clean MSSQL database environment
    -- When I execute the database creation script
    -- Then the database should be created with HIPAA-compliant settings
    
    EXEC [tSQLt].[AssertEquals] 'CareSync', DB_NAME(), 'Database name should be CareSync';
    
    -- Verify RECOVERY FULL mode
    EXEC [tSQLt].[AssertEquals] 1, 
        (SELECT CASE WHEN recovery_model = 1 THEN 1 ELSE 0 END FROM sys.databases WHERE name = DB_NAME()),
        'Database should be in FULL recovery mode';
    
    -- Verify READ_COMMITTED_SNAPSHOT enabled
    EXEC [tSQLt].[AssertDatabaseOptionEnabled] 'read_committed_snapshot';
    
    -- Verify ALLOW_SNAPSHOT_ISOLATION enabled
    EXEC [tSQLt].[AssertDatabaseOptionEnabled] 'allow_snapshot_isolation';
    
    -- Verify PAGE_VERIFY CHECKSUM enabled
    EXEC [tSQLt].[AssertDatabaseOptionEnabled] 'page_verify_option';
    
    -- Verify Query Store enabled
    EXEC [tSQLt].[AssertDatabaseOptionEnabled] 'is_query_store_on';
    
    -- Verify Change Data Capture enabled
    EXEC [tSQLt].[AssertDatabaseOptionEnabled] 'is_cdc_enabled';
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_logical_schemas_should_exist_for_data_organization]
AS
BEGIN
    -- Given the CareSync database exists
    -- When I create the database schemas
    -- Then the following schemas should exist for logical organization
    
    EXEC [tSQLt].[AssertObjectExists] 'Identity', 'SCHEMA', 'Identity schema should exist for user management';
    EXEC [tSQLt].[AssertObjectExists] 'Care', 'SCHEMA', 'Care schema should exist for patient care';
    EXEC [tSQLt].[AssertObjectExists] 'Clinical', 'SCHEMA', 'Clinical schema should exist for clinical data';
    EXEC [tSQLt].[AssertObjectExists] 'Communication', 'SCHEMA', 'Communication schema should exist for messaging';
    EXEC [tSQLt].[AssertObjectExists] 'Analytics', 'SCHEMA', 'Analytics schema should exist for reporting';
    EXEC [tSQLt].[AssertObjectExists] 'Audit', 'SCHEMA', 'Audit schema should exist for compliance';
    EXEC [tSQLt].[AssertObjectExists] 'Reference', 'SCHEMA', 'Reference schema should exist for lookups';
    EXEC [tSQLt].[AssertObjectExists] 'Security', 'SCHEMA', 'Security schema should exist for security functions';
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_application_security_roles_should_exist]
AS
BEGIN
    -- Given the CareSync database exists with schemas
    -- When I create the application security roles
    -- Then the following roles should exist
    
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_Application', 'ROLE', 'CareSync_Application role should exist';
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_ReadOnly', 'ROLE', 'CareSync_ReadOnly role should exist';
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_Analytics', 'ROLE', 'CareSync_Analytics role should exist';
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_Admin', 'ROLE', 'CareSync_Admin role should exist';
    
    -- And the following users should be created without login
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_API', 'USER', 'CareSync_API user should exist';
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_BackgroundJobs', 'USER', 'CareSync_BackgroundJobs user should exist';
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_Analytics_Service', 'USER', 'CareSync_Analytics_Service user should exist';
    EXEC [tSQLt].[AssertObjectExists] 'CareSync_Audit_Service', 'USER', 'CareSync_Audit_Service user should exist';
END
GO

-- ==============================================
-- Table Structure Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_users_table_should_support_multitenant_authentication]
AS
BEGIN
    -- Given the database schemas exist
    -- When I create the Identity.Users table
    -- Then the table should have multi-tenant authentication structure
    
    EXEC [tSQLt].[AssertObjectExists] 'Identity.Users', 'TABLE', 'Identity.Users table should exist';
    
    -- Verify core authentication columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'Id', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'TenantId', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'Email', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'NormalizedEmail', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'FirstName', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'LastName', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'PhoneNumber', 'nvarchar', 1;
    
    -- Verify security and audit columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'EmailVerified', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'TwoFactorEnabled', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'IsActive', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'CreatedAt', 'datetimeoffset', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'IsDeleted', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Identity.Users', 'RowVersion', 'timestamp', 0;
    
    -- Verify unique index on TenantId + NormalizedEmail exists
    EXEC [tSQLt].[AssertObjectExists] 'Identity.Users.IX_Users_Email', 'INDEX', 'Unique index on TenantId + NormalizedEmail should exist';
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_patients_table_should_support_comprehensive_patient_data]
AS
BEGIN
    -- Given the Identity.Users table exists
    -- When I create the Care.Patients table
    -- Then the table should support comprehensive patient data
    
    EXEC [tSQLt].[AssertObjectExists] 'Care.Patients', 'TABLE', 'Care.Patients table should exist';
    
    -- Verify patient identification columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'Id', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'TenantId', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'FirstName', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'LastName', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'DateOfBirth', 'date', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'Gender', 'nvarchar', 0;
    
    -- Verify medical information columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'PrimaryDiagnosis', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'SecondaryDiagnoses', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'Allergies', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'InsuranceInformation', 'nvarchar', 1;
    
    -- Verify care management columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'PrimaryUserId', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'PrivacySettings', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'TrackingConfigurations', 'nvarchar', 0;
    
    -- Verify audit columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'CreatedAt', 'datetimeoffset', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'IsDeleted', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.Patients', 'RowVersion', 'timestamp', 0;
    
    -- Verify foreign key relationship exists
    DECLARE @FKCount INT;
    SELECT @FKCount = COUNT(*)
    FROM sys.foreign_keys fk
    INNER JOIN sys.tables pt ON fk.parent_object_id = pt.object_id
    INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id
    INNER JOIN sys.schemas ps ON pt.schema_id = ps.schema_id
    INNER JOIN sys.schemas rs ON rt.schema_id = rs.schema_id
    WHERE ps.name = 'Care' AND pt.name = 'Patients'
    AND rs.name = 'Identity' AND rt.name = 'Users';
    
    EXEC [tSQLt].[AssertEquals] 1, @FKCount, 'Foreign key relationship to Identity.Users should exist';
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_careteams_table_should_support_multiuser_collaboration]
AS
BEGIN
    -- Given the Care.Patients table exists
    -- When I create the Care.CareTeams table
    -- Then the table should support the PRIMARY differentiator of concurrent multi-user access
    
    EXEC [tSQLt].[AssertObjectExists] 'Care.CareTeams', 'TABLE', 'Care.CareTeams table should exist for multi-user collaboration';
    
    -- Verify core collaboration columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'Id', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'TenantId', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'PatientId', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'Name', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'Description', 'nvarchar', 1;
    
    -- Verify multi-user management columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'MaxMembers', 'int', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'RequireApproval', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'CommunicationPreferences', 'nvarchar', 0;
    
    -- Verify audit columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'CreatedAt', 'datetimeoffset', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'IsDeleted', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Care.CareTeams', 'RowVersion', 'timestamp', 0;
    
    -- Verify default MaxMembers allows up to 50 concurrent users
    DECLARE @DefaultMaxMembers INT;
    SELECT @DefaultMaxMembers = CAST(column_default AS INT)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'Care' AND TABLE_NAME = 'CareTeams' AND COLUMN_NAME = 'MaxMembers'
    AND column_default LIKE '%50%';
    
    EXEC [tSQLt].[AssertEquals] 50, @DefaultMaxMembers, 'MaxMembers should default to 50 for concurrent user support';
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_trackingentries_table_should_have_monthly_partitioning]
AS
BEGIN
    -- Given the Care.Patients table exists
    -- When I create the Clinical.TrackingEntries table
    -- Then the table should be partitioned by month for performance
    
    EXEC [tSQLt].[AssertObjectExists] 'Clinical.TrackingEntries', 'TABLE', 'Clinical.TrackingEntries table should exist';
    
    -- Verify core tracking columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'Id', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'TenantId', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'PatientId', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'EnteredBy', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'TrackingType', 'int', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'OccurredAt', 'datetimeoffset', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'TimeZone', 'nvarchar', 0;
    
    -- Verify severity tracking columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'SeverityNumeric', 'int', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'SeverityDescriptive', 'int', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'SeverityVisual', 'int', 1;
    
    -- Verify data capture columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'Location', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'Notes', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'VoiceTranscription', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'CustomFields', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'EnvironmentalData', 'nvarchar', 1;
    
    -- Verify edit tracking columns for concurrent user support
    EXEC [tSQLt].[AssertTableColumnExists] 'Clinical.TrackingEntries', 'IsEdited', 'bit', 0;
    
    -- Verify partition function exists for monthly partitioning
    EXEC [tSQLt].[AssertObjectExists] 'PF_TrackingEntries_OccurredAt', 'FUNCTION', 'Partition function for monthly partitioning should exist';
    
    -- Verify partition scheme exists
    DECLARE @PartitionSchemeCount INT;
    SELECT @PartitionSchemeCount = COUNT(*)
    FROM sys.partition_schemes
    WHERE name = 'PS_TrackingEntries_OccurredAt';
    
    EXEC [tSQLt].[AssertEquals] 1, @PartitionSchemeCount, 'Partition scheme for TrackingEntries should exist';
    
    -- Verify clustered index uses partition scheme
    EXEC [tSQLt].[AssertObjectExists] 'Clinical.TrackingEntries.IX_TrackingEntries_Partitioned', 'INDEX', 'Partitioned clustered index should exist';
END
GO

-- ==============================================
-- Audit and Security Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_comprehensive_audit_logging_tables_should_exist]
AS
BEGIN
    -- Given the database schemas exist
    -- When I create the audit logging tables
    -- Then comprehensive audit logging should be supported
    
    -- Verify AuditLog table exists and captures all data changes
    EXEC [tSQLt].[AssertObjectExists] 'Audit.AuditLog', 'TABLE', 'Audit.AuditLog table should exist';
    
    -- Verify audit log structure
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'Id', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'TenantId', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'EntityType', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'EntityId', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'UserId', 'uniqueidentifier', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'UserName', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'Action', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'TableName', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'OldValues', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'NewValues', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'IPAddress', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'SessionId', 'nvarchar', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.AuditLog', 'Timestamp', 'datetimeoffset', 0;
    
    -- Verify SecurityEvents table exists for HIPAA compliance
    EXEC [tSQLt].[AssertObjectExists] 'Audit.SecurityEvents', 'TABLE', 'Audit.SecurityEvents table should exist for HIPAA compliance';
    
    -- Verify DataAccessLog table exists for PHI access tracking
    EXEC [tSQLt].[AssertObjectExists] 'Audit.DataAccessLog', 'TABLE', 'Audit.DataAccessLog table should exist for PHI access tracking';
    
    -- Verify audit tables are partitioned by month
    DECLARE @AuditPartitionCount INT;
    SELECT @AuditPartitionCount = COUNT(*)
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'Audit' AND t.name = 'AuditLog'
    AND i.name = 'IX_AuditLog_Partitioned';
    
    EXEC [tSQLt].[AssertEquals] 1, @AuditPartitionCount, 'AuditLog table should have partitioned clustered index';
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_row_level_security_should_enforce_tenant_isolation]
AS
BEGIN
    -- Given all tables are created with TenantId columns
    -- When I implement row-level security
    -- Then multi-tenant isolation should be enforced
    
    -- Verify security function exists
    EXEC [tSQLt].[AssertObjectExists] 'Security.fn_TenantAccessPredicate', 'FUNCTION', 'Tenant access predicate function should exist';
    
    -- Verify security policy exists
    DECLARE @SecurityPolicyCount INT;
    SELECT @SecurityPolicyCount = COUNT(*)
    FROM sys.security_policies
    WHERE name = 'TenantSecurityPolicy';
    
    EXEC [tSQLt].[AssertEquals] 1, @SecurityPolicyCount, 'TenantSecurityPolicy should exist';
    
    -- Verify security policy is enabled
    DECLARE @PolicyEnabled BIT;
    SELECT @PolicyEnabled = is_enabled
    FROM sys.security_policies
    WHERE name = 'TenantSecurityPolicy';
    
    EXEC [tSQLt].[AssertEquals] 1, @PolicyEnabled, 'TenantSecurityPolicy should be enabled';
    
    -- Verify security predicates are applied to key tables
    DECLARE @PredicateCount INT;
    SELECT @PredicateCount = COUNT(*)
    FROM sys.security_predicates sp
    INNER JOIN sys.objects o ON sp.target_object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name + '.' + o.name IN (
        'Identity.Users',
        'Care.Patients', 
        'Care.CareTeams',
        'Clinical.TrackingEntries',
        'Audit.AuditLog'
    );
    
    -- Should have at least 5 predicates for core tables
    IF @PredicateCount < 5
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = 'Expected at least 5 security predicates but found ' + CAST(@PredicateCount AS NVARCHAR);
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_audit_triggers_should_capture_data_changes]
AS
BEGIN
    -- Given the audit tables exist and row-level security is implemented
    -- When I create audit triggers
    -- Then automatic change tracking should be enabled
    
    -- Verify audit trigger exists for Users table
    DECLARE @TriggerCount INT;
    SELECT @TriggerCount = COUNT(*)
    FROM sys.triggers t
    INNER JOIN sys.tables tb ON t.parent_id = tb.object_id
    INNER JOIN sys.schemas s ON tb.schema_id = s.schema_id
    WHERE s.name = 'Identity' AND tb.name = 'Users'
    AND t.name = 'TR_Users_Audit';
    
    EXEC [tSQLt].[AssertEquals] 1, @TriggerCount, 'Audit trigger should exist for Identity.Users table';
    
    -- Verify audit helper function exists
    EXEC [tSQLt].[AssertObjectExists] 'Audit.fn_GetAuditData', 'FUNCTION', 'Audit helper function should exist';
    
    -- Note: Testing actual trigger functionality would require DML operations
    -- and is better suited for integration tests
END
GO

-- ==============================================
-- Data Retention and Compliance Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_data_retention_policies_should_support_hipaa_compliance]
AS
BEGIN
    -- Given the audit tables exist
    -- When I create data retention policies
    -- Then HIPAA-compliant data retention should be supported
    
    -- Verify DataRetentionPolicies table exists
    EXEC [tSQLt].[AssertObjectExists] 'Audit.DataRetentionPolicies', 'TABLE', 'DataRetentionPolicies table should exist';
    
    -- Verify retention policy structure
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.DataRetentionPolicies', 'TableName', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.DataRetentionPolicies', 'RetentionPeriodMonths', 'int', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.DataRetentionPolicies', 'ArchiveBeforeDelete', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Audit.DataRetentionPolicies', 'IsEnabled', 'bit', 0;
    
    -- Verify retention processing procedure exists
    EXEC [tSQLt].[AssertObjectExists] 'Audit.sp_ProcessDataRetention', 'PROCEDURE', 'Data retention procedure should exist';
    
    -- Verify default retention policies are configured
    DECLARE @PolicyCount INT;
    SELECT @PolicyCount = COUNT(*)
    FROM [Audit].[DataRetentionPolicies]
    WHERE TableName IN (
        'Audit.AuditLog',
        'Audit.SecurityEvents',
        'Audit.DataAccessLog',
        'Clinical.TrackingEntries',
        'Communication.Messages'
    );
    
    -- Should have policies for at least 5 key tables
    IF @PolicyCount < 5
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = 'Expected at least 5 retention policies but found ' + CAST(@PolicyCount AS NVARCHAR);
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

-- ==============================================
-- Communication and Collaboration Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_communication_tables_should_support_realtime_collaboration]
AS
BEGIN
    -- Given the Care.CareTeams table exists
    -- When I create the communication tables
    -- Then real-time care team collaboration should be supported
    
    -- Verify Messages table exists for real-time messaging
    EXEC [tSQLt].[AssertObjectExists] 'Communication.Messages', 'TABLE', 'Communication.Messages table should exist';
    
    -- Verify core messaging columns
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'CareTeamId', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'SenderId', 'uniqueidentifier', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'Content', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'MentionedUsers', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'ReadReceipts', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'DeliveryStatus', 'nvarchar', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'ReplyToMessageId', 'uniqueidentifier', 1;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'IsUrgent', 'bit', 0;
    EXEC [tSQLt].[AssertTableColumnExists] 'Communication.Messages', 'Attachments', 'nvarchar', 0;
    
    -- Verify Attachments table exists for file sharing
    EXEC [tSQLt].[AssertObjectExists] 'Communication.Attachments', 'TABLE', 'Communication.Attachments table should exist';
    
    -- Verify Notifications table exists for push notifications
    EXEC [tSQLt].[AssertObjectExists] 'Communication.Notifications', 'TABLE', 'Communication.Notifications table should exist';
    
    -- Verify message partitioning for performance
    DECLARE @MessagePartitionCount INT;
    SELECT @MessagePartitionCount = COUNT(*)
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'Communication' AND t.name = 'Messages'
    AND i.name = 'IX_Messages_Partitioned';
    
    EXEC [tSQLt].[AssertEquals] 1, @MessagePartitionCount, 'Messages table should have partitioned clustered index';
END
GO

-- ==============================================
-- Performance and Index Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [DatabaseSchemaTests].[test_performance_indexes_should_support_concurrent_access]
AS
BEGIN
    -- Given all tables are created
    -- When I create performance indexes
    -- Then concurrent multi-user access should be optimized
    
    -- Verify Users table indexes
    EXEC [tSQLt].[AssertObjectExists] 'Identity.Users.IX_Users_Email', 'INDEX', 'Users email index should exist';
    EXEC [tSQLt].[AssertObjectExists] 'Identity.Users.IX_Users_TenantId', 'INDEX', 'Users tenant index should exist';
    
    -- Verify Patients table indexes
    EXEC [tSQLt].[AssertObjectExists] 'Care.Patients.IX_Patients_TenantId', 'INDEX', 'Patients tenant index should exist';
    EXEC [tSQLt].[AssertObjectExists] 'Care.Patients.IX_Patients_PrimaryUserId', 'INDEX', 'Patients primary user index should exist';
    
    -- Verify CareTeams table indexes
    EXEC [tSQLt].[AssertObjectExists] 'Care.CareTeams.IX_CareTeams_PatientId', 'INDEX', 'CareTeams patient index should exist';
    
    -- Verify TrackingEntries table indexes for performance
    EXEC [tSQLt].[AssertObjectExists] 'Clinical.TrackingEntries.IX_TrackingEntries_PatientId', 'INDEX', 'TrackingEntries patient index should exist';
    EXEC [tSQLt].[AssertObjectExists] 'Clinical.TrackingEntries.IX_TrackingEntries_EnteredBy', 'INDEX', 'TrackingEntries entered by index should exist';
    
    -- Verify Messages table indexes for real-time performance
    EXEC [tSQLt].[AssertObjectExists] 'Communication.Messages.IX_Messages_CareTeamId', 'INDEX', 'Messages care team index should exist';
    EXEC [tSQLt].[AssertObjectExists] 'Communication.Messages.IX_Messages_SenderId', 'INDEX', 'Messages sender index should exist';
    
    -- Count total indexes to ensure comprehensive coverage
    DECLARE @IndexCount INT;
    SELECT @IndexCount = COUNT(*)
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name IN ('Identity', 'Care', 'Clinical', 'Communication')
    AND i.type > 0; -- Exclude heaps
    
    -- Should have substantial number of indexes for performance
    IF @IndexCount < 20
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = 'Expected at least 20 performance indexes but found ' + CAST(@IndexCount AS NVARCHAR);
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

PRINT 'CareSync Database Schema tSQLt Tests created successfully';
PRINT 'Run tests with: EXEC [tSQLt].[Run] @TestClass = ''DatabaseSchemaTests''';
GO