-- CareSync Communication Tables Creation Script
-- Creates tables for messaging, notifications, and file attachments

USE CareSync;
GO

-- =============================================
-- Communication Schema Tables
-- =============================================

-- Messages table for care team communication
CREATE TABLE [Communication].[Messages] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [CareTeamId] UNIQUEIDENTIFIER NOT NULL,
    [SenderId] UNIQUEIDENTIFIER NOT NULL,
    [Content] NVARCHAR(MAX) NOT NULL,
    [MessageType] NVARCHAR(50) NOT NULL DEFAULT 'text',
    [Priority] NVARCHAR(20) NOT NULL DEFAULT 'normal',
    [IsUrgent] BIT NOT NULL DEFAULT 0,
    [MentionedUsers] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [ReplyToMessageId] UNIQUEIDENTIFIER NULL,
    [ThreadId] UNIQUEIDENTIFIER NULL,
    [Attachments] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [ScheduledSendAt] DATETIMEOFFSET NULL,
    [IsSent] BIT NOT NULL DEFAULT 1,
    [ReadReceipts] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [DeliveryStatus] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [IsEdited] BIT NOT NULL DEFAULT 0,
    [EditHistory] NVARCHAR(MAX) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Messages_CareTeams] FOREIGN KEY ([CareTeamId]) 
        REFERENCES [Care].[CareTeams] ([Id]),
    CONSTRAINT [FK_Messages_Sender] FOREIGN KEY ([SenderId]) 
        REFERENCES [Identity].[Users] ([Id]),
    CONSTRAINT [FK_Messages_ReplyTo] FOREIGN KEY ([ReplyToMessageId]) 
        REFERENCES [Communication].[Messages] ([Id])
);

-- Partitioning by month for performance
CREATE PARTITION FUNCTION [PF_Messages_CreatedAt] (DATETIMEOFFSET)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', '2024-05-01', '2024-06-01',
    '2024-07-01', '2024-08-01', '2024-09-01', '2024-10-01', '2024-11-01', '2024-12-01',
    '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01', '2025-05-01', '2025-06-01',
    '2025-07-01', '2025-08-01', '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01'
);

CREATE PARTITION SCHEME [PS_Messages_CreatedAt]
AS PARTITION [PF_Messages_CreatedAt] ALL TO ([PRIMARY]);

-- Create partitioned clustered index
CREATE CLUSTERED INDEX [IX_Messages_Partitioned] 
ON [Communication].[Messages] ([CreatedAt], [Id])
ON [PS_Messages_CreatedAt] ([CreatedAt]);

CREATE INDEX [IX_Messages_CareTeamId] ON [Communication].[Messages] ([CareTeamId], [CreatedAt]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Messages_SenderId] ON [Communication].[Messages] ([SenderId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Messages_ThreadId] ON [Communication].[Messages] ([ThreadId]) WHERE [IsDeleted] = 0 AND [ThreadId] IS NOT NULL;
CREATE INDEX [IX_Messages_Priority] ON [Communication].[Messages] ([Priority], [IsUrgent]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Messages_ScheduledSend] ON [Communication].[Messages] ([ScheduledSendAt]) WHERE [IsDeleted] = 0 AND [ScheduledSendAt] IS NOT NULL;
GO

-- Notifications table for system-wide notifications
CREATE TABLE [Communication].[Notifications] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [UserId] UNIQUEIDENTIFIER NOT NULL,
    [Title] NVARCHAR(200) NOT NULL,
    [Content] NVARCHAR(1000) NOT NULL,
    [NotificationType] NVARCHAR(50) NOT NULL,
    [Priority] NVARCHAR(20) NOT NULL DEFAULT 'normal',
    [RelatedEntityType] NVARCHAR(100) NULL,
    [RelatedEntityId] UNIQUEIDENTIFIER NULL,
    [ActionUrl] NVARCHAR(2048) NULL,
    [IsRead] BIT NOT NULL DEFAULT 0,
    [ReadAt] DATETIMEOFFSET NULL,
    [ScheduledAt] DATETIMEOFFSET NULL,
    [IsDelivered] BIT NOT NULL DEFAULT 0,
    [DeliveredAt] DATETIMEOFFSET NULL,
    [DeliveryChannels] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [ExpiresAt] DATETIMEOFFSET NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Notifications_Users] FOREIGN KEY ([UserId]) 
        REFERENCES [Identity].[Users] ([Id])
);

-- Partitioning by month for performance
CREATE PARTITION FUNCTION [PF_Notifications_CreatedAt] (DATETIMEOFFSET)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', '2024-05-01', '2024-06-01',
    '2024-07-01', '2024-08-01', '2024-09-01', '2024-10-01', '2024-11-01', '2024-12-01',
    '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01', '2025-05-01', '2025-06-01',
    '2025-07-01', '2025-08-01', '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01'
);

