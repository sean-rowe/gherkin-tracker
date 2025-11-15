-- CareSync Table Creation Script
-- Creates all tables with multi-tenancy, row-level security, and audit support

USE CareSync;
GO

-- =============================================
-- Identity Schema Tables
-- =============================================

-- Users table with comprehensive authentication support
CREATE TABLE [Identity].[Users] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [Email] NVARCHAR(256) NOT NULL,
    [NormalizedEmail] NVARCHAR(256) NOT NULL,
    [FirstName] NVARCHAR(100) NOT NULL,
    [LastName] NVARCHAR(100) NOT NULL,
    [PhoneNumber] NVARCHAR(20) NULL,
    [DateOfBirth] DATE NULL,
    [ProfilePictureUrl] NVARCHAR(2048) NULL,
    [TimeZone] NVARCHAR(50) NOT NULL DEFAULT 'UTC',
    [LanguageCode] NVARCHAR(10) NOT NULL DEFAULT 'en',
    [EmailVerified] BIT NOT NULL DEFAULT 0,
    [PhoneVerified] BIT NOT NULL DEFAULT 0,
    [TwoFactorEnabled] BIT NOT NULL DEFAULT 0,
    [LastLoginAt] DATETIMEOFFSET NULL,
    [LockoutEnd] DATETIMEOFFSET NULL,
    [AccessFailedCount] INT NOT NULL DEFAULT 0,
    [IsActive] BIT NOT NULL DEFAULT 1,
    [ExternalProvider] NVARCHAR(50) NULL,
    [ExternalUserId] NVARCHAR(256) NULL,
    [NotificationPreferences] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [AccessibilityPreferences] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [TermsAcceptedAt] DATETIMEOFFSET NULL,
    [PrivacyPolicyAcceptedAt] DATETIMEOFFSET NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL
);

-- Create indexes for Users table
CREATE UNIQUE INDEX [IX_Users_Email] ON [Identity].[Users] ([TenantId], [NormalizedEmail]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Users_TenantId] ON [Identity].[Users] ([TenantId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Users_ExternalProvider] ON [Identity].[Users] ([ExternalProvider], [ExternalUserId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Users_LastLogin] ON [Identity].[Users] ([LastLoginAt]) WHERE [IsDeleted] = 0;
GO

-- Device registrations for push notifications
CREATE TABLE [Identity].[DeviceRegistrations] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [UserId] UNIQUEIDENTIFIER NOT NULL,
    [DeviceToken] NVARCHAR(1024) NOT NULL,
    [Platform] NVARCHAR(50) NOT NULL,
    [DeviceModel] NVARCHAR(100) NULL,
    [OSVersion] NVARCHAR(50) NULL,
    [AppVersion] NVARCHAR(50) NULL,
    [IsActive] BIT NOT NULL DEFAULT 1,
    [LastSeenAt] DATETIMEOFFSET NULL,
    [NotificationSettings] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_DeviceRegistrations_Users] FOREIGN KEY ([UserId]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_DeviceRegistrations_UserId] ON [Identity].[DeviceRegistrations] ([UserId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_DeviceRegistrations_Platform] ON [Identity].[DeviceRegistrations] ([Platform]) WHERE [IsDeleted] = 0;
GO

-- =============================================
-- Care Schema Tables
-- =============================================

-- Patients table
CREATE TABLE [Care].[Patients] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [FirstName] NVARCHAR(100) NOT NULL,
    [LastName] NVARCHAR(100) NOT NULL,
    [DateOfBirth] DATE NOT NULL,
    [Gender] NVARCHAR(20) NOT NULL,
    [ProfilePictureUrl] NVARCHAR(2048) NULL,
    [PrimaryDiagnosis] NVARCHAR(500) NULL,
    [SecondaryDiagnoses] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [Allergies] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [MedicalRecordNumber] NVARCHAR(100) NULL,
    [InsuranceInformation] NVARCHAR(MAX) NULL, -- Encrypted
    [TimeZone] NVARCHAR(50) NOT NULL DEFAULT 'UTC',
    [PrimaryUserId] UNIQUEIDENTIFIER NOT NULL,
    [PrivacySettings] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [TrackingConfigurations] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Patients_PrimaryUser] FOREIGN KEY ([PrimaryUserId]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_Patients_TenantId] ON [Care].[Patients] ([TenantId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Patients_PrimaryUserId] ON [Care].[Patients] ([PrimaryUserId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Patients_DateOfBirth] ON [Care].[Patients] ([DateOfBirth]) WHERE [IsDeleted] = 0;
GO

-- Care teams table
CREATE TABLE [Care].[CareTeams] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [Description] NVARCHAR(1000) NULL,
    [MaxMembers] INT NOT NULL DEFAULT 50,
    [RequireApproval] BIT NOT NULL DEFAULT 1,
    [CommunicationPreferences] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_CareTeams_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id])
);

