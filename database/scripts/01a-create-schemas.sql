-- Create schemas if they don't exist (idempotent)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Identity')
    EXEC('CREATE SCHEMA [Identity]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Care')
    EXEC('CREATE SCHEMA [Care]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Clinical')
    EXEC('CREATE SCHEMA [Clinical]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Communication')
    EXEC('CREATE SCHEMA [Communication]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Analytics')
    EXEC('CREATE SCHEMA [Analytics]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Audit')
    EXEC('CREATE SCHEMA [Audit]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Reference')
    EXEC('CREATE SCHEMA [Reference]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Security')
    EXEC('CREATE SCHEMA [Security]');