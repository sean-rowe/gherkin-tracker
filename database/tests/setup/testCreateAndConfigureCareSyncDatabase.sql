CREATE PROCEDURE DatabaseSetupTests.[test CreateAndConfigureCareSyncDatabase creates and configures the database]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable 'sys.databases';
    INSERT INTO sys.databases (name, is_cdc_enabled) VALUES ('CareSync', 0);

    -- Act
    EXEC setup.CreateAndConfigureCareSyncDatabase;

    -- Assert
    EXEC tSQLt.AssertEquals 1, (SELECT is_cdc_enabled FROM sys.databases WHERE name = 'CareSync');
END;