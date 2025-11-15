Feature: Database Schema Design
  As a system architect
  I want a robust database schema with multi-tenancy, security, and audit capabilities
  So that the CareSync application can handle healthcare data securely and efficiently

  Background:
    Given a clean MSSQL database environment
    And I have administrative privileges
    And HIPAA compliance requirements are enabled

  @database @schema @security
  Scenario: Create database with HIPAA-compliant configuration
    Given I need to create the CareSync database
    When I execute the database creation script
    Then the database should be created with name "CareSync"
    And the database should have RECOVERY FULL mode enabled
    And the database should have READ_COMMITTED_SNAPSHOT enabled
    And the database should have ALLOW_SNAPSHOT_ISOLATION enabled
    And the database should have PAGE_VERIFY CHECKSUM enabled
    And the database should have Query Store enabled for performance monitoring
    And Change Data Capture should be enabled for auditing

  @database @schema @organization
  Scenario: Create logical schemas for data organization
    Given the CareSync database exists
    When I create the database schemas
    Then the following schemas should exist:
      | Schema        | Purpose                            |
      | Identity      | User management and authentication |
      | Care          | Patient care and tracking          |
      | Clinical      | Clinical data tracking             |
      | Communication | Messages and notifications         |
      | Analytics     | Reporting and analytics            |
      | Audit         | Audit trails and compliance        |
      | Reference     | Reference data and lookups         |
      | Security      | Security functions and policies    |

  @database @security @roles
  Scenario: Create application security roles
    Given the CareSync database exists with schemas
    When I create the application security roles
    Then the following roles should exist:
      | Role                  | Purpose                    |
      | CareSync_Application  | Main application access    |
      | CareSync_ReadOnly     | Read-only access           |
      | CareSync_Analytics    | Analytics service access   |
      | CareSync_Admin        | Administrative access      |
    And the following users should be created without login:
      | User                     | Assigned Role        |
      | CareSync_API             | CareSync_Application |
      | CareSync_BackgroundJobs  | CareSync_Application |
      | CareSync_Analytics_Service | CareSync_Analytics |
      | CareSync_Audit_Service   | CareSync_ReadOnly    |

  @database @multitenant @security
  Scenario: Create Users table with multi-tenancy support
    Given the database schemas exist
    When I create the Identity.Users table
    Then the table should have the following structure:
      | Column                    | Type            | Constraints                    |
      | Id                        | UNIQUEIDENTIFIER| PRIMARY KEY, DEFAULT NEWSEQUENTIALID() |
      | TenantId                  | NVARCHAR(128)   | NOT NULL                       |
      | Email                     | NVARCHAR(256)   | NOT NULL                       |
      | NormalizedEmail           | NVARCHAR(256)   | NOT NULL                       |
      | FirstName                 | NVARCHAR(100)   | NOT NULL                       |
      | LastName                  | NVARCHAR(100)   | NOT NULL                       |
      | PhoneNumber               | NVARCHAR(20)    | NULL                          |
      | EmailVerified             | BIT             | NOT NULL DEFAULT 0            |
      | TwoFactorEnabled          | BIT             | NOT NULL DEFAULT 0            |
      | IsActive                  | BIT             | NOT NULL DEFAULT 1            |
      | CreatedAt                 | DATETIMEOFFSET  | NOT NULL DEFAULT SYSDATETIMEOFFSET() |
      | IsDeleted                 | BIT             | NOT NULL DEFAULT 0            |
      | RowVersion                | ROWVERSION      | NOT NULL                       |
    And the table should have a unique index on (TenantId, NormalizedEmail) where IsDeleted = 0
    And the table should support soft delete functionality

  @database @multitenant @care
  Scenario: Create Patients table with comprehensive patient data support
    Given the Identity.Users table exists
    When I create the Care.Patients table
    Then the table should have the following structure:
      | Column                   | Type            | Constraints                    |
      | Id                       | UNIQUEIDENTIFIER| PRIMARY KEY, DEFAULT NEWSEQUENTIALID() |
      | TenantId                 | NVARCHAR(128)   | NOT NULL                       |
      | FirstName                | NVARCHAR(100)   | NOT NULL                       |
      | LastName                 | NVARCHAR(100)   | NOT NULL                       |
      | DateOfBirth              | DATE            | NOT NULL                       |
      | Gender                   | NVARCHAR(20)    | NOT NULL                       |
      | PrimaryDiagnosis         | NVARCHAR(500)   | NULL                          |
      | SecondaryDiagnoses       | NVARCHAR(MAX)   | NOT NULL DEFAULT '[]'         |
      | Allergies                | NVARCHAR(MAX)   | NOT NULL DEFAULT '[]'         |
      | InsuranceInformation     | NVARCHAR(MAX)   | NULL (Encrypted)              |
      | PrimaryUserId            | UNIQUEIDENTIFIER| NOT NULL                       |
      | PrivacySettings          | NVARCHAR(MAX)   | NOT NULL DEFAULT '{}'         |
      | TrackingConfigurations   | NVARCHAR(MAX)   | NOT NULL DEFAULT '{}'         |
      | CreatedAt                | DATETIMEOFFSET  | NOT NULL DEFAULT SYSDATETIMEOFFSET() |
      | IsDeleted                | BIT             | NOT NULL DEFAULT 0            |
      | RowVersion               | ROWVERSION      | NOT NULL                       |
    And the table should have a foreign key to Identity.Users(Id) for PrimaryUserId
    And the table should have proper indexes for performance

  @database @multitenant @collaboration
  Scenario: Create CareTeams table for multi-user collaboration
    Given the Care.Patients table exists
    When I create the Care.CareTeams table
    Then the table should support the PRIMARY differentiator of concurrent multi-user access
    And the table should have the following structure:
      | Column                     | Type            | Constraints                    |
      | Id                         | UNIQUEIDENTIFIER| PRIMARY KEY, DEFAULT NEWSEQUENTIALID() |
      | TenantId                   | NVARCHAR(128)   | NOT NULL                       |
      | PatientId                  | UNIQUEIDENTIFIER| NOT NULL                       |
      | Name                       | NVARCHAR(200)   | NOT NULL                       |
      | Description                | NVARCHAR(1000)  | NULL                          |
      | MaxMembers                 | INT             | NOT NULL DEFAULT 50           |
      | RequireApproval            | BIT             | NOT NULL DEFAULT 1            |
      | CommunicationPreferences   | NVARCHAR(MAX)   | NOT NULL DEFAULT '{}'         |
      | CreatedAt                  | DATETIMEOFFSET  | NOT NULL DEFAULT SYSDATETIMEOFFSET() |
      | IsDeleted                  | BIT             | NOT NULL DEFAULT 0            |
      | RowVersion                 | ROWVERSION      | NOT NULL                       |
    And the table should have a foreign key to Care.Patients(Id) for PatientId
    And the table should enforce maximum 50 members per care team

  @database @clinical @partitioning
  Scenario: Create TrackingEntries table with monthly partitioning for performance
    Given the Care.Patients table exists
    When I create the Clinical.TrackingEntries table
    Then the table should be partitioned by month on OccurredAt column
    And the table should have the following structure:
      | Column               | Type            | Constraints                    |
      | Id                   | UNIQUEIDENTIFIER| PRIMARY KEY, DEFAULT NEWSEQUENTIALID() |
      | TenantId             | NVARCHAR(128)   | NOT NULL                       |
      | PatientId            | UNIQUEIDENTIFIER| NOT NULL                       |
      | EnteredBy            | UNIQUEIDENTIFIER| NOT NULL                       |
      | TrackingType         | INT             | NOT NULL (enum)               |
      | OccurredAt           | DATETIMEOFFSET  | NOT NULL                       |
      | TimeZone             | NVARCHAR(50)    | NOT NULL DEFAULT 'UTC'        |
      | SeverityNumeric      | INT             | NULL                          |
      | SeverityDescriptive  | INT             | NULL (enum)                   |
      | SeverityVisual       | INT             | NULL (enum)                   |
      | Location             | NVARCHAR(300)   | NULL                          |
      | Notes                | NVARCHAR(MAX)   | NULL                          |
      | VoiceTranscription   | NVARCHAR(MAX)   | NULL                          |
      | CustomFields         | NVARCHAR(MAX)   | NOT NULL DEFAULT '{}'         |
      | EnvironmentalData    | NVARCHAR(MAX)   | NULL                          |
      | IsEdited             | BIT             | NOT NULL DEFAULT 0            |
      | CreatedAt            | DATETIMEOFFSET  | NOT NULL DEFAULT SYSDATETIMEOFFSET() |
      | IsDeleted            | BIT             | NOT NULL DEFAULT 0            |
      | RowVersion           | ROWVERSION      | NOT NULL                       |
    And the partition function should cover 3 years of monthly partitions
    And the table should have a clustered index on (OccurredAt, Id) using the partition scheme

  @database @audit @security
  Scenario: Create comprehensive audit logging tables
    Given the database schemas exist
    When I create the audit logging tables
    Then the Audit.AuditLog table should capture all data changes
    And the table should have the following structure:
      | Column            | Type            | Constraints                    |
      | Id                | UNIQUEIDENTIFIER| PRIMARY KEY, DEFAULT NEWSEQUENTIALID() |
      | TenantId          | NVARCHAR(128)   | NOT NULL                       |
      | EntityType        | NVARCHAR(100)   | NOT NULL                       |
      | EntityId          | UNIQUEIDENTIFIER| NOT NULL                       |
      | UserId            | UNIQUEIDENTIFIER| NULL                          |
      | UserName          | NVARCHAR(256)   | NULL                          |
      | Action            | NVARCHAR(50)    | NOT NULL                       |
      | TableName         | NVARCHAR(128)   | NOT NULL                       |
      | OldValues         | NVARCHAR(MAX)   | NULL (JSON)                   |
      | NewValues         | NVARCHAR(MAX)   | NULL (JSON)                   |
      | IPAddress         | NVARCHAR(45)    | NULL                          |
      | SessionId         | NVARCHAR(256)   | NULL                          |
      | Timestamp         | DATETIMEOFFSET  | NOT NULL DEFAULT SYSDATETIMEOFFSET() |
    And the table should be partitioned by month on Timestamp column
    And the Audit.SecurityEvents table should capture HIPAA security events
    And the Audit.DataAccessLog table should track PHI access for compliance

  @database @security @rls
  Scenario: Implement row-level security for multi-tenant isolation
    Given all tables are created with TenantId columns
    When I implement row-level security
    Then a security function Security.fn_TenantAccessPredicate should be created
    And the function should check SESSION_CONTEXT('TenantId') for tenant isolation
    And the function should allow access for CareSync_Admin role members
    And a security policy Security.TenantSecurityPolicy should be created
    And the policy should apply filter predicates to all tenant-enabled tables:
      | Table                              |
      | Identity.Users                     |
      | Care.Patients                      |
      | Care.CareTeams                     |
      | Clinical.TrackingEntries          |
      | Clinical.Symptoms                  |
      | Clinical.Medications              |
      | Clinical.Behaviors                |
      | Communication.Messages            |
      | Audit.AuditLog                    |
    And the security policy should be enabled with STATE = ON

  @database @audit @triggers
  Scenario: Create audit triggers for automatic change tracking
    Given the audit tables exist
    And row-level security is implemented
    When I create audit triggers
    Then an audit trigger should be created for the Identity.Users table
    And the trigger should capture INSERT, UPDATE, and DELETE operations
    And the trigger should use SESSION_CONTEXT for user attribution
    And the trigger should store JSON representations of old and new values
    And the trigger should populate all required audit fields:
      | Field         | Source                              |
      | TenantId      | From affected record or session    |
      | UserId        | SESSION_CONTEXT('UserId')          |
      | UserName      | SESSION_CONTEXT('UserName')        |
      | IPAddress     | SESSION_CONTEXT('IPAddress')       |
      | SessionId     | SESSION_CONTEXT('SessionId')       |
      | ApplicationName | APP_NAME()                        |
      | HostName      | HOST_NAME()                        |

  @database @retention @compliance
  Scenario: Implement data retention policies for HIPAA compliance
    Given the audit tables exist
    When I create data retention policies
    Then a DataRetentionPolicies configuration table should be created
    And the table should define retention periods for different data types:
      | Table                            | Retention Period |
      | Audit.AuditLog                   | 84 months        |
      | Audit.SecurityEvents             | 84 months        |
      | Audit.DataAccessLog              | 84 months        |
      | Clinical.TrackingEntries         | 24 months        |
      | Communication.Messages           | 12 months        |
      | Communication.Notifications      | 6 months         |
    And a stored procedure sp_ProcessDataRetention should be created
    And the procedure should support dry-run mode for testing
    And the procedure should archive data before deletion
    And the procedure should update last processed timestamps

  @database @performance @indexes
  Scenario: Create optimized indexes for multi-user performance
    Given all tables are created
    When I create performance indexes
    Then each table should have proper indexing strategy for concurrent access:
      | Table                    | Index Strategy                                    |
      | Identity.Users           | TenantId, Email, LastLogin                       |
      | Care.Patients            | TenantId, PrimaryUserId, DateOfBirth            |
      | Care.CareTeams           | PatientId, TenantId                             |
      | Clinical.TrackingEntries | PatientId+OccurredAt, EnteredBy, TrackingType   |
      | Clinical.Symptoms        | PatientId, Category, IsActive                    |
      | Clinical.Medications     | PatientId, StartDate+EndDate, NDCNumber         |
      | Communication.Messages   | CareTeamId+CreatedAt, SenderId, ThreadId        |
    And all indexes should include WHERE IsDeleted = 0 filter for soft deletes
    And clustered indexes should be designed for partition elimination

  @database @communication @messaging
  Scenario: Create communication tables for care team collaboration
    Given the Care.CareTeams table exists
    When I create the communication tables
    Then the Communication.Messages table should support real-time messaging
    And the table should have fields for:
      | Field              | Purpose                                  |
      | CareTeamId         | Link to care team                       |
      | SenderId           | Message sender                          |
      | Content            | Message content                         |
      | MentionedUsers     | @mentions JSON array                    |
      | ReadReceipts       | Read status JSON object                 |
      | DeliveryStatus     | Delivery confirmation JSON              |
      | ReplyToMessageId   | Thread support                          |
      | IsUrgent           | Priority flagging                       |
      | Attachments        | File attachment references              |
    And the Communication.Attachments table should support file sharing
    And the Communication.Notifications table should support push notifications
    And all tables should be partitioned by month for performance

  @database @error-handling @validation
  Scenario: Database creation handles errors gracefully
    Given I have database creation scripts
    When an error occurs during table creation
    Then the error should be logged with specific table information
    And the script should continue with remaining tables
    And foreign key constraints should be added after all tables exist
    And validation should confirm all required objects were created

  @database @backup @disaster-recovery
  Scenario: Database supports backup and disaster recovery
    Given the CareSync database is created
    When I configure backup settings
    Then the database should be in FULL recovery mode
    And transaction log backups should be supported
    And point-in-time recovery should be enabled
    And the database should support AlwaysOn availability groups
    And data files should be configured for optimal growth

  @database @monitoring @performance
  Scenario: Database includes monitoring and performance features
    Given the CareSync database is created
    When I enable monitoring features
    Then Query Store should be enabled with appropriate settings
    And automatic statistics creation should be enabled
    And automatic statistics updates should be enabled
    And page verification should be set to CHECKSUM
    And the database should support query performance insights