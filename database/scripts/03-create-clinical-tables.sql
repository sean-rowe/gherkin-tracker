-- CareSync Clinical Tables Creation Script
-- Creates all clinical tracking tables (symptoms, medications, behaviors, tracking entries)

USE CareSync;
GO

-- =============================================
-- Clinical Schema Tables
-- =============================================

-- Base tracking entries table
CREATE TABLE [Clinical].[TrackingEntries] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [EnteredBy] UNIQUEIDENTIFIER NOT NULL,
    [TrackingType] INT NOT NULL, -- TrackingType enum
    [OccurredAt] DATETIMEOFFSET NOT NULL,
    [TimeZone] NVARCHAR(50) NOT NULL DEFAULT 'UTC',
    [Duration] TIME NULL,
    [SeverityNumeric] INT NULL,
    [SeverityDescriptive] INT NULL, -- DescriptiveSeverity enum
    [SeverityVisual] INT NULL, -- VisualSeverity enum
    [SeverityScaleType] INT NOT NULL DEFAULT 0, -- SeverityScaleType enum
    [Location] NVARCHAR(300) NULL,
    [Coordinates] NVARCHAR(100) NULL, -- GPS coordinates
    [Notes] NVARCHAR(MAX) NULL,
    [VoiceTranscription] NVARCHAR(MAX) NULL,
    [Tags] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [CustomFields] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [EnvironmentalData] NVARCHAR(MAX) NULL,
    [IsFlagged] BIT NOT NULL DEFAULT 0,
    [FlagReason] NVARCHAR(500) NULL,
    [ConfidenceLevel] DECIMAL(5,4) NULL,
    [DataSource] NVARCHAR(100) NOT NULL DEFAULT 'manual',
    [ExternalId] NVARCHAR(256) NULL,
    [IsEdited] BIT NOT NULL DEFAULT 0,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_TrackingEntries_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id]),
    CONSTRAINT [FK_TrackingEntries_EnteredBy] FOREIGN KEY ([EnteredBy]) 
        REFERENCES [Identity].[Users] ([Id])
);

-- Partitioning by month for performance
CREATE PARTITION FUNCTION [PF_TrackingEntries_OccurredAt] (DATETIMEOFFSET)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', '2024-05-01', '2024-06-01',
    '2024-07-01', '2024-08-01', '2024-09-01', '2024-10-01', '2024-11-01', '2024-12-01',
    '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01', '2025-05-01', '2025-06-01',
    '2025-07-01', '2025-08-01', '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01'
);

CREATE PARTITION SCHEME [PS_TrackingEntries_OccurredAt]
AS PARTITION [PF_TrackingEntries_OccurredAt] ALL TO ([PRIMARY]);

-- Create partitioned clustered index
CREATE CLUSTERED INDEX [IX_TrackingEntries_Partitioned] 
ON [Clinical].[TrackingEntries] ([OccurredAt], [Id])
ON [PS_TrackingEntries_OccurredAt] ([OccurredAt]);

CREATE INDEX [IX_TrackingEntries_PatientId] ON [Clinical].[TrackingEntries] ([PatientId], [OccurredAt]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_TrackingEntries_EnteredBy] ON [Clinical].[TrackingEntries] ([EnteredBy]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_TrackingEntries_TrackingType] ON [Clinical].[TrackingEntries] ([TrackingType], [OccurredAt]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_TrackingEntries_Location] ON [Clinical].[TrackingEntries] ([Location]) WHERE [IsDeleted] = 0 AND [Location] IS NOT NULL;
GO

-- Tracking entry edits for audit trail and conflict resolution
CREATE TABLE [Clinical].[TrackingEntryEdits] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [TrackingEntryId] UNIQUEIDENTIFIER NOT NULL,
    [EditedBy] UNIQUEIDENTIFIER NOT NULL,
    [ChangedFields] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [PreviousValues] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [NewValues] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [EditReason] NVARCHAR(500) NULL,
    [IsConflictResolution] BIT NOT NULL DEFAULT 0,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_TrackingEntryEdits_TrackingEntries] FOREIGN KEY ([TrackingEntryId]) 
        REFERENCES [Clinical].[TrackingEntries] ([Id]),
    CONSTRAINT [FK_TrackingEntryEdits_EditedBy] FOREIGN KEY ([EditedBy]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_TrackingEntryEdits_TrackingEntryId] ON [Clinical].[TrackingEntryEdits] ([TrackingEntryId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_TrackingEntryEdits_EditedBy] ON [Clinical].[TrackingEntryEdits] ([EditedBy]) WHERE [IsDeleted] = 0;
GO

-- Symptoms table
CREATE TABLE [Clinical].[Symptoms] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [Description] NVARCHAR(1000) NULL,
    [Category] NVARCHAR(100) NOT NULL,
    [Subcategory] NVARCHAR(100) NULL,
    [ICD10Code] NVARCHAR(20) NULL,
    [SnomedCode] NVARCHAR(50) NULL,
    [IsCustom] BIT NOT NULL DEFAULT 0,
    [PreferredSeverityScale] INT NOT NULL DEFAULT 0,
    [CustomSeverityScale] NVARCHAR(MAX) NULL,
    [BodyLocations] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [CommonTriggers] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [TrackDuration] BIT NOT NULL DEFAULT 1,
    [TrackLocation] BIT NOT NULL DEFAULT 0,
    [AllowPhotos] BIT NOT NULL DEFAULT 1,
    [CustomFields] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [Color] NVARCHAR(7) NULL,
    [Icon] NVARCHAR(100) NULL,
    [IsActive] BIT NOT NULL DEFAULT 1,
    [ReminderFrequencyHours] INT NULL,
    [QuickEntryTemplates] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Symptoms_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id])
);

