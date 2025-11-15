-- CareSync Database Implementation Script
-- This script executes all database creation scripts in the correct order
-- Following BDD methodology, these scripts should make all tSQLt tests pass

-- =============================================
-- IMPORTANT: Run this after BDD tests have been written
-- =============================================

PRINT '================================================';
PRINT 'CareSync Database Schema Implementation';
PRINT 'Executing scripts to satisfy BDD requirements';
PRINT '================================================';
PRINT '';

-- Step 1: Create database
PRINT 'Step 1: Creating CareSync database with HIPAA-compliant configuration...';
:r 01-create-database.sql
PRINT 'Database created successfully.';
PRINT '';

-- Step 2: Create Identity and Care schema tables
PRINT 'Step 2: Creating Identity and Care schema tables...';
:r 02-create-tables.sql
PRINT 'Identity and Care tables created successfully.';
PRINT '';

-- Step 3: Create Clinical schema tables
PRINT 'Step 3: Creating Clinical schema tables with partitioning...';
:r 03-create-clinical-tables.sql
PRINT 'Clinical tables created successfully.';
PRINT '';

-- Step 4: Create Communication schema tables
PRINT 'Step 4: Creating Communication schema tables...';
:r 04-create-communication-tables.sql
PRINT 'Communication tables created successfully.';
PRINT '';

-- Step 5: Create Audit and Security configuration
PRINT 'Step 5: Creating Audit schema and security configuration...';
:r 05-create-audit-security.sql
PRINT 'Audit and security configuration created successfully.';
PRINT '';

PRINT '================================================';
PRINT 'Database Schema Implementation Complete';
PRINT '================================================';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run tSQLt tests to verify implementation: EXEC sqlcmd -i ../tests/run-tests.sql';
PRINT '2. All tests should pass (Green phase)';
PRINT '3. Deploy to Kubernetes StatefulSet';
PRINT '';
PRINT 'The database now supports:';
PRINT '- Multi-tenant isolation with row-level security';
PRINT '- HIPAA-compliant audit trails and retention';
PRINT '- Concurrent multi-user access (PRIMARY differentiator)';
PRINT '- Monthly partitioning for performance at scale';
PRINT '- Real-time collaboration features';
PRINT '';

-- Verify key components were created
DECLARE @ComponentCount INT;

-- Check schemas
SELECT @ComponentCount = COUNT(*) 
FROM sys.schemas 
WHERE name IN ('Identity', 'Care', 'Clinical', 'Communication', 'Analytics', 'Audit', 'Reference', 'Security');
PRINT 'Schemas created: ' + CAST(@ComponentCount AS NVARCHAR) + ' (expected: 8)';

-- Check security roles
SELECT @ComponentCount = COUNT(*)
FROM sys.database_principals
WHERE type = 'R' AND name LIKE 'CareSync_%';
PRINT 'Security roles created: ' + CAST(@ComponentCount AS NVARCHAR) + ' (expected: 4)';

-- Check key tables
SELECT @ComponentCount = COUNT(*)
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('Identity', 'Care', 'Clinical', 'Communication', 'Audit')
AND TABLE_TYPE = 'BASE TABLE';
PRINT 'Tables created: ' + CAST(@ComponentCount AS NVARCHAR) + ' (expected: 25+)';

-- Check partition functions
SELECT @ComponentCount = COUNT(*)
FROM sys.partition_functions;
PRINT 'Partition functions created: ' + CAST(@ComponentCount AS NVARCHAR) + ' (expected: 5+)';

-- Check security policy
SELECT @ComponentCount = COUNT(*)
FROM sys.security_policies
WHERE name = 'TenantSecurityPolicy' AND is_enabled = 1;
PRINT 'Security policy enabled: ' + CAST(@ComponentCount AS NVARCHAR) + ' (expected: 1)';

PRINT '';
PRINT 'Implementation complete at: ' + CONVERT(NVARCHAR, SYSDATETIME(), 120);
GO