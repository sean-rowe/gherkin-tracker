#!/usr/bin/env python3
"""
Agent-Based Implementation Verifier
Uses Claude Code to check if pending Gherkin steps are already implemented
"""

import os
import sys
import subprocess
import psycopg2
from pathlib import Path
from typing import Dict, List
import time
import json

# Database connection
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

class ImplementationVerifier:
    """Uses Claude Code to verify if steps are already implemented"""

    def __init__(self, project_name: str, codebase_path: str, max_tasks: int = 100):
        self.project_name = project_name
        self.codebase_path = Path(codebase_path)
        self.max_tasks = max_tasks
        self.conn = None
        self.verified_count = 0
        self.already_implemented = 0
        self.not_implemented = 0

    def connect_db(self):
        """Connect to database"""
        self.conn = psycopg2.connect(**DB_PARAMS)
        print(f"✓ Connected to database: {DB_PARAMS['dbname']}")

    def get_pending_tasks(self, limit: int = None) -> List[Dict]:
        """Get pending tasks to verify for this project"""
        cursor = self.conn.cursor()

        query = """
            SELECT
                t.id as task_id,
                t.task_name,
                s.step_type,
                s.step_text,
                f.feature_name,
                f.file_name,
                sc.scenario_name
            FROM task t
            JOIN step s ON t.step_id = s.id
            JOIN scenario_step ss ON s.id = ss.step_id
            JOIN scenario sc ON ss.scenario_id = sc.id
            JOIN feature f ON sc.feature_id = f.id
            JOIN project p ON f.project_id = p.id
            WHERE t.status = 'Pending'
            AND p.name = %s
            ORDER BY f.priority DESC NULLS LAST, t.created_at
        """

        if limit:
            query += f" LIMIT {limit}"

        cursor.execute(query, (self.project_name,))

        tasks = []
        for row in cursor.fetchall():
            tasks.append({
                'task_id': row[0],
                'task_name': row[1],
                'step_type': row[2],
                'step_text': row[3],
                'feature_name': row[4],
                'file_name': row[5],
                'scenario_name': row[6]
            })

        cursor.close()
        return tasks

    def ask_claude_if_implemented(self, task: Dict) -> Dict:
        """Use Claude Code to check if a step is implemented"""

        step_type = task['step_type']
        step_text = task['step_text']
        feature_name = task['feature_name']
        scenario_name = task['scenario_name']

        # Create a prompt for Claude
        prompt = f"""Check if this BDD step is already implemented in the {self.project_name} codebase:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Please check:
1. Is there a SpecFlow step definition for this in any *Steps.cs file?
2. Is there business logic/service code that implements this functionality?
3. Are there any tests that verify this behavior?

Respond with a JSON object:
{{
    "is_implemented": true/false,
    "has_step_definition": true/false,
    "has_business_logic": true/false,
    "has_tests": true/false,
    "evidence_files": ["file1.cs", "file2.cs"],
    "confidence": "high/medium/low",
    "notes": "explanation of what was found"
}}

IMPORTANT: Only mark is_implemented=true if there is REAL working code, not TODO/NotImplementedException/placeholder code.
"""

        try:
            # Run Claude Code in the codebase directory
            result = subprocess.run(
                ['claude', '-p', prompt],
                cwd=str(self.codebase_path),
                capture_output=True,
                text=True,
                timeout=180  # 3 minutes
            )

            # Try to parse JSON from Claude's response
            output = result.stdout

            # Extract JSON from markdown code blocks if present
            if '```json' in output:
                json_start = output.find('```json') + 7
                json_end = output.find('```', json_start)
                json_str = output[json_start:json_end].strip()
            elif '```' in output:
                json_start = output.find('```') + 3
                json_end = output.find('```', json_start)
                json_str = output[json_start:json_end].strip()
            elif '{' in output and '}' in output:
                json_start = output.find('{')
                json_end = output.rfind('}') + 1
                json_str = output[json_start:json_end]
            else:
                json_str = output

            response = json.loads(json_str)
            return response

        except subprocess.TimeoutExpired:
            print(f"  ⚠ Claude timeout for task")
            return {"is_implemented": False, "confidence": "low", "notes": "Claude timeout"}
        except json.JSONDecodeError as e:
            print(f"  ⚠ Failed to parse Claude response: {e}")
            print(f"  Raw output: {output[:200]}")
            return {"is_implemented": False, "confidence": "low", "notes": f"Parse error: {e}"}
        except Exception as e:
            print(f"  ⚠ Error calling Claude: {e}")
            return {"is_implemented": False, "confidence": "low", "notes": f"Error: {e}"}

    def mark_as_implemented(self, task_id: str, evidence: Dict):
        """Mark task as completed in database"""
        cursor = self.conn.cursor()

        evidence_files = ', '.join(evidence.get('evidence_files', []))
        notes = f"Auto-verified: {evidence.get('notes', '')}\nConfidence: {evidence.get('confidence', 'unknown')}\nFiles: {evidence_files}"

        cursor.execute("""
            UPDATE task
            SET status = 'Completed',
                code_location = %s,
                completed_at = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP,
                notes = %s
            WHERE id = %s
        """, (evidence_files, notes, task_id))

        self.conn.commit()
        cursor.close()

    def verify_tasks(self):
        """Main verification loop"""
        print("\n" + "="*80)
        print("Agent-Based Implementation Verification")
        print("="*80)
        print(f"Max tasks to verify: {self.max_tasks}")
        print(f"Codebase: {self.codebase_path}")
        print("="*80 + "\n")

        # Get pending tasks
        tasks = self.get_pending_tasks(self.max_tasks)
        print(f"✓ Found {len(tasks)} pending tasks\n")

        for i, task in enumerate(tasks, 1):
            print(f"\n[{i}/{len(tasks)}] Verifying...")
            print(f"  Feature: {task['feature_name']}")
            print(f"  Scenario: {task['scenario_name']}")
            print(f"  Step: {task['step_type']} {task['step_text']}")

            # Ask Claude if it's implemented
            result = self.ask_claude_if_implemented(task)

            if result.get('is_implemented', False):
                print(f"  ✓ ALREADY IMPLEMENTED")
                print(f"    Confidence: {result.get('confidence', 'unknown')}")
                print(f"    Evidence: {result.get('evidence_files', [])}")
                print(f"    Notes: {result.get('notes', '')[:100]}")

                # Mark as completed
                self.mark_as_implemented(task['task_id'], result)
                self.already_implemented += 1
            else:
                print(f"  ✗ Not implemented")
                self.not_implemented += 1

            self.verified_count += 1

            # Small delay to avoid overwhelming Claude
            time.sleep(1)

        # Final statistics
        print("\n" + "="*80)
        print("Verification Complete")
        print("="*80)
        print(f"Tasks verified: {self.verified_count}")
        print(f"✓ Already implemented: {self.already_implemented}")
        print(f"✗ Not implemented: {self.not_implemented}")
        print(f"Implementation rate: {self.already_implemented / self.verified_count * 100:.1f}%")
        print("="*80 + "\n")

        # Get updated stats from database for this project only
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT COUNT(*) FROM task t
            JOIN step s ON t.step_id = s.id
            JOIN scenario_step ss ON s.id = ss.step_id
            JOIN scenario sc ON ss.scenario_id = sc.id
            JOIN feature f ON sc.feature_id = f.id
            JOIN project p ON f.project_id = p.id
            WHERE t.status = 'Completed' AND p.name = %s
        """, (self.project_name,))
        total_completed = cursor.fetchone()[0]

        cursor.execute("""
            SELECT COUNT(*) FROM task t
            JOIN step s ON t.step_id = s.id
            JOIN scenario_step ss ON s.id = ss.step_id
            JOIN scenario sc ON ss.scenario_id = sc.id
            JOIN feature f ON sc.feature_id = f.id
            JOIN project p ON f.project_id = p.id
            WHERE t.status = 'Pending' AND p.name = %s
        """, (self.project_name,))
        total_pending = cursor.fetchone()[0]

        cursor.close()

        print("="*80)
        print(f"Database Statistics for {self.project_name}")
        print("="*80)
        print(f"Total completed: {total_completed}")
        print(f"Total pending: {total_pending}")
        print(f"Overall completion: {total_completed / (total_completed + total_pending) * 100:.1f}%")
        print("="*80 + "\n")

def main():
    if len(sys.argv) < 3:
        print("Usage: python agent_verify_implementations.py <project_name> <codebase_directory> [max_tasks]")
        print("Example: python agent_verify_implementations.py CareSync /Users/srowe/RiderProjects/caresync 10")
        print("Example: python agent_verify_implementations.py CueMap /Users/srowe/RiderProjects/cuemap 20")
        sys.exit(1)

    project_name = sys.argv[1]
    codebase_path = sys.argv[2]
    max_tasks = int(sys.argv[3]) if len(sys.argv) > 3 else 100

    if not Path(codebase_path).exists():
        print(f"✗ Directory not found: {codebase_path}")
        sys.exit(1)

    verifier = ImplementationVerifier(project_name, codebase_path, max_tasks)
    verifier.connect_db()

    try:
        verifier.verify_tasks()
    except KeyboardInterrupt:
        print("\n\n✗ Interrupted by user")
    finally:
        verifier.conn.close()

if __name__ == '__main__':
    main()
