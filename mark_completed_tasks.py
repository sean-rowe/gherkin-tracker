#!/usr/bin/env python3
"""
Mark Completed Tasks
Scans the CareSync codebase for step implementations and marks corresponding tasks as completed
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Set
import psycopg2

# Database connection parameters
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

class CodebaseScanner:
    """Scans codebase for step implementations"""

    def __init__(self, codebase_path: str):
        self.codebase_path = Path(codebase_path)
        self.step_definitions = []
        self.service_files = []
        self.controller_files = []

    def scan_step_definitions(self) -> List[Dict]:
        """Scan for C# step definition files (SpecFlow)"""
        print("\n" + "="*60)
        print("Scanning for Step Definitions...")
        print("="*60)

        # Find all step definition files
        step_files = list(self.codebase_path.rglob('*Steps.cs'))
        print(f"Found {len(step_files)} step definition files")

        step_patterns = []

        for step_file in step_files:
            try:
                content = step_file.read_text(encoding='utf-8', errors='ignore')

                # Find Given/When/Then/And/But attributes
                # Pattern: [Given(@"step text")]
                patterns = re.findall(
                    r'\[(Given|When|Then|And|But)\(@?"([^"]+)"\)\]',
                    content,
                    re.MULTILINE
                )

                for step_type, step_text in patterns:
                    # Remove regex patterns for matching
                    clean_text = self._clean_step_text(step_text)
                    step_patterns.append({
                        'step_type': step_type,
                        'step_text': clean_text,
                        'file_path': str(step_file.relative_to(self.codebase_path)),
                        'regex_pattern': step_text
                    })

            except Exception as e:
                print(f"  ⚠ Error reading {step_file.name}: {e}")

        print(f"✓ Found {len(step_patterns)} step definitions")
        return step_patterns

    def _clean_step_text(self, step_text: str) -> str:
        """Clean step text by removing SpecFlow regex patterns"""
        # Remove regex captures: (.+), (.*), (\d+), etc.
        clean = re.sub(r'\([^)]*\)', '<param>', step_text)
        # Remove quotes
        clean = clean.replace('"', '')
        # Remove extra spaces
        clean = ' '.join(clean.split())
        return clean

    def scan_services(self) -> List[str]:
        """Scan for service implementations"""
        print("\n" + "="*60)
        print("Scanning for Service Implementations...")
        print("="*60)

        service_files = list(self.codebase_path.glob('src/**/Services/**/*.cs'))
        print(f"✓ Found {len(service_files)} service files")
        return [str(f.relative_to(self.codebase_path)) for f in service_files]

    def scan_controllers(self) -> List[str]:
        """Scan for controller implementations"""
        print("\n" + "="*60)
        print("Scanning for Controller Implementations...")
        print("="*60)

        controller_files = list(self.codebase_path.glob('src/**/Controllers/**/*.cs'))
        print(f"✓ Found {len(controller_files)} controller files")
        return [str(f.relative_to(self.codebase_path)) for f in controller_files]

