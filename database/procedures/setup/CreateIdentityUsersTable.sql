CREATE PROCEDURE setup.CreateIdentityUsersTable
AS
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Users' AND schema_id = SCHEMA_ID('Identity'))
    BEGIN
        EXEC('        CREATE TABLE Identity.Users
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
        );');

        EXEC('        CREATE UNIQUE INDEX IX_Users_TenantId_NormalizedEmail ON Identity.Users (TenantId, NormalizedEmail) WHERE IsDeleted = 0;
    END');
    END
END;