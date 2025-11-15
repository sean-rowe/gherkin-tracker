-- CareSync Security Function tSQLt Tests
-- BDD-driven tests for row-level security and audit functions

USE CareSync;
GO

-- Create test class schema for security tests
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'SecurityFunctionTests')
BEGIN
    EXEC('CREATE SCHEMA [SecurityFunctionTests]');
END
GO

-- ==============================================
-- Row-Level Security Function Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_tenant_access_predicate_should_enforce_isolation]
AS
BEGIN
    -- Given all tables are created with TenantId columns
    -- When I implement row-level security  
    -- Then tenant isolation should be enforced through the security function
    
    -- Verify the security function exists
    EXEC [tSQLt].[AssertObjectExists] 'Security.fn_TenantAccessPredicate', 'FUNCTION', 'Tenant access predicate function should exist';
    
    -- Verify function parameters
    DECLARE @FunctionDefinition NVARCHAR(MAX);
    SELECT @FunctionDefinition = OBJECT_DEFINITION(OBJECT_ID('Security.fn_TenantAccessPredicate'));
    
    -- Function should check SESSION_CONTEXT for TenantId
    IF CHARINDEX('SESSION_CONTEXT', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Security function should check SESSION_CONTEXT for tenant isolation', 1;
    END
    
    -- Function should allow CareSync_Admin role
    IF CHARINDEX('CareSync_Admin', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Security function should allow CareSync_Admin role access', 1;
    END
    
    -- Function should allow db_owner role
    IF CHARINDEX('db_owner', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Security function should allow db_owner role access', 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_security_policy_should_apply_to_all_tenant_tables]
AS
BEGIN
    -- Given the security function exists
    -- When I create the security policy
    -- Then filter predicates should be applied to all tenant-enabled tables
    
    -- Verify security policy exists and is enabled
    DECLARE @PolicyCount INT;
    SELECT @PolicyCount = COUNT(*)
    FROM sys.security_policies
    WHERE name = 'TenantSecurityPolicy' AND is_enabled = 1;
    
    EXEC [tSQLt].[AssertEquals] 1, @PolicyCount, 'TenantSecurityPolicy should exist and be enabled';
    
    -- Verify predicates are applied to core tables
    DECLARE @PredicateCount INT;
    SELECT @PredicateCount = COUNT(*)
    FROM sys.security_predicates sp
    INNER JOIN sys.objects o ON sp.target_object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE sp.predicate_type = 1 -- FILTER predicate
    AND s.name + '.' + o.name IN (
        'Identity.Users',
        'Care.Patients',
        'Care.CareTeams',
        'Care.CareTeamMembers',
        'Clinical.TrackingEntries',
        'Clinical.Symptoms',
        'Clinical.Medications',
        'Clinical.Behaviors',
        'Communication.Messages',
        'Communication.Notifications',
        'Audit.AuditLog',
        'Audit.SecurityEvents',
        'Audit.DataAccessLog'
    );
    
    -- Should have predicates for at least 10 core tables
    IF @PredicateCount < 10
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = 'Expected at least 10 security predicates but found ' + CAST(@PredicateCount AS NVARCHAR);
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_session_context_should_control_data_access]
AS
BEGIN
    -- Given row-level security is implemented
    -- When SESSION_CONTEXT is set for a tenant
    -- Then only that tenant's data should be accessible
    
    -- This test verifies the security function logic conceptually
    -- Actual runtime testing would require data and session setup
    
    -- Verify the security function uses SESSION_CONTEXT('TenantId')
    DECLARE @FunctionDefinition NVARCHAR(MAX);
    SELECT @FunctionDefinition = OBJECT_DEFINITION(OBJECT_ID('Security.fn_TenantAccessPredicate'));
    
    -- Should check for TenantId in session context
    IF CHARINDEX('SESSION_CONTEXT(N''TenantId'')', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Security function should check SESSION_CONTEXT(''TenantId'')', 1;
    END
    
    -- Should return access result
    IF CHARINDEX('AccessResult', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Security function should return AccessResult', 1;
    END
    
    -- Function should be schema-bound for performance
    IF CHARINDEX('WITH SCHEMABINDING', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Security function should be schema-bound for performance', 1;
    END
END
GO

-- ==============================================
-- Audit Function Tests  
-- ==============================================

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_audit_data_function_should_capture_session_info]
AS
BEGIN
    -- Given the audit tables exist
    -- When I create audit triggers
    -- Then the audit helper function should capture session information
    
    -- Verify audit helper function exists
    EXEC [tSQLt].[AssertObjectExists] 'Audit.fn_GetAuditData', 'FUNCTION', 'Audit helper function should exist';
    
    -- Verify function captures session context data
    DECLARE @FunctionDefinition NVARCHAR(MAX);
    SELECT @FunctionDefinition = OBJECT_DEFINITION(OBJECT_ID('Audit.fn_GetAuditData'));
    
    -- Should capture UserId from session
    IF CHARINDEX('SESSION_CONTEXT(N''UserId'')', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture UserId from session context', 1;
    END
    
    -- Should capture UserName from session
    IF CHARINDEX('SESSION_CONTEXT(N''UserName'')', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture UserName from session context', 1;
    END
    
    -- Should capture IPAddress from session
    IF CHARINDEX('SESSION_CONTEXT(N''IPAddress'')', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture IPAddress from session context', 1;
    END
    
    -- Should capture SessionId from session
    IF CHARINDEX('SESSION_CONTEXT(N''SessionId'')', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture SessionId from session context', 1;
    END
    
    -- Should capture CorrelationId from session
    IF CHARINDEX('SESSION_CONTEXT(N''CorrelationId'')', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture CorrelationId from session context', 1;
    END
    
    -- Should capture ApplicationName
    IF CHARINDEX('APP_NAME()', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture ApplicationName', 1;
    END
    
    -- Should capture HostName
    IF CHARINDEX('HOST_NAME()', @FunctionDefinition) = 0
    BEGIN
        THROW 50000, 'Audit function should capture HostName', 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_users_audit_trigger_should_capture_all_changes]
AS
BEGIN
    -- Given the audit helper function exists
    -- When I create audit triggers
    -- Then the Users table trigger should capture INSERT, UPDATE, and DELETE operations
    
    -- Verify audit trigger exists for Users table
    DECLARE @TriggerCount INT;
    SELECT @TriggerCount = COUNT(*)
    FROM sys.triggers t
    INNER JOIN sys.tables tb ON t.parent_id = tb.object_id
    INNER JOIN sys.schemas s ON tb.schema_id = s.schema_id
    WHERE s.name = 'Identity' AND tb.name = 'Users'
    AND t.name = 'TR_Users_Audit';
    
    EXEC [tSQLt].[AssertEquals] 1, @TriggerCount, 'Users audit trigger should exist';
    
    -- Verify trigger is configured for AFTER INSERT, UPDATE, DELETE
    DECLARE @TriggerDefinition NVARCHAR(MAX);
    SELECT @TriggerDefinition = OBJECT_DEFINITION(t.object_id)
    FROM sys.triggers t
    INNER JOIN sys.tables tb ON t.parent_id = tb.object_id
    INNER JOIN sys.schemas s ON tb.schema_id = s.schema_id
    WHERE s.name = 'Identity' AND tb.name = 'Users'
    AND t.name = 'TR_Users_Audit';
    
    -- Should handle INSERT operations
    IF CHARINDEX('INSERT', @TriggerDefinition) = 0
    BEGIN
        THROW 50000, 'Users audit trigger should handle INSERT operations', 1;
    END
    
    -- Should handle UPDATE operations  
    IF CHARINDEX('UPDATE', @TriggerDefinition) = 0
    BEGIN
        THROW 50000, 'Users audit trigger should handle UPDATE operations', 1;
    END
    
    -- Should handle DELETE operations
    IF CHARINDEX('DELETE', @TriggerDefinition) = 0
    BEGIN
        THROW 50000, 'Users audit trigger should handle DELETE operations', 1;
    END
    
    -- Should capture old and new values as JSON
    IF CHARINDEX('FOR JSON AUTO', @TriggerDefinition) = 0
    BEGIN
        THROW 50000, 'Users audit trigger should capture values as JSON', 1;
    END
    
    -- Should insert into AuditLog table
    IF CHARINDEX('INSERT INTO [Audit].[AuditLog]', @TriggerDefinition) = 0
    BEGIN
        THROW 50000, 'Users audit trigger should insert into AuditLog table', 1;
    END
    
    -- Should use audit helper function
    IF CHARINDEX('[Audit].[fn_GetAuditData]', @TriggerDefinition) = 0
    BEGIN
        THROW 50000, 'Users audit trigger should use audit helper function', 1;
    END
END
GO

-- ==============================================
-- Data Retention Function Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_data_retention_procedure_should_support_dry_run]
AS
BEGIN
    -- Given the audit tables exist  
    -- When I create data retention policies
    -- Then the retention procedure should support dry-run mode for testing
    
    -- Verify retention procedure exists
    EXEC [tSQLt].[AssertObjectExists] 'Audit.sp_ProcessDataRetention', 'PROCEDURE', 'Data retention procedure should exist';
    
    -- Verify procedure supports dry-run parameter
    DECLARE @ProcedureDefinition NVARCHAR(MAX);
    SELECT @ProcedureDefinition = OBJECT_DEFINITION(OBJECT_ID('Audit.sp_ProcessDataRetention'));
    
    -- Should have @DryRun parameter
    IF CHARINDEX('@DryRun BIT = 1', @ProcedureDefinition) = 0
    BEGIN
        THROW 50000, 'Data retention procedure should have @DryRun parameter defaulting to 1', 1;
    END
    
    -- Should check DryRun before deleting data
    IF CHARINDEX('IF @DryRun = 0', @ProcedureDefinition) = 0
    BEGIN
        THROW 50000, 'Data retention procedure should check @DryRun before deleting', 1;
    END
    
    -- Should archive data before deletion
    IF CHARINDEX('INSERT INTO', @ProcedureDefinition) = 0 OR CHARINDEX('_Archive', @ProcedureDefinition) = 0
    BEGIN
        THROW 50000, 'Data retention procedure should archive data before deletion', 1;
    END
    
    -- Should use retention policies table
    IF CHARINDEX('[Audit].[DataRetentionPolicies]', @ProcedureDefinition) = 0
    BEGIN
        THROW 50000, 'Data retention procedure should use DataRetentionPolicies table', 1;
    END
    
    -- Should update last processed date
    IF CHARINDEX('LastProcessedDate', @ProcedureDefinition) = 0
    BEGIN
        THROW 50000, 'Data retention procedure should update LastProcessedDate', 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_retention_policies_should_have_hipaa_compliant_periods]
AS
BEGIN
    -- Given the DataRetentionPolicies table exists
    -- When default retention policies are inserted
    -- Then retention periods should be HIPAA-compliant
    
    -- Verify audit logs have 7-year retention (84 months)
    DECLARE @AuditRetention INT;
    SELECT @AuditRetention = RetentionPeriodMonths
    FROM [Audit].[DataRetentionPolicies]
    WHERE TableName = 'Audit.AuditLog';
    
    EXEC [tSQLt].[AssertEquals] 84, @AuditRetention, 'Audit logs should have 7-year (84 month) retention';
    
    -- Verify security events have 7-year retention
    DECLARE @SecurityRetention INT;
    SELECT @SecurityRetention = RetentionPeriodMonths
    FROM [Audit].[DataRetentionPolicies]
    WHERE TableName = 'Audit.SecurityEvents';
    
    EXEC [tSQLt].[AssertEquals] 84, @SecurityRetention, 'Security events should have 7-year (84 month) retention';
    
    -- Verify data access logs have 7-year retention
    DECLARE @AccessRetention INT;
    SELECT @AccessRetention = RetentionPeriodMonths
    FROM [Audit].[DataRetentionPolicies]
    WHERE TableName = 'Audit.DataAccessLog';
    
    EXEC [tSQLt].[AssertEquals] 84, @AccessRetention, 'Data access logs should have 7-year (84 month) retention';
    
    -- Verify clinical data has appropriate retention (2 years)
    DECLARE @ClinicalRetention INT;
    SELECT @ClinicalRetention = RetentionPeriodMonths
    FROM [Audit].[DataRetentionPolicies]
    WHERE TableName = 'Clinical.TrackingEntries';
    
    EXEC [tSQLt].[AssertEquals] 24, @ClinicalRetention, 'Clinical tracking entries should have 2-year (24 month) retention';
    
    -- Verify archive-before-delete is enabled for compliance
    DECLARE @ArchiveEnabledCount INT;
    SELECT @ArchiveEnabledCount = COUNT(*)
    FROM [Audit].[DataRetentionPolicies]
    WHERE ArchiveBeforeDelete = 1
    AND TableName IN ('Audit.AuditLog', 'Audit.SecurityEvents', 'Clinical.TrackingEntries');
    
    IF @ArchiveEnabledCount < 3
    BEGIN
        THROW 50000, 'Archive-before-delete should be enabled for compliance tables', 1;
    END
END
GO

-- ==============================================
-- Partition Function Tests
-- ==============================================

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_partition_functions_should_support_three_years]
AS
BEGIN
    -- Given the tables need monthly partitioning
    -- When I create partition functions
    -- Then they should cover at least 3 years of monthly partitions
    
    -- Verify TrackingEntries partition function exists
    DECLARE @PartitionFunctionCount INT;
    SELECT @PartitionFunctionCount = COUNT(*)
    FROM sys.partition_functions
    WHERE name = 'PF_TrackingEntries_OccurredAt';
    
    EXEC [tSQLt].[AssertEquals] 1, @PartitionFunctionCount, 'TrackingEntries partition function should exist';
    
    -- Verify partition function has sufficient boundary points for 3 years
    DECLARE @BoundaryCount INT;
    SELECT @BoundaryCount = COUNT(*)
    FROM sys.partition_range_values rv
    INNER JOIN sys.partition_functions pf ON rv.function_id = pf.function_id
    WHERE pf.name = 'PF_TrackingEntries_OccurredAt';
    
    -- Should have at least 36 boundary points for 3 years of monthly partitions
    IF @BoundaryCount < 36
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = 'Partition function should have at least 36 boundary points but found ' + CAST(@BoundaryCount AS NVARCHAR);
        THROW 50000, @ErrorMsg, 1;
    END
    
    -- Verify audit log partition function exists
    DECLARE @AuditPartitionCount INT;
    SELECT @AuditPartitionCount = COUNT(*)
    FROM sys.partition_functions
    WHERE name = 'PF_AuditLog_Timestamp';
    
    EXEC [tSQLt].[AssertEquals] 1, @AuditPartitionCount, 'AuditLog partition function should exist';
    
    -- Verify messages partition function exists
    DECLARE @MessagesPartitionCount INT;
    SELECT @MessagesPartitionCount = COUNT(*)
    FROM sys.partition_functions
    WHERE name = 'PF_Messages_CreatedAt';
    
    EXEC [tSQLt].[AssertEquals] 1, @MessagesPartitionCount, 'Messages partition function should exist';
END
GO

CREATE OR ALTER PROCEDURE [SecurityFunctionTests].[test_partition_schemes_should_use_primary_filegroup]
AS
BEGIN
    -- Given partition functions exist
    -- When I create partition schemes
    -- Then they should use PRIMARY filegroup for simplicity
    
    -- Verify TrackingEntries partition scheme exists
    DECLARE @PartitionSchemeCount INT;
    SELECT @PartitionSchemeCount = COUNT(*)
    FROM sys.partition_schemes
    WHERE name = 'PS_TrackingEntries_OccurredAt';
    
    EXEC [tSQLt].[AssertEquals] 1, @PartitionSchemeCount, 'TrackingEntries partition scheme should exist';
    
    -- Verify audit log partition scheme exists
    DECLARE @AuditSchemeCount INT;
    SELECT @AuditSchemeCount = COUNT(*)
    FROM sys.partition_schemes
    WHERE name = 'PS_AuditLog_Timestamp';
    
    EXEC [tSQLt].[AssertEquals] 1, @AuditSchemeCount, 'AuditLog partition scheme should exist';
    
    -- Verify partition schemes use filegroups appropriately
    DECLARE @FilegroupAssignmentCount INT;
    SELECT @FilegroupAssignmentCount = COUNT(*)
    FROM sys.destination_data_spaces dds
    INNER JOIN sys.partition_schemes ps ON dds.partition_scheme_id = ps.data_space_id
    INNER JOIN sys.filegroups fg ON dds.data_space_id = fg.data_space_id
    WHERE ps.name IN ('PS_TrackingEntries_OccurredAt', 'PS_AuditLog_Timestamp', 'PS_Messages_CreatedAt')
    AND fg.name = 'PRIMARY';
    
    -- Should have multiple filegroup assignments
    IF @FilegroupAssignmentCount = 0
    BEGIN
        THROW 50000, 'Partition schemes should have proper filegroup assignments', 1;
    END
END
GO

PRINT 'CareSync Security Function tSQLt Tests created successfully';
PRINT 'Run tests with: EXEC [tSQLt].[Run] @TestClass = ''SecurityFunctionTests''';
GO