CREATE INDEX [IX_Symptoms_PatientId] ON [Clinical].[Symptoms] ([PatientId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Symptoms_Category] ON [Clinical].[Symptoms] ([Category]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Symptoms_IsActive] ON [Clinical].[Symptoms] ([PatientId], [IsActive]) WHERE [IsDeleted] = 0;
GO

-- Symptom triggers table
CREATE TABLE [Clinical].[SymptomTriggers] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [SymptomId] UNIQUEIDENTIFIER NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [Category] NVARCHAR(100) NOT NULL,
    [Severity] INT NULL,
    [ConfidenceLevel] DECIMAL(5,4) NOT NULL DEFAULT 0.5,
    [IsAIIdentified] BIT NOT NULL DEFAULT 0,
    [ObservationCount] INT NOT NULL DEFAULT 1,
    [LastObservedAt] DATETIMEOFFSET NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_SymptomTriggers_Symptoms] FOREIGN KEY ([SymptomId]) 
        REFERENCES [Clinical].[Symptoms] ([Id])
);

CREATE INDEX [IX_SymptomTriggers_SymptomId] ON [Clinical].[SymptomTriggers] ([SymptomId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_SymptomTriggers_Category] ON [Clinical].[SymptomTriggers] ([Category]) WHERE [IsDeleted] = 0;
GO

-- Medications table
CREATE TABLE [Clinical].[Medications] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [GenericName] NVARCHAR(200) NULL,
    [ActiveIngredient] NVARCHAR(500) NULL,
    [Dosage] NVARCHAR(100) NOT NULL,
    [Form] NVARCHAR(50) NOT NULL,
    [Route] NVARCHAR(50) NOT NULL,
    [Frequency] NVARCHAR(200) NOT NULL,
    [ScheduleConfiguration] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [Instructions] NVARCHAR(1000) NULL,
    [Purpose] NVARCHAR(500) NULL,
    [PrescriberId] UNIQUEIDENTIFIER NULL,
    [PrescriberInfo] NVARCHAR(500) NULL,
    [PrescribedDate] DATE NULL,
    [StartDate] DATE NOT NULL,
    [EndDate] DATE NULL,
    [NDCNumber] NVARCHAR(20) NULL,
    [RxNormId] NVARCHAR(20) NULL,
    [Color] NVARCHAR(7) NULL,
    [PhotoUrl] NVARCHAR(2048) NULL,
    [RemindersEnabled] BIT NOT NULL DEFAULT 1,
    [ReminderSettings] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [TrackEffectiveness] BIT NOT NULL DEFAULT 1,
    [TrackSideEffects] BIT NOT NULL DEFAULT 1,
    [KnownSideEffects] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [DrugInteractions] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [PharmacyInfo] NVARCHAR(MAX) NULL,
    [InsuranceInfo] NVARCHAR(MAX) NULL, -- Encrypted
    [RefillReminderSettings] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [DaysSupply] INT NULL,
    [LastRefillDate] DATE NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Medications_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id]),
    CONSTRAINT [FK_Medications_Prescriber] FOREIGN KEY ([PrescriberId]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_Medications_PatientId] ON [Clinical].[Medications] ([PatientId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Medications_StartEndDate] ON [Clinical].[Medications] ([StartDate], [EndDate]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Medications_NDC] ON [Clinical].[Medications] ([NDCNumber]) WHERE [IsDeleted] = 0 AND [NDCNumber] IS NOT NULL;
GO

-- Medication adherence tracking
CREATE TABLE [Clinical].[MedicationAdherence] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [MedicationId] UNIQUEIDENTIFIER NOT NULL,
    [ScheduledAt] DATETIMEOFFSET NOT NULL,
    [TakenAt] DATETIMEOFFSET NULL,
    [WasTaken] BIT NOT NULL DEFAULT 0,
    [ActualDosage] NVARCHAR(100) NULL,
    [ReasonNotTaken] NVARCHAR(300) NULL,
    [Notes] NVARCHAR(1000) NULL,
    [RecordedBy] UNIQUEIDENTIFIER NOT NULL,
    [RecordingMethod] NVARCHAR(50) NOT NULL DEFAULT 'manual',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_MedicationAdherence_Medications] FOREIGN KEY ([MedicationId]) 
        REFERENCES [Clinical].[Medications] ([Id]),
    CONSTRAINT [FK_MedicationAdherence_RecordedBy] FOREIGN KEY ([RecordedBy]) 
        REFERENCES [Identity].[Users] ([Id])
);

