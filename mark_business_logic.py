#!/usr/bin/env python3
"""
Mark Business Logic as Implemented
Maps service implementations to features and marks business_logic_implemented
"""

import os
import sys
import psycopg2
from pathlib import Path
from typing import Dict, List, Set

DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

# Map service files to feature keywords
SERVICE_TO_FEATURE_MAP = {
    'MedicationService': ['medication', 'drug', 'prescription', 'dosage'],
    'SymptomService': ['symptom', 'tracking'],
    'BehaviorService': ['behavior', 'behaviour', 'abc'],
    'NutritionService': ['nutrition', 'food', 'meal', 'diet'],
    'BowelMovementService': ['bowel', 'bristol', 'stool'],
    'CareTeamService': ['careteam', 'team', 'invitation'],
    'PatientService': ['patient', 'demographics'],
    'AuditService': ['audit', 'logging', 'trail'],
    'OfflineDataSyncService': ['offline', 'sync', 'synchronization'],
    'ConflictResolutionService': ['conflict', 'resolution'],
    'ConflictNotificationService': ['conflict', 'notification'],
    'EmailService': ['email', 'smtp', 'queue'],
    'AuthenticationService': ['authentication', 'auth', 'login', 'oauth', 'jwt'],
    'AuthorizationService': ['authorization', 'permission', 'role', 'rbac'],
    'EncryptionService': ['encryption', 'crypto', 'security'],
    'TenantService': ['tenant', 'multitenancy', 'multitenant'],
    'TrackingService': ['tracking', 'entry'],
    'CalendarService': ['calendar', 'event', 'schedule'],
    'EnvironmentalDataService': ['environmental', 'weather', 'air', 'pollen'],
    'EducationalService': ['educational', 'iep', 'school'],
    'WebSocketNotificationService': ['websocket', 'realtime', 'notification'],
    'SearchService': ['search', 'query', 'filter'],
    'SettingsService': ['settings', 'preferences', 'configuration'],
    'MedicationReminderService': ['reminder', 'medication', 'alert'],
    'NotificationService': ['notification', 'alert', 'push'],
    'ReportService': ['report', 'export', 'pdf'],
    'TranslationService': ['translation', 'language', 'i18n'],
    'WearableService': ['wearable', 'device', 'healthkit', 'fitbit'],
    'AnalyticsService': ['analytics', 'pattern', 'insight', 'correlation'],
    'FileStorageService': ['file', 'storage', 'attachment', 'upload'],
    'WebhookService': ['webhook', 'subscription', 'callback'],
}

def connect_db():
    """Connect to database"""
    conn = psycopg2.connect(**DB_PARAMS)
    print(f"✓ Connected to database: {DB_PARAMS['dbname']}")
    return conn

def get_existing_services(codebase_path: Path) -> Set[str]:
    """Scan for existing service files"""
    services = set()
    service_files = list(codebase_path.glob('src/**/Services/**/*Service.cs'))

    for service_file in service_files:
        service_name = service_file.stem
        if not service_name.startswith('I'):  # Skip interfaces
            services.add(service_name)

    print(f"✓ Found {len(services)} service implementations")
    return services

def mark_business_logic_for_service(conn, project_name: str, service_name: str, keywords: List[str]):
    """Mark tasks as having business logic if service exists"""
    cursor = conn.cursor()

    # Build keyword pattern
    keyword_pattern = '|'.join(keywords)

    # Update tasks for features matching keywords
    cursor.execute("""
        UPDATE task t
        SET business_logic_implemented = true,
            service_location = %s,
            updated_at = CURRENT_TIMESTAMP,
            notes = COALESCE(notes || E'\n', '') || 'Business logic exists in ' || %s
        FROM step s
        JOIN scenario_step ss ON s.id = ss.step_id
        JOIN scenario sc ON ss.scenario_id = sc.id
        JOIN feature f ON sc.feature_id = f.id
        JOIN project p ON f.project_id = p.id
        WHERE t.step_id = s.id
        AND p.name = %s
        AND t.business_logic_implemented = false
        AND (
            LOWER(f.feature_name) ~* %s
            OR LOWER(sc.scenario_name) ~* %s
            OR LOWER(s.step_text) ~* %s
        )
    """, (
        f'src/Infrastructure/Services/{service_name}.cs',
        service_name,
        project_name,
        keyword_pattern,
        keyword_pattern,
        keyword_pattern
    ))

    updated = cursor.rowcount
    conn.commit()
    cursor.close()

    return updated

def main():
    if len(sys.argv) < 3:
        print("Usage: python mark_business_logic.py <project_name> <codebase_directory>")
        print("Example: python mark_business_logic.py CareSync /Users/srowe/RiderProjects/caresync")
        sys.exit(1)

    project_name = sys.argv[1]
    codebase_path = Path(sys.argv[2])

    if not codebase_path.exists():
        print(f"✗ Directory not found: {codebase_path}")
        sys.exit(1)

    print("\n" + "="*80)
    print(f"Marking Business Logic for {project_name}")
    print("="*80)
    print(f"Codebase: {codebase_path}")
    print("="*80 + "\n")

    # Get existing services
    existing_services = get_existing_services(codebase_path)

    # Connect to database
    conn = connect_db()

    total_marked = 0

    print("\nMapping services to features...")
    print("-" * 80)

    for service_name, keywords in SERVICE_TO_FEATURE_MAP.items():
        if service_name in existing_services:
            marked = mark_business_logic_for_service(conn, project_name, service_name, keywords)
            if marked > 0:
                print(f"✓ {service_name:30} -> {marked:4} tasks marked")
                total_marked += marked

    # Get final statistics
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN business_logic_implemented THEN 1 ELSE 0 END) as logic_done,
            SUM(CASE WHEN bdd_implemented THEN 1 ELSE 0 END) as bdd_done,
            SUM(CASE WHEN bdd_implemented AND business_logic_implemented THEN 1 ELSE 0 END) as both_done
        FROM task t
        JOIN step s ON t.step_id = s.id
        JOIN scenario_step ss ON s.id = ss.step_id
        JOIN scenario sc ON ss.scenario_id = sc.id
        JOIN feature f ON sc.feature_id = f.id
        JOIN project p ON f.project_id = p.id
        WHERE p.name = %s
    """, (project_name,))

    row = cursor.fetchone()
    total, logic_done, bdd_done, both_done = row

    cursor.close()
    conn.close()

    print("\n" + "="*80)
    print(f"Final Statistics for {project_name}")
    print("="*80)
    print(f"Total tasks:               {total}")
    print(f"Business logic done:       {logic_done} ({logic_done/total*100:.1f}%)")
    print(f"BDD steps done:            {bdd_done} ({bdd_done/total*100:.1f}%)")
    print(f"Fully implemented (both):  {both_done} ({both_done/total*100:.1f}%)")
    print(f"\nTasks marked this run:     {total_marked}")
    print("="*80 + "\n")

if __name__ == '__main__':
    main()