CREATE PARTITION SCHEME [PS_Notifications_CreatedAt]
AS PARTITION [PF_Notifications_CreatedAt] ALL TO ([PRIMARY]);

-- Create partitioned clustered index
CREATE CLUSTERED INDEX [IX_Notifications_Partitioned] 
ON [Communication].[Notifications] ([CreatedAt], [Id])
ON [PS_Notifications_CreatedAt] ([CreatedAt]);

CREATE INDEX [IX_Notifications_UserId] ON [Communication].[Notifications] ([UserId], [IsRead]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Notifications_Type] ON [Communication].[Notifications] ([NotificationType]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Notifications_Scheduled] ON [Communication].[Notifications] ([ScheduledAt]) WHERE [IsDeleted] = 0 AND [ScheduledAt] IS NOT NULL;
CREATE INDEX [IX_Notifications_Expires] ON [Communication].[Notifications] ([ExpiresAt]) WHERE [IsDeleted] = 0 AND [ExpiresAt] IS NOT NULL;
GO

-- Attachments table for files, photos, videos, documents
CREATE TABLE [Communication].[Attachments] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [TrackingEntryId] UNIQUEIDENTIFIER NULL,
    [MessageId] UNIQUEIDENTIFIER NULL,
    [FileName] NVARCHAR(255) NOT NULL,
    [FilePath] NVARCHAR(2048) NOT NULL,
    [ContentType] NVARCHAR(100) NOT NULL,
    [FileSize] BIGINT NOT NULL,
    [AttachmentType] NVARCHAR(50) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [ThumbnailUrl] NVARCHAR(2048) NULL,
    [PrivacyLevel] NVARCHAR(20) NOT NULL DEFAULT 'team',
    [ContainsPHI] BIT NOT NULL DEFAULT 0,
    [EncryptionKeyId] NVARCHAR(256) NULL,
    [UploadedBy] UNIQUEIDENTIFIER NOT NULL,
    [VirusScanStatus] NVARCHAR(20) NOT NULL DEFAULT 'pending',
    [VirusScanResult] NVARCHAR(50) NULL,
    [CompletedProcessing] BIT NOT NULL DEFAULT 0,
    [ProcessingError] NVARCHAR(1000) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Attachments_TrackingEntries] FOREIGN KEY ([TrackingEntryId]) 
        REFERENCES [Clinical].[TrackingEntries] ([Id]),
    CONSTRAINT [FK_Attachments_Messages] FOREIGN KEY ([MessageId]) 
        REFERENCES [Communication].[Messages] ([Id]),
    CONSTRAINT [FK_Attachments_UploadedBy] FOREIGN KEY ([UploadedBy]) 
        REFERENCES [Identity].[Users] ([Id]),
    CONSTRAINT [CK_Attachments_Parent] CHECK (
        ([TrackingEntryId] IS NOT NULL AND [MessageId] IS NULL) OR 
        ([TrackingEntryId] IS NULL AND [MessageId] IS NOT NULL)
    )
);

