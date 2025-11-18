#!/usr/bin/env python3
"""
UPTRMS Implementation Verification Script

Scans the UPTRMS codebase for existing SpecFlow step definitions and marks
corresponding tasks as completed in the gherkin_tracker database.

Strategy:
1. Parse all *Steps.cs files to extract [Given], [When], [Then] attributes
2. Match step definitions to database steps using regex/text matching
3. Mark tasks as completed for matched steps
4. Generate report showing completion status
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Set, Tuple
import psycopg2
from psycopg2.extras import execute_values

# Database connection
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

# UPTRMS paths
UPTRMS_ROOT = Path('/Users/srowe/RiderProjects/pediatric-therapy-resource')
STEP_DEFINITIONS_PATH = UPTRMS_ROOT / 'api/Tests/BDD/StepDefinitions'

class StepDefinitionParser:
    """Parses C# SpecFlow step definition files"""

    # Regex patterns for SpecFlow attributes
    GIVEN_PATTERN = re.compile(r'\[Given\(@"(.+?)"\)\]', re.IGNORECASE)
    WHEN_PATTERN = re.compile(r'\[When\(@"(.+?)"\)\]', re.IGNORECASE)
    THEN_PATTERN = re.compile(r'\[Then\(@"(.+?)"\)\]', re.IGNORECASE)

    def __init__(self, file_path: Path):
        self.file_path = file_path
        self.content = file_path.read_text(encoding='utf-8', errors='ignore')

    def extract_steps(self) -> List[Dict[str, str]]:
        """Extract all step definitions from the file"""
        steps = []

        # Find Given steps
        for match in self.GIVEN_PATTERN.finditer(self.content):
            steps.append({
                'step_type': 'Given',
                'pattern': match.group(1),
                'file': self.file_path.name
            })

        # Find When steps
        for match in self.WHEN_PATTERN.finditer(self.content):
            steps.append({
                'step_type': 'When',
                'pattern': match.group(1),
                'file': self.file_path.name
            })

        # Find Then steps
        for match in self.THEN_PATTERN.finditer(self.content):
            steps.append({
                'step_type': 'Then',
                'pattern': match.group(1),
                'file': self.file_path.name
            })

        return steps

class StepMatcher:
    """Matches SpecFlow step patterns to Gherkin step text"""

    @staticmethod
    def pattern_to_regex(specflow_pattern: str) -> str:
        """Convert SpecFlow pattern to Python regex"""
        # Replace SpecFlow placeholders with regex
        # (.+) -> any text
        # (\d+) -> digits
        # (.*) -> optional any text
        regex = specflow_pattern

        # Escape special regex characters except our placeholders
        regex = re.escape(regex)

        # Restore SpecFlow regex patterns
        regex = regex.replace(r'\(\.\+\)', '(.+)')
        regex = regex.replace(r'\(\\d\+\)', r'(\d+)')
        regex = regex.replace(r'\(\.\*\)', '(.*)')

        return f'^{regex}$'

    @staticmethod
    def matches(pattern: str, step_text: str) -> bool:
        """Check if a SpecFlow pattern matches a Gherkin step"""
        try:
            regex = StepMatcher.pattern_to_regex(pattern)
            return bool(re.match(regex, step_text, re.IGNORECASE))
        except:
            # If regex compilation fails, try exact match
            return pattern.lower() == step_text.lower()

