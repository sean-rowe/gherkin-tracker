#!/usr/bin/env python3
"""
Verify BDD Step Implementations
Checks that tasks marked as "Completed" have actual BDD step implementations in step definition files
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

class StepVerifier:
    """Verifies BDD step implementations exist for completed tasks"""

    def __init__(self, codebase_path: str):
        self.codebase_path = Path(codebase_path)
        self.step_implementations = {}
        self.conn = None

    def connect_db(self):
        """Connect to database"""
        self.conn = psycopg2.connect(**DB_PARAMS)
        print(f"✓ Connected to database: {DB_PARAMS['dbname']}")

    def load_step_definitions(self) -> Dict[str, Dict]:
        """Load all step definitions from step definition files"""
        print("\n" + "="*80)
        print("Loading Step Definitions from Codebase")
        print("="*80)

        step_files = list(self.codebase_path.rglob('*Steps.cs'))
        print(f"Found {len(step_files)} step definition files")

        all_implementations = {}

        for step_file in step_files:
            try:
                content = step_file.read_text(encoding='utf-8', errors='ignore')

                # Find all step attributes with their implementations
                # Pattern: [Given/When/Then/And/But(@"pattern")] followed by method
                patterns = re.findall(
                    r'\[(Given|When|Then|And|But)\(@?"([^"]+)"\)\]\s*(?:public\s+)?(?:async\s+)?(?:Task\s+)?(\w+)\s*\(',
                    content,
                    re.MULTILINE | re.DOTALL
                )

                for step_type, pattern, method_name in patterns:
                    key = f"{step_type}::{pattern}"

                    # Find the method implementation
                    method_pattern = rf'(?:public\s+)?(?:async\s+)?(?:Task\s+)?{re.escape(method_name)}\s*\([^)]*\)\s*\{{([^}}]*)}}'
                    method_match = re.search(method_pattern, content, re.DOTALL)

                    implementation_body = ""
                    if method_match:
                        implementation_body = method_match.group(1).strip()

                    all_implementations[key] = {
                        'step_type': step_type,
                        'pattern': pattern,
                        'method_name': method_name,
                        'file': str(step_file.relative_to(self.codebase_path)),
                        'implementation': implementation_body,
                        'has_implementation': len(implementation_body) > 20  # Non-trivial implementation
                    }

            except Exception as e:
                print(f"  ⚠ Error reading {step_file.name}: {e}")

        print(f"✓ Loaded {len(all_implementations)} step implementations")
        return all_implementations

    def get_completed_tasks(self) -> List[Dict]:
        """Get all completed tasks from database"""
        cursor = self.conn.cursor()

        cursor.execute("""
            SELECT
                t.id as task_id,
                t.task_name,
                t.code_location,
                t.notes,
                s.id as step_id,
                s.step_type,
                s.step_text,
                f.feature_name,
                sc.scenario_name
            FROM task t
            JOIN step s ON t.step_id = s.id
            JOIN scenario_step ss ON s.id = ss.step_id
            JOIN scenario sc ON ss.scenario_id = sc.id
            JOIN feature f ON sc.feature_id = f.id
            WHERE t.status = 'Completed'
            ORDER BY f.feature_name, sc.scenario_name, ss.display_order
        """)

        tasks = []
        for row in cursor.fetchall():
            tasks.append({
                'task_id': row[0],
                'task_name': row[1],
                'code_location': row[2],
                'notes': row[3],
                'step_id': row[4],
                'step_type': row[5],
                'step_text': row[6],
                'feature_name': row[7],
                'scenario_name': row[8]
            })

        cursor.close()
        return tasks

    def verify_implementation(self, task: Dict, implementations: Dict) -> Dict:
        """Verify if a task has a proper BDD step implementation"""
        step_type = task['step_type']
        step_text = task['step_text']

        # Try exact match first
        for key, impl in implementations.items():
            impl_type, impl_pattern = key.split('::', 1)

            # Check if types match
            if impl_type != step_type and impl_type not in ['And', 'But']:
                continue

            # Check if text matches (accounting for regex patterns)
            if self._matches_pattern(step_text, impl_pattern):
                return {
                    'has_implementation': True,
                    'implementation_file': impl['file'],
                    'method_name': impl['method_name'],
                    'has_real_code': impl['has_implementation'],
                    'implementation_preview': impl['implementation'][:200] if impl['implementation'] else ""
                }

        return {
            'has_implementation': False,
            'implementation_file': None,
            'method_name': None,
            'has_real_code': False,
            'implementation_preview': ""
        }

    def _matches_pattern(self, step_text: str, pattern: str) -> bool:
        """Check if step text matches a SpecFlow pattern"""
        # Convert SpecFlow pattern to regex
        # (.+) -> .+
        # (.*) -> .*
        # (\d+) -> \d+
        # literal text stays the same

        regex_pattern = pattern
        regex_pattern = regex_pattern.replace('(', '\\(').replace(')', '\\)')
        regex_pattern = re.sub(r'\\\(\.?\*?\+?\\\)', r'.+', regex_pattern)
        regex_pattern = re.sub(r'\\\(\\d\+\\\)', r'\\d+', regex_pattern)

        try:
            return re.match(regex_pattern, step_text, re.IGNORECASE) is not None
        except:
            # Fallback to simple text matching
            return step_text.lower() in pattern.lower() or pattern.lower() in step_text.lower()

    def mark_fake_implementations(self, task_id: str):
        """Mark task as having fake/placeholder implementation"""
        cursor = self.conn.cursor()

        cursor.execute("""
            UPDATE task
            SET status = 'Pending',
                notes = 'REVERTED: Step definition exists but has no real implementation (placeholder code)',
                code_location = NULL,
                completed_at = NULL
            WHERE id = %s
        """, (task_id,))

        self.conn.commit()
        cursor.close()

    def run_verification(self):
        """Main verification process"""
        print("\n" + "="*80)
        print("BDD Implementation Verification")
        print("="*80)

        # Load step implementations
        implementations = self.load_step_definitions()

        # Get completed tasks
        completed_tasks = self.get_completed_tasks()
        print(f"\n✓ Found {len(completed_tasks)} completed tasks to verify\n")

        # Verification results
        verified = 0
        fake_implementations = 0
        no_implementation = 0
        real_implementations = 0

        issues = []

        for task in completed_tasks:
            verification = self.verify_implementation(task, implementations)

            if verification['has_implementation']:
                if verification['has_real_code']:
                    verified += 1
                    real_implementations += 1
                else:
                    # Has step definition but no real code
                    fake_implementations += 1
                    self.mark_fake_implementations(task['task_id'])

                    issues.append({
                        'type': 'FAKE_IMPLEMENTATION',
                        'feature': task['feature_name'],
                        'scenario': task['scenario_name'],
                        'step': f"{task['step_type']} {task['step_text']}",
                        'file': verification['implementation_file'],
                        'method': verification['method_name']
                    })
            else:
                # No step definition found
                no_implementation += 1
                self.mark_fake_implementations(task['task_id'])

                issues.append({
                    'type': 'NO_IMPLEMENTATION',
                    'feature': task['feature_name'],
                    'scenario': task['scenario_name'],
                    'step': f"{task['step_type']} {task['step_text']}",
                    'file': None,
                    'method': None
                })

        # Print summary
        print("="*80)
        print("Verification Results")
        print("="*80)
        print(f"Total completed tasks verified: {len(completed_tasks)}")
        print(f"✓ Real implementations: {real_implementations}")
        print(f"⚠ Fake/placeholder implementations: {fake_implementations}")
        print(f"✗ No implementation found: {no_implementation}")
        print(f"\nTasks reverted to Pending: {fake_implementations + no_implementation}")
        print("="*80)

        # Print detailed issues
        if issues:
            print("\n" + "="*80)
            print("ISSUES FOUND")
            print("="*80)

            # Group by type
            fake_issues = [i for i in issues if i['type'] == 'FAKE_IMPLEMENTATION']
            no_impl_issues = [i for i in issues if i['type'] == 'NO_IMPLEMENTATION']

            if fake_issues:
                print(f"\nFAKE/PLACEHOLDER IMPLEMENTATIONS ({len(fake_issues)}):")
                print("-" * 80)
                for i, issue in enumerate(fake_issues[:20], 1):  # Show first 20
                    print(f"{i}. Feature: {issue['feature']}")
                    print(f"   Scenario: {issue['scenario']}")
                    print(f"   Step: {issue['step']}")
                    print(f"   File: {issue['file']}")
                    print(f"   Method: {issue['method']}")
                    print()

                if len(fake_issues) > 20:
                    print(f"   ... and {len(fake_issues) - 20} more\n")

            if no_impl_issues:
                print(f"\nNO IMPLEMENTATION FOUND ({len(no_impl_issues)}):")
                print("-" * 80)
                for i, issue in enumerate(no_impl_issues[:20], 1):  # Show first 20
                    print(f"{i}. Feature: {issue['feature']}")
                    print(f"   Scenario: {issue['scenario']}")
                    print(f"   Step: {issue['step']}")
                    print()

                if len(no_impl_issues) > 20:
                    print(f"   ... and {len(no_impl_issues) - 20} more\n")

        # Final statistics
        cursor = self.conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM task WHERE status = 'Completed'")
        final_completed = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task WHERE status = 'Pending'")
        final_pending = cursor.fetchone()[0]

        cursor.close()

        print("\n" + "="*80)
        print("Final Database Statistics")
        print("="*80)
        print(f"Completed tasks (verified): {final_completed}")
        print(f"Pending tasks: {final_pending}")
        print(f"Total tasks: {final_completed + final_pending}")
        print(f"True completion rate: {final_completed / (final_completed + final_pending) * 100:.1f}%")
        print("="*80 + "\n")

def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: python verify_bdd_implementations.py <caresync_directory>")
        print("Example: python verify_bdd_implementations.py /Users/srowe/RiderProjects/caresync")
        sys.exit(1)

    codebase_path = sys.argv[1]

    if not Path(codebase_path).exists():
        print(f"✗ Directory not found: {codebase_path}")
        sys.exit(1)

    verifier = StepVerifier(codebase_path)
    verifier.connect_db()
    verifier.run_verification()
    verifier.conn.close()

if __name__ == '__main__':
    main()