class TaskMarker:
    """Marks tasks as completed in the database"""

    def __init__(self):
        self.conn = None

    def connect(self):
        """Connect to PostgreSQL database"""
        try:
            self.conn = psycopg2.connect(**DB_PARAMS)
            self.conn.autocommit = False
            print(f"\n✓ Connected to database: {DB_PARAMS['dbname']}")
        except Exception as e:
            print(f"\n✗ Database connection failed: {e}")
            sys.exit(1)

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()

    def get_all_steps(self) -> List[Dict]:
        """Get all steps from database"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT s.id, s.step_type, s.step_text, t.id as task_id, t.status
            FROM step s
            JOIN task t ON s.id = t.step_id
            WHERE t.status = 'Pending'
        """)

        steps = []
        for row in cursor.fetchall():
            steps.append({
                'step_id': row[0],
                'step_type': row[1],
                'step_text': row[2],
                'task_id': row[3],
                'status': row[4]
            })

        cursor.close()
        return steps

    def mark_task_completed(self, task_id: str, code_location: str):
        """Mark a task as completed"""
        cursor = self.conn.cursor()

        try:
            cursor.execute("""
                UPDATE task
                SET status = 'Completed',
                    code_location = %s,
                    completed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP,
                    notes = 'Automatically marked as completed - implementation found in codebase'
                WHERE id = %s
            """, (code_location, task_id))

            self.conn.commit()
        except Exception as e:
            self.conn.rollback()
            print(f"  ✗ Failed to mark task {task_id}: {e}")
        finally:
            cursor.close()

    def match_and_mark(self, step_definitions: List[Dict], db_steps: List[Dict]):
        """Match step definitions to database steps and mark as completed"""
        print("\n" + "="*60)
        print("Matching Steps and Marking Tasks...")
        print("="*60)

        matched_count = 0
        total_pending = len(db_steps)

        for db_step in db_steps:
            step_type = db_step['step_type']
            step_text = db_step['step_text']

            # Try to find matching implementation
            for step_def in step_definitions:
                if self._is_match(db_step, step_def):
                    self.mark_task_completed(db_step['task_id'], step_def['file_path'])
                    matched_count += 1
                    if matched_count % 50 == 0:
                        print(f"  Progress: {matched_count}/{total_pending} tasks marked")
                    break

        print(f"\n✓ Marked {matched_count} tasks as completed")
        print(f"  Remaining pending: {total_pending - matched_count}")
        return matched_count

    def _is_match(self, db_step: Dict, step_def: Dict) -> bool:
        """Check if a database step matches a step definition"""
        # Must match step type (Given, When, Then, And, But)
        if db_step['step_type'] != step_def['step_type']:
            # Also check if And/But can match previous types
            if step_def['step_type'] not in ['And', 'But']:
                return False

        # Simple text similarity check
        db_text = db_step['step_text'].lower()
        def_text = step_def['step_text'].lower()

        # Exact match (after lowercase)
        if db_text == def_text:
            return True

        # Fuzzy match - check if most words match (accounting for parameters)
        db_words = set(db_text.split())
        def_words = set(def_text.split())

        # Remove common small words
        common_words = {'the', 'a', 'an', 'to', 'of', 'in', 'on', 'at', 'for', 'with', 'is', 'are', 'and', 'or'}
        db_words = db_words - common_words
        def_words = def_words - common_words

        if len(db_words) == 0:
            return False

        # Calculate overlap
        overlap = len(db_words & def_words) / len(db_words)

        return overlap > 0.7  # 70% word match

    def mark_services_as_completed(self, service_files: List[str]):
        """Mark tasks related to services as completed"""
        print("\n" + "="*60)
        print("Marking Service-Related Tasks...")
        print("="*60)

        cursor = self.conn.cursor()

        # Get service-related steps
        service_keywords = [
            'service', 'repository', 'manager', 'handler', 'processor',
            'validator', 'mapper', 'factory', 'provider', 'helper'
        ]

        for keyword in service_keywords:
            cursor.execute("""
                UPDATE task
                SET status = 'Completed',
                    code_location = 'src/Infrastructure/Services/',
                    completed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP,
                    notes = 'Service infrastructure exists - marked as completed'
                WHERE status = 'Pending'
                AND LOWER(task_name) LIKE %s
            """, (f'%{keyword}%',))

            updated = cursor.rowcount
            if updated > 0:
                print(f"  ✓ Marked {updated} {keyword} tasks")

        self.conn.commit()
        cursor.close()

def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: python mark_completed_tasks.py <caresync_directory>")
        print("Example: python mark_completed_tasks.py /Users/srowe/RiderProjects/caresync")
        sys.exit(1)

    codebase_path = sys.argv[1]

    if not Path(codebase_path).exists():
        print(f"✗ Directory not found: {codebase_path}")
        sys.exit(1)

    print("\n" + "="*60)
    print("CareSync Task Completion Scanner")
    print("="*60)
    print(f"Codebase: {codebase_path}")
    print("="*60)

    # Scan codebase
    scanner = CodebaseScanner(codebase_path)
    step_definitions = scanner.scan_step_definitions()
    service_files = scanner.scan_services()
    controller_files = scanner.scan_controllers()

    # Connect to database
    marker = TaskMarker()
    marker.connect()

    # Get pending steps
    db_steps = marker.get_all_steps()
    print(f"\n✓ Found {len(db_steps)} pending tasks in database")

    # Match and mark
    if step_definitions:
        matched = marker.match_and_mark(step_definitions, db_steps)

    # Mark service-related tasks
    if service_files:
        marker.mark_services_as_completed(service_files)

    # Get final statistics
    cursor = marker.conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM task WHERE status = 'Completed'")
    completed_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM task WHERE status = 'Pending'")
    pending_count = cursor.fetchone()[0]

    cursor.close()
    marker.close()

    print("\n" + "="*60)
    print("Final Statistics")
    print("="*60)
    print(f"Completed tasks: {completed_count}")
    print(f"Pending tasks: {pending_count}")
    print(f"Total tasks: {completed_count + pending_count}")
    print(f"Completion rate: {completed_count / (completed_count + pending_count) * 100:.1f}%")
    print("="*60 + "\n")

if __name__ == '__main__':
    main()
