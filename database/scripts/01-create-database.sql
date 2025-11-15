-- CareSync Database Creation Script
-- Creates the main CareSync database with proper configuration for multi-tenancy,
-- performance, and HIPAA compliance

USE master;



-- Create CareSync database with optimized settings
CREATE DATABASE CareSync
ON 
(
    NAME = 'CareSync_Data',
    FILENAME = '/var/opt/mssql/data/CareSync.mdf',
    SIZE = 1GB,
    MAXSIZE = 100GB,
    FILEGROWTH = 256MB
)
LOG ON 
(
    NAME = 'CareSync_Log',
    FILENAME = '/var/opt/mssql/data/CareSync.ldf',
    SIZE = 256MB,
    MAXSIZE = 10GB,
    FILEGROWTH = 64MB
);

-- Configure database options for performance and security
ALTER DATABASE CareSync SET RECOVERY FULL;
ALTER DATABASE CareSync SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE CareSync SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE CareSync SET AUTO_UPDATE_STATISTICS_ASYNC ON;
ALTER DATABASE CareSync SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE CareSync SET ENABLE_BROKER;
ALTER DATABASE CareSync SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE CareSync SET ALLOW_SNAPSHOT_ISOLATION ON;

-- Configure Query Store for performance monitoring
ALTER DATABASE CareSync SET QUERY_STORE = ON;
ALTER DATABASE CareSync SET QUERY_STORE 
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);



-- Enable Change Data Capture for auditing
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'CareSync' AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END

-- Create application roles for security
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_Application' AND type = 'R') CREATE ROLE [CareSync_Application];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_ReadOnly' AND type = 'R') CREATE ROLE [CareSync_ReadOnly];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_Analytics' AND type = 'R') CREATE ROLE [CareSync_Analytics];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_Admin' AND type = 'R') CREATE ROLE [CareSync_Admin];

-- Create database users for application services
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_API') CREATE USER [CareSync_API] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_BackgroundJobs') CREATE USER [CareSync_BackgroundJobs] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_Analytics_Service') CREATE USER [CareSync_Analytics_Service] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CareSync_Audit_Service') CREATE USER [CareSync_Audit_Service] WITHOUT LOGIN;

-- Assign users to roles
ALTER ROLE [CareSync_Application] ADD MEMBER [CareSync_API];
ALTER ROLE [CareSync_Application] ADD MEMBER [CareSync_BackgroundJobs];
ALTER ROLE [CareSync_Analytics] ADD MEMBER [CareSync_Analytics_Service];
ALTER ROLE [CareSync_ReadOnly] ADD MEMBER [CareSync_Audit_Service];

PRINT 'CareSync database created successfully with optimized configuration';