CREATE INDEX [IX_CareTeams_PatientId] ON [Care].[CareTeams] ([PatientId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_CareTeams_TenantId] ON [Care].[CareTeams] ([TenantId]) WHERE [IsDeleted] = 0;
GO

-- Care team members table
CREATE TABLE [Care].[CareTeamMembers] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [CareTeamId] UNIQUEIDENTIFIER NOT NULL,
    [UserId] UNIQUEIDENTIFIER NOT NULL,
    [Role] INT NOT NULL, -- UserRole enum
    [CustomRoleTitle] NVARCHAR(100) NULL,
    [Organization] NVARCHAR(200) NULL,
    [IsAdmin] BIT NOT NULL DEFAULT 0,
    [Permissions] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [JoinedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [IsActive] BIT NOT NULL DEFAULT 1,
    [LastActiveAt] DATETIMEOFFSET NULL,
    [NotificationPreferences] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_CareTeamMembers_CareTeams] FOREIGN KEY ([CareTeamId]) 
        REFERENCES [Care].[CareTeams] ([Id]),
    CONSTRAINT [FK_CareTeamMembers_Users] FOREIGN KEY ([UserId]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE UNIQUE INDEX [IX_CareTeamMembers_Unique] ON [Care].[CareTeamMembers] ([CareTeamId], [UserId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_CareTeamMembers_UserId] ON [Care].[CareTeamMembers] ([UserId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_CareTeamMembers_Role] ON [Care].[CareTeamMembers] ([Role]) WHERE [IsDeleted] = 0;
GO

-- Care team invitations table
CREATE TABLE [Care].[CareTeamInvitations] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [CareTeamId] UNIQUEIDENTIFIER NOT NULL,
    [Email] NVARCHAR(256) NOT NULL,
    [PhoneNumber] NVARCHAR(20) NULL,
    [ProposedRole] INT NOT NULL,
    [CustomRoleTitle] NVARCHAR(100) NULL,
    [Organization] NVARCHAR(200) NULL,
    [InvitationMessage] NVARCHAR(1000) NULL,
    [InvitedBy] UNIQUEIDENTIFIER NOT NULL,
    [InvitationToken] NVARCHAR(256) NOT NULL,
    [ExpiresAt] DATETIMEOFFSET NOT NULL,
    [IsSent] BIT NOT NULL DEFAULT 0,
    [SentAt] DATETIMEOFFSET NULL,
    [IsAccepted] BIT NOT NULL DEFAULT 0,
    [AcceptedAt] DATETIMEOFFSET NULL,
    [IsRejected] BIT NOT NULL DEFAULT 0,
    [RejectedAt] DATETIMEOFFSET NULL,
    [RejectionReason] NVARCHAR(500) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_CareTeamInvitations_CareTeams] FOREIGN KEY ([CareTeamId]) 
        REFERENCES [Care].[CareTeams] ([Id]),
    CONSTRAINT [FK_CareTeamInvitations_InvitedBy] FOREIGN KEY ([InvitedBy]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_CareTeamInvitations_CareTeamId] ON [Care].[CareTeamInvitations] ([CareTeamId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_CareTeamInvitations_Email] ON [Care].[CareTeamInvitations] ([Email]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_CareTeamInvitations_Token] ON [Care].[CareTeamInvitations] ([InvitationToken]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_CareTeamInvitations_ExpiresAt] ON [Care].[CareTeamInvitations] ([ExpiresAt]) WHERE [IsDeleted] = 0;
GO

-- Emergency contacts table
CREATE TABLE [Care].[EmergencyContacts] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [Relationship] NVARCHAR(100) NOT NULL,
    [PhoneNumber] NVARCHAR(20) NOT NULL,
    [AlternativePhoneNumber] NVARCHAR(20) NULL,
    [Email] NVARCHAR(256) NULL,
    [Address] NVARCHAR(500) NULL,
    [Priority] INT NOT NULL DEFAULT 1,
    [AuthorizedForMedicalDecisions] BIT NOT NULL DEFAULT 0,
    [CanPickUp] BIT NOT NULL DEFAULT 0,
    [Notes] NVARCHAR(1000) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_EmergencyContacts_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id])
);

CREATE INDEX [IX_EmergencyContacts_PatientId] ON [Care].[EmergencyContacts] ([PatientId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_EmergencyContacts_Priority] ON [Care].[EmergencyContacts] ([PatientId], [Priority]) WHERE [IsDeleted] = 0;
GO

-- Medical history table
CREATE TABLE [Care].[MedicalHistory] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [EntryType] NVARCHAR(100) NOT NULL,
    [Title] NVARCHAR(300) NOT NULL,
    [Description] NVARCHAR(2000) NULL,
    [Date] DATE NOT NULL,
    [EndDate] DATE NULL,
    [HealthcareProvider] NVARCHAR(300) NULL,
    [ICD10Code] NVARCHAR(20) NULL,
    [Severity] NVARCHAR(50) NULL,
    [Status] NVARCHAR(50) NOT NULL,
    [Documents] NVARCHAR(MAX) NULL,
    [IsActive] BIT NOT NULL DEFAULT 1,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_MedicalHistory_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id])
);

CREATE INDEX [IX_MedicalHistory_PatientId] ON [Care].[MedicalHistory] ([PatientId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_MedicalHistory_Date] ON [Care].[MedicalHistory] ([PatientId], [Date]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_MedicalHistory_EntryType] ON [Care].[MedicalHistory] ([EntryType]) WHERE [IsDeleted] = 0;
GO

PRINT 'Identity and Care schema tables created successfully';
GO