CREATE INDEX [IX_MedicationAdherence_MedicationId] ON [Clinical].[MedicationAdherence] ([MedicationId], [ScheduledAt]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_MedicationAdherence_ScheduledAt] ON [Clinical].[MedicationAdherence] ([ScheduledAt]) WHERE [IsDeleted] = 0;
GO

-- Behaviors table
CREATE TABLE [Clinical].[Behaviors] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [PatientId] UNIQUEIDENTIFIER NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [Description] NVARCHAR(1000) NULL,
    [Category] NVARCHAR(100) NOT NULL,
    [Subcategory] NVARCHAR(100) NULL,
    [IsPositiveBehavior] BIT NOT NULL DEFAULT 0,
    [IntensityScaleType] INT NOT NULL DEFAULT 1, -- SeverityScaleType enum
    [CustomIntensityScale] NVARCHAR(MAX) NULL,
    [TrackDuration] BIT NOT NULL DEFAULT 1,
    [TrackFrequency] BIT NOT NULL DEFAULT 1,
    [TrackAntecedents] BIT NOT NULL DEFAULT 1,
    [TrackConsequences] BIT NOT NULL DEFAULT 1,
    [TrackEnvironmentalFactors] BIT NOT NULL DEFAULT 1,
    [AllowVideos] BIT NOT NULL DEFAULT 0,
    [AllowPhotos] BIT NOT NULL DEFAULT 1,
    [CommonAntecedents] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [CommonConsequences] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [BehaviorGoals] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [InterventionStrategies] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [CustomFields] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    [Color] NVARCHAR(7) NULL,
    [Icon] NVARCHAR(100) NULL,
    [IsActive] BIT NOT NULL DEFAULT 1,
    [BehaviorPlanId] UNIQUEIDENTIFIER NULL,
    [QuickEntryTemplates] NVARCHAR(MAX) NOT NULL DEFAULT '[]',
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_Behaviors_Patients] FOREIGN KEY ([PatientId]) 
        REFERENCES [Care].[Patients] ([Id])
);

CREATE INDEX [IX_Behaviors_PatientId] ON [Clinical].[Behaviors] ([PatientId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Behaviors_Category] ON [Clinical].[Behaviors] ([Category]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_Behaviors_IsActive] ON [Clinical].[Behaviors] ([PatientId], [IsActive]) WHERE [IsDeleted] = 0;
GO

-- ABC behavior entries
CREATE TABLE [Clinical].[ABCEntries] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    [TenantId] NVARCHAR(128) NOT NULL,
    [BehaviorId] UNIQUEIDENTIFIER NOT NULL,
    [TrackingEntryId] UNIQUEIDENTIFIER NOT NULL,
    [Antecedents] NVARCHAR(1000) NULL,
    [AntecedentData] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [BehaviorDescription] NVARCHAR(1000) NOT NULL,
    [Intensity] INT NULL,
    [Duration] TIME NULL,
    [Frequency] INT NOT NULL DEFAULT 1,
    [Consequences] NVARCHAR(1000) NULL,
    [ConsequenceData] NVARCHAR(MAX) NOT NULL DEFAULT '{}',
    [EnvironmentalFactors] NVARCHAR(1000) NULL,
    [PeoplePresent] NVARCHAR(500) NULL,
    [Activity] NVARCHAR(300) NULL,
    [Setting] NVARCHAR(300) NULL,
    [BehaviorFunction] NVARCHAR(200) NULL,
    [InterventionsUsed] NVARCHAR(1000) NULL,
    [InterventionEffectiveness] INT NULL,
    [FollowUpActions] NVARCHAR(1000) NULL,
    -- Audit fields
    [CreatedBy] NVARCHAR(128) NOT NULL,
    [CreatedAt] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    [LastModifiedBy] NVARCHAR(128) NULL,
    [LastModifiedAt] DATETIMEOFFSET NULL,
    [IsDeleted] BIT NOT NULL DEFAULT 0,
    [DeletedBy] NVARCHAR(128) NULL,
    [DeletedAt] DATETIMEOFFSET NULL,
    [RowVersion] ROWVERSION NOT NULL,
    
    CONSTRAINT [FK_ABCEntries_Behaviors] FOREIGN KEY ([BehaviorId]) 
        REFERENCES [Clinical].[Behaviors] ([Id]),
    CONSTRAINT [FK_ABCEntries_TrackingEntries] FOREIGN KEY ([TrackingEntryId]) 
        REFERENCES [Clinical].[TrackingEntries] ([Id])
);

CREATE INDEX [IX_ABCEntries_BehaviorId] ON [Clinical].[ABCEntries] ([BehaviorId]) WHERE [IsDeleted] = 0;
CREATE INDEX [IX_ABCEntries_TrackingEntryId] ON [Clinical].[ABCEntries] ([TrackingEntryId]) WHERE [IsDeleted] = 0;
GO

PRINT 'Clinical schema tables created successfully';
GO