CREATE INDEX [IX_Attachments_TrackingEntryId] ON [Communication].[Attachments] ([TrackingEntryId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Attachments_MessageId] ON [Communication].[Attachments] ([MessageId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Attachments_UploadedBy] ON [Communication].[Attachments] ([UploadedBy]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Attachments_AttachmentType] ON [Communication].[Attachments] ([AttachmentType]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Attachments_ContainsPHI] ON [Communication].[Attachments] ([ContainsPHI]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Attachments_VirusScan] ON [Communication].[Attachments] ([VirusScanStatus]) WHERE [IsDeleted] = 0;
GO

-- Message translations for multi-language support
CREATE TABLE [Communication].[MessageTranslations] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [MessageId] UNIQUEIDENTIFIER NOT NULL,
    [LanguageCode] NVARCHAR(10) NOT NULL,
    [TranslatedContent] NVARCHAR(MAX) NOT NULL,
    [TranslationProvider] NVARCHAR(50) NOT NULL DEFAULT 'azure',
    [ConfidenceScore] DECIMAL(5,4) NULL,
    [IsHumanReviewed] BIT NOT NULL DEFAULT 0,
    [ReviewedBy] UNIQUEIDENTIFIER NULL,
    [ReviewedAt] DATETIMEOFFSET NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_MessageTranslations_Messages] FOREIGN KEY ([MessageId]) 
        REFERENCES [Communication].[Messages] ([Id]),
    CONSTRAINT [FK_MessageTranslations_ReviewedBy] FOREIGN KEY ([ReviewedBy]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE UNIQUE INDEX [IX_MessageTranslations_Unique] ON [Communication].[MessageTranslations] ([MessageId], [LanguageCode]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_MessageTranslations_LanguageCode] ON [Communication].[MessageTranslations] ([LanguageCode]) WHERE [IsDeleted] = 0;
GO

-- Email templates for system notifications
CREATE TABLE [Communication].[EmailTemplates] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [Name] NVARCHAR(100) NOT NULL,
    [Subject] NVARCHAR(200) NOT NULL,
    [HtmlContent] NVARCHAR(MAX) NOT NULL,
    [TextContent] NVARCHAR(MAX) NOT NULL,
    [TemplateType] NVARCHAR(50) NOT NULL,
    [LanguageCode] NVARCHAR(10) NOT NULL DEFAULT 'en',
    [IsActive] BIT NOT NULL DEFAULT 1,
    [Variables] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [Category] NVARCHAR(50) NOT NULL,
    [SendFromName] NVARCHAR(100) NULL,
    [SendFromEmail] NVARCHAR(256) NULL,
    [ReplyToEmail] NVARCHAR(256) NULL,
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

CREATE UNIQUE INDEX [IX_EmailTemplates_Name] ON [Communication].[EmailTemplates] ([Name], [LanguageCode]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_EmailTemplates_Type] ON [Communication].[EmailTemplates] ([TemplateType]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_EmailTemplates_Category] ON [Communication].[EmailTemplates] ([Category]) WHERE [IsDeleted] = 0;
GO

-- Email queue for outbound emails
CREATE TABLE [Communication].[EmailQueue] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [ToEmails] NVARCHAR(MAX) NOT NULL,
    [CcEmails] NVARCHAR(MAX) NULL,
    [BccEmails] NVARCHAR(MAX) NULL,
    [Subject] NVARCHAR(200) NOT NULL,
    [HtmlContent] NVARCHAR(MAX) NOT NULL,
    [TextContent] NVARCHAR(MAX) NOT NULL,
    [FromName] NVARCHAR(100) NOT NULL,
    [FromEmail] NVARCHAR(256) NOT NULL,
    [ReplyToEmail] NVARCHAR(256) NULL,
    [Priority] INT NOT NULL DEFAULT 3, -- 1=high, 3=normal, 5=low
    [ScheduledAt] DATETIMEOFFSET NULL,
    [AttemptCount] INT NOT NULL DEFAULT 0,
    [MaxAttempts] INT NOT NULL DEFAULT 3,
    [Status] NVARCHAR(20) NOT NULL DEFAULT 'pending',
    [SentAt] DATETIMEOFFSET NULL,
    [ErrorMessage] NVARCHAR(1000) NULL,
    [ExternalMessageId] NVARCHAR(256) NULL,
    [TemplateId] UNIQUEIDENTIFIER NULL,
    [TemplateData] NVARCHAR(MAX) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_EmailQueue_Templates] FOREIGN KEY ([TemplateId]) 
        REFERENCES [Communication].[EmailTemplates] ([Id])
);

CREATE INDEX [IX_EmailQueue_Status] ON [Communication].[EmailQueue] ([Status], [Priority]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_EmailQueue_Scheduled] ON [Communication].[EmailQueue] ([ScheduledAt]) WHERE [IsDeleted] = 0 AND [ScheduledAt] IS NOT NULL;
CREATE INDEX [IX_EmailQueue_AttemptCount] ON [Communication].[EmailQueue] ([AttemptCount], [MaxAttempts]) WHERE [IsDeleted] = 0;
GO

-- Push notification queue
CREATE TABLE [Communication].[PushNotificationQueue] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [UserId] UNIQUEIDENTIFIER NOT NULL,
    [DeviceTokens] NVARCHAR(MAX) NOT NULL,
    [Title] NVARCHAR(100) NOT NULL,
    [Body] NVARCHAR(500) NOT NULL,
    [Data] NVARCHAR(MAX) NULL,
    [Platform] NVARCHAR(20) NOT NULL,
    [Priority] NVARCHAR(10) NOT NULL DEFAULT 'normal',
    [ScheduledAt] DATETIMEOFFSET NULL,
    [AttemptCount] INT NOT NULL DEFAULT 0,
    [MaxAttempts] INT NOT NULL DEFAULT 3,
    [Status] NVARCHAR(20) NOT NULL DEFAULT 'pending',
    [SentAt] DATETIMEOFFSET NULL,
    [ErrorMessage] NVARCHAR(1000) NULL,
    [ExternalMessageId] NVARCHAR(256) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_PushNotificationQueue_Users] FOREIGN KEY ([UserId]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_PushNotificationQueue_Status] ON [Communication].[PushNotificationQueue] ([Status], [Priority]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_PushNotificationQueue_UserId] ON [Communication].[PushNotificationQueue] ([UserId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_PushNotificationQueue_Scheduled] ON [Communication].[PushNotificationQueue] ([ScheduledAt]) WHERE [IsDeleted] = 0 AND [ScheduledAt] IS NOT NULL;
GO

PRINT 'Communication schema tables created successfully';
GO