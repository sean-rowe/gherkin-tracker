-- Create CareSync Project Management Database
USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'CareSyncProject')
BEGIN
    CREATE DATABASE CareSyncProject;
    PRINT 'Database CareSyncProject created successfully';
END
ELSE
BEGIN
    PRINT 'Database CareSyncProject already exists';
END
GO

USE CareSyncProject;
GO

PRINT 'Switched to CareSyncProject database';
GO
