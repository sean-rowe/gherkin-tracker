CREATE PROCEDURE setup.CreateAndConfigureCareSyncDatabase
AS
BEGIN
    -- Drop database if it exists (for development)
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'CareSync')
    BEGIN
        ALTER DATABASE CareSync SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE CareSync;
    END

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

    USE CareSync;

    -- Enable Change Data Capture for auditing
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'CareSync' AND is_cdc_enabled = 1)
    BEGIN
        EXEC sys.sp_cdc_enable_db;
    END
END;