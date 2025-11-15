-- tSQLt Test Framework Setup for CareSync Database Schema Testing
-- This script sets up the tSQLt framework for BDD-style database testing

USE CareSync;
GO

-- Enable CLR integration (required for tSQLt)
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

-- Download and install tSQLt framework
-- Note: In production, tSQLt should be installed from official release
-- For this BDD setup, we'll create a minimal structure for schema testing

-- Create tSQLt schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'tSQLt')
BEGIN
    EXEC('CREATE SCHEMA [tSQLt]');
END
GO

-- Create test result table
CREATE TABLE [tSQLt].[TestResults] (
    [Id] INT IDENTITY(1,1) PRIMARY KEY,
    [TestCase] NVARCHAR(MAX) NOT NULL,
    [Class] NVARCHAR(MAX) NOT NULL,
    [TestName] NVARCHAR(MAX) NOT NULL,
    [Result] NVARCHAR(10) NOT NULL, -- 'Success' or 'Failure'
    [Message] NVARCHAR(MAX) NULL,
    [ExecutedAt] DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- Create test execution procedure
CREATE OR ALTER PROCEDURE [tSQLt].[Run]
    @TestClass NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TestCount INT = 0;
    DECLARE @SuccessCount INT = 0;
    DECLARE @FailureCount INT = 0;
    
    PRINT 'tSQLt Test Framework - CareSync Database Schema Tests';
    PRINT '======================================================';
    PRINT 'Starting test execution at: ' + CONVERT(NVARCHAR, SYSDATETIME(), 120);
    PRINT '';
    
    -- Execute all test procedures
    DECLARE test_cursor CURSOR FOR
    SELECT 
        SCHEMA_NAME(p.schema_id) AS TestClass,
        p.name AS TestName
    FROM sys.procedures p
    INNER JOIN sys.schemas s ON p.schema_id = s.schema_id
    WHERE s.name LIKE '%Test%'
    AND p.name LIKE 'test_%'
    AND (@TestClass IS NULL OR s.name = @TestClass);
    
    DECLARE @CurrentClass NVARCHAR(MAX), @CurrentTest NVARCHAR(MAX);
    DECLARE @SQL NVARCHAR(MAX);
    
    OPEN test_cursor;
    FETCH NEXT FROM test_cursor INTO @CurrentClass, @CurrentTest;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @TestCount = @TestCount + 1;
            SET @SQL = 'EXEC [' + @CurrentClass + '].[' + @CurrentTest + ']';
            EXEC sp_executesql @SQL;
            
            INSERT INTO [tSQLt].[TestResults] ([TestCase], [Class], [TestName], [Result])
            VALUES (@CurrentClass + '.' + @CurrentTest, @CurrentClass, @CurrentTest, 'Success');
            
            SET @SuccessCount = @SuccessCount + 1;
            PRINT '[PASS] ' + @CurrentClass + '.' + @CurrentTest;
        END TRY
        BEGIN CATCH
            INSERT INTO [tSQLt].[TestResults] ([TestCase], [Class], [TestName], [Result], [Message])
            VALUES (@CurrentClass + '.' + @CurrentTest, @CurrentClass, @CurrentTest, 'Failure', ERROR_MESSAGE());
            
            SET @FailureCount = @FailureCount + 1;
            PRINT '[FAIL] ' + @CurrentClass + '.' + @CurrentTest + ' - ' + ERROR_MESSAGE();
        END CATCH
        
        FETCH NEXT FROM test_cursor INTO @CurrentClass, @CurrentTest;
    END
    
    CLOSE test_cursor;
    DEALLOCATE test_cursor;
    
    PRINT '';
    PRINT 'Test Execution Summary:';
    PRINT '======================';
    PRINT 'Total Tests: ' + CAST(@TestCount AS NVARCHAR);
    PRINT 'Passed: ' + CAST(@SuccessCount AS NVARCHAR);
    PRINT 'Failed: ' + CAST(@FailureCount AS NVARCHAR);
    PRINT 'Success Rate: ' + CAST(CASE WHEN @TestCount > 0 THEN (@SuccessCount * 100) / @TestCount ELSE 0 END AS NVARCHAR) + '%';
    PRINT 'Completed at: ' + CONVERT(NVARCHAR, SYSDATETIME(), 120);
END
GO

-- Create assertion procedures for BDD-style testing
CREATE OR ALTER PROCEDURE [tSQLt].[AssertEquals]
    @Expected SQL_VARIANT,
    @Actual SQL_VARIANT,
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
    IF NOT (@Expected = @Actual OR (@Expected IS NULL AND @Actual IS NULL))
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = ISNULL(@Message, 'Assertion failed: Expected [' + ISNULL(CAST(@Expected AS NVARCHAR(MAX)), 'NULL') + '] but was [' + ISNULL(CAST(@Actual AS NVARCHAR(MAX)), 'NULL') + ']');
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [tSQLt].[AssertObjectExists]
    @ObjectName NVARCHAR(MAX),
    @ObjectType NVARCHAR(50) = NULL,
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
    DECLARE @Count INT;
    
    IF @ObjectType IS NULL OR @ObjectType = 'TABLE'
    BEGIN
        SELECT @Count = COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA + '.' + TABLE_NAME = @ObjectName OR TABLE_NAME = @ObjectName;
    END
    ELSE IF @ObjectType = 'SCHEMA'
    BEGIN
        SELECT @Count = COUNT(*) FROM sys.schemas WHERE name = @ObjectName;
    END
    ELSE IF @ObjectType = 'ROLE'
    BEGIN
        SELECT @Count = COUNT(*) FROM sys.database_principals WHERE name = @ObjectName AND type = 'R';
    END
    ELSE IF @ObjectType = 'USER'
    BEGIN
        SELECT @Count = COUNT(*) FROM sys.database_principals WHERE name = @ObjectName AND type = 'S';
    END
    ELSE IF @ObjectType = 'FUNCTION'
    BEGIN
        SELECT @Count = COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES 
        WHERE ROUTINE_SCHEMA + '.' + ROUTINE_NAME = @ObjectName AND ROUTINE_TYPE = 'FUNCTION';
    END
    ELSE IF @ObjectType = 'PROCEDURE'
    BEGIN
        SELECT @Count = COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES 
        WHERE ROUTINE_SCHEMA + '.' + ROUTINE_NAME = @ObjectName AND ROUTINE_TYPE = 'PROCEDURE';
    END
    ELSE IF @ObjectType = 'INDEX'
    BEGIN
        DECLARE @TableName NVARCHAR(MAX) = SUBSTRING(@ObjectName, 1, CHARINDEX('.', @ObjectName) - 1);
        DECLARE @IndexName NVARCHAR(MAX) = SUBSTRING(@ObjectName, CHARINDEX('.', @ObjectName) + 1, LEN(@ObjectName));
        SELECT @Count = COUNT(*) FROM sys.indexes i
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE i.name = @IndexName AND (s.name + '.' + t.name = @TableName OR t.name = @TableName);
    END
    
    IF @Count = 0
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = ISNULL(@Message, 'Object [' + @ObjectName + '] of type [' + ISNULL(@ObjectType, 'ANY') + '] does not exist');
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [tSQLt].[AssertTableColumnExists]
    @TableName NVARCHAR(MAX),
    @ColumnName NVARCHAR(MAX),
    @DataType NVARCHAR(50) = NULL,
    @IsNullable BIT = NULL,
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
    DECLARE @Count INT;
    DECLARE @ActualDataType NVARCHAR(50);
    DECLARE @ActualIsNullable BIT;
    
    SELECT 
        @Count = COUNT(*),
        @ActualDataType = MAX(DATA_TYPE),
        @ActualIsNullable = MAX(CASE WHEN IS_NULLABLE = 'YES' THEN 1 ELSE 0 END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE (TABLE_SCHEMA + '.' + TABLE_NAME = @TableName OR TABLE_NAME = @TableName)
    AND COLUMN_NAME = @ColumnName;
    
    IF @Count = 0
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = ISNULL(@Message, 'Column [' + @ColumnName + '] does not exist in table [' + @TableName + ']');
        THROW 50000, @ErrorMsg, 1;
    END
    
    IF @DataType IS NOT NULL AND @ActualDataType != @DataType
    BEGIN
        SET @ErrorMsg = ISNULL(@Message, 'Column [' + @ColumnName + '] has data type [' + @ActualDataType + '] but expected [' + @DataType + ']');
        THROW 50000, @ErrorMsg, 1;
    END
    
    IF @IsNullable IS NOT NULL AND @ActualIsNullable != @IsNullable
    BEGIN
        SET @ErrorMsg = ISNULL(@Message, 'Column [' + @ColumnName + '] nullable setting is [' + CAST(@ActualIsNullable AS NVARCHAR) + '] but expected [' + CAST(@IsNullable AS NVARCHAR) + ']');
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

CREATE OR ALTER PROCEDURE [tSQLt].[AssertDatabaseOptionEnabled]
    @OptionName NVARCHAR(100),
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
    DECLARE @IsEnabled BIT = 0;
    
    SELECT @IsEnabled = 
        CASE 
            WHEN @OptionName = 'READ_committed_snapshot' THEN is_read_committed_snapshot_on
            WHEN @OptionName = 'allow_snapshot_isolation' THEN snapshot_isolation_state
            WHEN @OptionName = 'is_broker_enabled' THEN is_broker_enabled
            WHEN @OptionName = 'page_verify_option' THEN CASE WHEN page_verify_option = 2 THEN 1 ELSE 0 END
            WHEN @OptionName = 'is_query_store_on' THEN is_query_store_on
            WHEN @OptionName = 'is_cdc_enabled' THEN is_cdc_enabled
            ELSE 0
        END
    FROM sys.databases 
    WHERE name = DB_NAME();
    
    IF @IsEnabled = 0
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(MAX) = ISNULL(@Message, 'Database option [' + @OptionName + '] is not enabled');
        THROW 50000, @ErrorMsg, 1;
    END
END
GO

PRINT 'tSQLt framework setup completed for CareSync database schema testing';
GO