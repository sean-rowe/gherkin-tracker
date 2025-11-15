CREATE PROCEDURE DatabaseSetupTests.[test CreateIdentityUsersTable creates Users table with multi-tenancy support]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable 'sys.tables';
    EXEC tSQLt.FakeTable 'sys.schemas';
    INSERT INTO sys.schemas (name) VALUES ('Identity');

    -- Act
    EXEC setup.CreateIdentityUsersTable;

    -- Assert
    EXEC tSQLt.AssertObjectExists 'Identity.Users';
    EXEC tSQLt.AssertObjectExists 'IX_Users_TenantId_NormalizedEmail';

    -- Verify columns
    EXEC tSQLt.AssertEqualsTableSchema 'ExpectedIdentityUsersTable', 'Identity.Users';
END;
GO

CREATE TABLE ExpectedIdentityUsersTable
(
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    TenantId NVARCHAR(128) NOT NULL,
    Email NVARCHAR(256) NOT NULL,
    NormalizedEmail NVARCHAR(256) NOT NULL,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    PhoneNumber NVARCHAR(20) NULL,
    EmailVerified BIT NOT NULL DEFAULT 0,
    TwoFactorEnabled BIT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    IsDeleted BIT NOT NULL DEFAULT 0,
    RowVersion ROWVERSION NOT NULL
);