class DatabaseUpdater:
    """Updates the gherkin_tracker database with completion status"""

    def __init__(self):
        self.conn = None
        self.project_id = None

    def connect(self):
        """Connect to PostgreSQL"""
        try:
            self.conn = psycopg2.connect(**DB_PARAMS)
            self.conn.autocommit = False
            print(f"✓ Connected to database: {DB_PARAMS['dbname']}")
        except Exception as e:
            print(f"✗ Database connection failed: {e}")
            sys.exit(1)

    def get_project_id(self, project_name: str) -> str:
        """Get project ID"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT id FROM project WHERE name = %s", (project_name,))
        result = cursor.fetchone()
        cursor.close()

        if not result:
            print(f"✗ Project '{project_name}' not found in database")
            sys.exit(1)

        return result[0]

    def get_all_steps(self) -> List[Dict]:
        """Get all steps for UPTRMS project"""
        cursor = self.conn.cursor()

        query = """
            SELECT DISTINCT
                st.id,
                st.step_type,
                st.step_text,
                t.id as task_id,
                t.status
            FROM step st
            JOIN task t ON st.id = t.step_id
            WHERE st.id IN (
                SELECT DISTINCT ss.step_id
                FROM scenario_step ss
                JOIN scenario s ON ss.scenario_id = s.id
                JOIN feature f ON s.feature_id = f.id
                JOIN project p ON f.project_id = p.id
                WHERE p.id = %s
            )
            ORDER BY st.step_type, st.step_text
        """

        cursor.execute(query, (self.project_id,))
        results = cursor.fetchall()
        cursor.close()

        steps = []
        for row in results:
            steps.append({
                'step_id': row[0],
                'step_type': row[1],
                'step_text': row[2],
                'task_id': row[3],
                'status': row[4]
            })

        return steps

    def mark_task_completed(self, task_id: str, implementation_file: str):
        """Mark a task as completed"""
        cursor = self.conn.cursor()

        cursor.execute("""
            UPDATE task
            SET status = 'Completed',
                bdd_step_file = %s,
                completed_at = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            AND status != 'Completed'
        """, (implementation_file, task_id))

        rows_updated = cursor.rowcount
        cursor.close()

        return rows_updated > 0

    def mark_task_pending(self, task_id: str):
        """Ensure task is marked as Pending if not implemented"""
        cursor = self.conn.cursor()

        cursor.execute("""
            UPDATE task
            SET status = 'Pending',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            AND status != 'Completed'
            AND status != 'Pending'
        """, (task_id,))

        cursor.close()

    def commit(self):
        """Commit changes"""
        self.conn.commit()

    def close(self):
        """Close connection"""
        if self.conn:
            self.conn.close()

def scan_step_definitions() -> List[Dict]:
    """Scan all SpecFlow step definition files"""
    print(f"\n{'='*80}")
    print("Scanning SpecFlow Step Definitions")
    print(f"{'='*80}")
    print(f"Directory: {STEP_DEFINITIONS_PATH}")

    step_files = list(STEP_DEFINITIONS_PATH.glob('*Steps.cs'))
    print(f"Found {len(step_files)} step definition files\n")

    all_implemented_steps = []

    for step_file in sorted(step_files):
        # Skip backup and disabled files
        if '.backup' in step_file.name or '.disabled' in step_file.name:
            print(f"  ⊘ Skipped: {step_file.name}")
            continue

        parser = StepDefinitionParser(step_file)
        steps = parser.extract_steps()

        if steps:
            print(f"  ✓ {step_file.name}: {len(steps)} steps")
            all_implemented_steps.extend(steps)
        else:
            print(f"  ⚠ {step_file.name}: no steps found")

    print(f"\nTotal implemented steps: {len(all_implemented_steps)}")
    return all_implemented_steps

def match_and_update(implemented_steps: List[Dict], db_updater: DatabaseUpdater):
    """Match implemented steps to database and update completion status"""
    print(f"\n{'='*80}")
    print("Matching Steps to Database")
    print(f"{'='*80}\n")

    # Get all database steps
    db_steps = db_updater.get_all_steps()
    print(f"Database steps to check: {len(db_steps)}")
    print(f"Implemented steps to match: {len(implemented_steps)}\n")

    # Build a lookup of implemented steps by type
    implemented_by_type = {}
    for impl_step in implemented_steps:
        step_type = impl_step['step_type']
        if step_type not in implemented_by_type:
            implemented_by_type[step_type] = []
        implemented_by_type[step_type].append(impl_step)

    # Match and update
    matched_count = 0
    updated_count = 0

    print("Matching steps...")
    for i, db_step in enumerate(db_steps):
        if (i + 1) % 100 == 0:
            print(f"  Processed {i + 1}/{len(db_steps)} steps...")

        step_type = db_step['step_type']
        step_text = db_step['step_text']

        # Get candidate implementations for this step type
        candidates = implemented_by_type.get(step_type, [])

        # Try to find a match
        matched = False
        for impl_step in candidates:
            if StepMatcher.matches(impl_step['pattern'], step_text):
                matched_count += 1

                # Mark as completed if not already
                if db_updater.mark_task_completed(db_step['task_id'], impl_step['file']):
                    updated_count += 1

                matched = True
                break

        if not matched:
            # Ensure it's marked as Pending
            db_updater.mark_task_pending(db_step['task_id'])

    print(f"\n✓ Matching complete")
    print(f"  Matched steps: {matched_count}/{len(db_steps)} ({matched_count/len(db_steps)*100:.1f}%)")
    print(f"  Newly marked as completed: {updated_count}")

    return matched_count, updated_count

def generate_report(db_updater: DatabaseUpdater):
    """Generate completion report"""
    print(f"\n{'='*80}")
    print("Implementation Status Report")
    print(f"{'='*80}\n")

    cursor = db_updater.conn.cursor()

    # Overall stats
    cursor.execute("""
        SELECT
            COUNT(*) FILTER (WHERE t.status = 'Completed') as completed,
            COUNT(*) FILTER (WHERE t.status = 'Pending') as pending,
            COUNT(*) FILTER (WHERE t.status = 'Failed') as failed,
            COUNT(*) as total
        FROM task t
        JOIN step st ON t.step_id = st.id
        WHERE st.id IN (
            SELECT DISTINCT ss.step_id
            FROM scenario_step ss
            JOIN scenario s ON ss.scenario_id = s.id
            JOIN feature f ON s.feature_id = f.id
            JOIN project p ON f.project_id = p.id
            WHERE p.id = %s
        )
    """, (db_updater.project_id,))

    completed, pending, failed, total = cursor.fetchone()

    print(f"UPTRMS Implementation Status:")
    print(f"├── Total Tasks:      {total:,}")
    print(f"├── Completed:        {completed:,} ({completed/total*100:.1f}%)")
    print(f"├── Pending:          {pending:,} ({pending/total*100:.1f}%)")
    print(f"└── Failed:           {failed:,} ({failed/total*100:.1f}%)")

    # Completion by step type
    print(f"\nCompletion by Step Type:")
    cursor.execute("""
        SELECT
            st.step_type,
            COUNT(*) FILTER (WHERE t.status = 'Completed') as completed,
            COUNT(*) as total
        FROM task t
        JOIN step st ON t.step_id = st.id
        WHERE st.id IN (
            SELECT DISTINCT ss.step_id
            FROM scenario_step ss
            JOIN scenario s ON ss.scenario_id = s.id
            JOIN feature f ON s.feature_id = f.id
            JOIN project p ON f.project_id = p.id
            WHERE p.id = %s
        )
        GROUP BY st.step_type
        ORDER BY st.step_type
    """, (db_updater.project_id,))

    for row in cursor.fetchall():
        step_type, type_completed, type_total = row
        print(f"  {step_type:6} {type_completed:,}/{type_total:,} ({type_completed/type_total*100:.1f}%)")

    # Most implemented features
    print(f"\nTop 10 Most Implemented Features:")
    cursor.execute("""
        SELECT
            f.feature_name,
            COUNT(*) FILTER (WHERE t.status = 'Completed') as completed,
            COUNT(*) as total
        FROM feature f
        JOIN scenario s ON f.id = s.feature_id
        JOIN scenario_step ss ON s.id = ss.scenario_id
        JOIN step st ON ss.step_id = st.id
        JOIN task t ON st.id = t.step_id
        WHERE f.project_id = %s
        GROUP BY f.id, f.feature_name
        HAVING COUNT(*) FILTER (WHERE t.status = 'Completed') > 0
        ORDER BY completed DESC
        LIMIT 10
    """, (db_updater.project_id,))

    for i, row in enumerate(cursor.fetchall(), 1):
        feature_name, feat_completed, feat_total = row
        print(f"  {i:2}. {feature_name[:60]:60} {feat_completed:3}/{feat_total:3} ({feat_completed/feat_total*100:.0f}%)")

    cursor.close()

def main():
    """Main entry point"""
    print(f"\n{'='*80}")
    print("UPTRMS Implementation Verification")
    print(f"{'='*80}")

    # Check paths
    if not STEP_DEFINITIONS_PATH.exists():
        print(f"✗ Step definitions directory not found: {STEP_DEFINITIONS_PATH}")
        sys.exit(1)

    # Initialize database connection
    db_updater = DatabaseUpdater()
    db_updater.connect()
    db_updater.project_id = db_updater.get_project_id('UPTRMS')

    try:
        # Scan step definitions
        implemented_steps = scan_step_definitions()

        # Match and update database
        matched_count, updated_count = match_and_update(implemented_steps, db_updater)

        # Commit changes
        print(f"\nCommitting changes to database...")
        db_updater.commit()
        print(f"✓ Changes committed")

        # Generate report
        generate_report(db_updater)

        print(f"\n{'='*80}")
        print("Verification Complete")
        print(f"{'='*80}\n")

    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        db_updater.conn.rollback()
        sys.exit(1)
    finally:
        db_updater.close()

if __name__ == '__main__':
    main()
