-- CareSync Database Schema Test Runner
-- Executes all tSQLt tests for BDD-driven database schema validation

USE CareSync;
GO

PRINT '=============================================================';
PRINT 'CareSync Database Schema Test Suite';
PRINT 'BDD-driven tests for HIPAA-compliant multi-tenant database';
PRINT '=============================================================';
PRINT '';

-- Ensure tSQLt framework is set up
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'tSQLt')
BEGIN
    PRINT 'ERROR: tSQLt framework not found. Please run tSQLt-setup.sql first.';
    RETURN;
END

-- Clear previous test results
DELETE FROM [tSQLt].[TestResults];

PRINT 'Starting database schema validation tests...';
PRINT '';

-- Run Database Schema Tests
PRINT 'Running DatabaseSchemaTests...';
BEGIN TRY
    EXEC [tSQLt].[Run] @TestClass = 'DatabaseSchemaTests';
END TRY
BEGIN CATCH
    PRINT 'ERROR in DatabaseSchemaTests: ' + ERROR_MESSAGE();
END CATCH

PRINT '';

-- Run Security Function Tests  
PRINT 'Running SecurityFunctionTests...';
BEGIN TRY
    EXEC [tSQLt].[Run] @TestClass = 'SecurityFunctionTests';
END TRY
BEGIN CATCH
    PRINT 'ERROR in SecurityFunctionTests: ' + ERROR_MESSAGE();
END CATCH

PRINT '';

-- Run all tests together for overall summary
PRINT 'Running complete test suite...';
BEGIN TRY
    EXEC [tSQLt].[Run];
END TRY
BEGIN CATCH
    PRINT 'ERROR in complete test suite: ' + ERROR_MESSAGE();
END CATCH

PRINT '';
PRINT '=============================================================';
PRINT 'Test Results Summary';
PRINT '=============================================================';

-- Display detailed test results
SELECT 
    [Class],
    [TestName],
    [Result],
    [Message],
    [ExecutedAt]
FROM [tSQLt].[TestResults]
ORDER BY [Class], [TestName];

-- Display summary statistics
SELECT 
    'Total Tests' AS Metric,
    COUNT(*) AS Count
FROM [tSQLt].[TestResults]

UNION ALL

SELECT 
    'Passed Tests' AS Metric,
    SUM(CASE WHEN [Result] = 'Success' THEN 1 ELSE 0 END) AS Count
FROM [tSQLt].[TestResults]

UNION ALL

SELECT 
    'Failed Tests' AS Metric,
    SUM(CASE WHEN [Result] = 'Failure' THEN 1 ELSE 0 END) AS Count
FROM [tSQLt].[TestResults]

UNION ALL

SELECT 
    'Success Rate %' AS Metric,
    CASE 
        WHEN COUNT(*) > 0 THEN (SUM(CASE WHEN [Result] = 'Success' THEN 1 ELSE 0 END) * 100) / COUNT(*)
        ELSE 0 
    END AS Count
FROM [tSQLt].[TestResults];

-- Check for any failures
DECLARE @FailureCount INT;
SELECT @FailureCount = COUNT(*)
FROM [tSQLt].[TestResults]
WHERE [Result] = 'Failure';

IF @FailureCount > 0
BEGIN
    PRINT '';
    PRINT 'WARNING: ' + CAST(@FailureCount AS NVARCHAR) + ' test(s) failed!';
    PRINT 'Schema implementation does not meet BDD requirements.';
    PRINT 'Review failed tests above and fix issues before proceeding.';
    PRINT '';
    
    -- Show failed tests
    PRINT 'Failed Tests:';
    PRINT '=============';
    SELECT 
        [Class] + '.' + [TestName] AS FailedTest,
        [Message] AS FailureReason
    FROM [tSQLt].[TestResults]
    WHERE [Result] = 'Failure'
    ORDER BY [Class], [TestName];
END
ELSE
BEGIN
    PRINT '';
    PRINT 'SUCCESS: All tests passed!';
    PRINT 'Database schema meets all BDD requirements.';
    PRINT 'Ready to proceed with implementation.';
END

PRINT '';
PRINT 'Test execution completed at: ' + CONVERT(NVARCHAR, SYSDATETIME(), 120);
PRINT '=============================================================';
GO