#!/usr/bin/env python3
"""
Gherkin Feature Importer
Parses .feature files and imports them into the gherkin_tracker PostgreSQL database
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Optional
import psycopg2
from psycopg2.extras import execute_values
import uuid

# Database connection parameters
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

class GherkinParser:
    """Parses Gherkin .feature files"""

    def __init__(self, file_path: str):
        self.file_path = file_path
        self.content = Path(file_path).read_text(encoding='utf-8')

    def parse(self) -> Dict:
        """Parse the feature file and return structured data"""
        lines = self.content.split('\n')

        feature_data = {
            'file_name': Path(self.file_path).name,
            'file_path': str(Path(self.file_path).relative_to(Path(self.file_path).parts[0])),
            'feature_name': '',
            'as_a': None,
            'i_want': None,
            'so_that': None,
            'description': '',
            'background': None,
            'tags': [],
            'scenarios': []
        }

        current_section = None
        current_scenario = None
        current_steps = []
        description_lines = []
        background_steps = []

        for line in lines:
            stripped = line.strip()

            # Skip empty lines and comments
            if not stripped or stripped.startswith('#'):
                continue

            # Parse tags
            if stripped.startswith('@'):
                tags = [tag.strip() for tag in stripped.split() if tag.startswith('@')]
                feature_data['tags'].extend(tags)
                continue

            # Parse Feature declaration
            if stripped.startswith('Feature:'):
                feature_data['feature_name'] = stripped.replace('Feature:', '').strip()
                current_section = 'feature'
                continue

            # Parse As a / I want / So that
            if stripped.startswith('As a ') or stripped.startswith('As an '):
                feature_data['as_a'] = stripped
                continue

            if stripped.startswith('I want'):
                feature_data['i_want'] = stripped
                continue

            if stripped.startswith('So that'):
                feature_data['so_that'] = stripped
                continue

            # Parse Background
            if stripped.startswith('Background:'):
                current_section = 'background'
                continue

            # Parse Scenario or Scenario Outline
            if stripped.startswith('Scenario:') or stripped.startswith('Scenario Outline:'):
                # Save previous scenario if exists
                if current_scenario:
                    current_scenario['steps'] = current_steps
                    feature_data['scenarios'].append(current_scenario)

                scenario_type = 'ScenarioOutline' if 'Outline' in stripped else 'Scenario'
                scenario_name = stripped.replace('Scenario:', '').replace('Scenario Outline:', '').strip()

                current_scenario = {
                    'scenario_name': scenario_name,
                    'scenario_type': scenario_type,
                    'tags': feature_data['tags'].copy(),
                    'description': '',
                    'display_order': len(feature_data['scenarios']) + 1
                }
                current_steps = []
                current_section = 'scenario'
                continue

            # Parse steps (Given, When, Then, And, But)
            step_match = re.match(r'^(Given|When|Then|And|But)\s+(.+)$', stripped)
            if step_match and current_section in ['scenario', 'background']:
                step_type = step_match.group(1)
                step_text = step_match.group(2)

                step = {
                    'step_type': step_type,
                    'step_text': step_text,
                    'display_order': len(current_steps) + 1 if current_section == 'scenario' else len(background_steps) + 1
                }

                if current_section == 'background':
                    background_steps.append(step)
                else:
                    current_steps.append(step)
                continue

            # Parse Examples for Scenario Outline
            if stripped.startswith('Examples:'):
                current_section = 'examples'
                continue

            # Collect description lines
            if current_section == 'feature' and not any(stripped.startswith(kw) for kw in ['Scenario', 'Background', 'As a', 'I want', 'So that']):
                description_lines.append(stripped)

        # Save last scenario
        if current_scenario:
            current_scenario['steps'] = current_steps
            feature_data['scenarios'].append(current_scenario)

        # Compile description
        feature_data['description'] = '\n'.join(description_lines).strip()

        # Compile background
        if background_steps:
            feature_data['background'] = '\n'.join([f"{s['step_type']} {s['step_text']}" for s in background_steps])

        # Join tags
        feature_data['tags'] = ', '.join(set(feature_data['tags'])) if feature_data['tags'] else None

        return feature_data

class GherkinImporter:
    """Imports parsed Gherkin data into PostgreSQL database"""

    def __init__(self):
        self.conn = None
        self.project_id = None
        self.step_cache = {}  # Cache for step deduplication

    def connect(self):
        """Connect to PostgreSQL database"""
        try:
            self.conn = psycopg2.connect(**DB_PARAMS)
            self.conn.autocommit = False
            print(f"✓ Connected to database: {DB_PARAMS['dbname']}")
        except Exception as e:
            print(f"✗ Database connection failed: {e}")
            sys.exit(1)

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()

    def get_or_create_project(self, project_name: str) -> uuid.UUID:
        """Get or create project and return its ID"""
        cursor = self.conn.cursor()

        # Check if project exists
        cursor.execute("SELECT id FROM project WHERE name = %s", (project_name,))
        result = cursor.fetchone()

        if result:
            project_id = result[0]
            print(f"✓ Using existing project: {project_name} ({project_id})")
        else:
            # Create new project
            cursor.execute(
                """INSERT INTO project (name, description, created_at, updated_at)
                   VALUES (%s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                   RETURNING id""",
                (project_name, 'CareSync Multi-Platform Health Tracking Application')
            )
            project_id = cursor.fetchone()[0]
            self.conn.commit()
            print(f"✓ Created new project: {project_name} ({project_id})")

        cursor.close()
        return project_id

    def get_or_create_step(self, step_type: str, step_text: str) -> uuid.UUID:
        """Get or create step (with deduplication) and return its ID"""
        # Check cache first
        cache_key = f"{step_type}::{step_text}"
        if cache_key in self.step_cache:
            return self.step_cache[cache_key]

        cursor = self.conn.cursor()

        # Check if step exists
        cursor.execute(
            "SELECT id FROM step WHERE step_type = %s AND step_text = %s",
            (step_type, step_text)
        )
        result = cursor.fetchone()

        if result:
            step_id = result[0]
            # Increment usage count
            cursor.execute(
                "UPDATE step SET usage_count = usage_count + 1 WHERE id = %s",
                (step_id,)
            )
        else:
            # Create new step
            cursor.execute(
                """INSERT INTO step (step_type, step_text, usage_count, created_at, updated_at)
                   VALUES (%s, %s, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                   RETURNING id""",
                (step_type, step_text)
            )
            step_id = cursor.fetchone()[0]

        cursor.close()

        # Cache the result
        self.step_cache[cache_key] = step_id

        return step_id

    def import_feature(self, feature_data: Dict) -> None:
        """Import a single feature with all its scenarios and steps"""
        cursor = self.conn.cursor()

        try:
            # Insert feature
            cursor.execute(
                """INSERT INTO feature (
                    project_id, file_name, file_path, feature_name,
                    as_a, i_want, so_that, description, background, tags,
                    created_at, updated_at
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                ) RETURNING id""",
                (
                    self.project_id,
                    feature_data['file_name'],
                    feature_data['file_path'],
                    feature_data['feature_name'],
                    feature_data['as_a'],
                    feature_data['i_want'],
                    feature_data['so_that'],
                    feature_data['description'],
                    feature_data['background'],
                    feature_data['tags']
                )
            )
            feature_id = cursor.fetchone()[0]

            # Import scenarios
            for scenario_data in feature_data['scenarios']:
                cursor.execute(
                    """INSERT INTO scenario (
                        feature_id, scenario_name, scenario_type, tags,
                        display_order, created_at, updated_at
                    ) VALUES (
                        %s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                    ) RETURNING id""",
                    (
                        feature_id,
                        scenario_data['scenario_name'],
                        scenario_data['scenario_type'],
                        ', '.join(scenario_data['tags']) if scenario_data['tags'] else None,
                        scenario_data['display_order']
                    )
                )
                scenario_id = cursor.fetchone()[0]

                # Import steps for this scenario
                for step_data in scenario_data['steps']:
                    # Get or create step
                    step_id = self.get_or_create_step(
                        step_data['step_type'],
                        step_data['step_text']
                    )

                    # Link step to scenario
                    cursor.execute(
                        """INSERT INTO scenario_step (
                            scenario_id, step_id, display_order, created_at
                        ) VALUES (
                            %s, %s, %s, CURRENT_TIMESTAMP
                        )""",
                        (scenario_id, step_id, step_data['display_order'])
                    )

                    # Create task for step (if doesn't exist)
                    cursor.execute(
                        """INSERT INTO task (
                            step_id, task_name, description,
                            status, priority, created_at, updated_at
                        ) VALUES (
                            %s, %s, %s, 'Pending', 0,
                            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                        ) ON CONFLICT (step_id) DO NOTHING""",
                        (
                            step_id,
                            f"Implement: {step_data['step_type']} {step_data['step_text'][:100]}",
                            f"Implement Gherkin step: {step_data['step_type']} {step_data['step_text']}"
                        )
                    )

            # NOTE: Do NOT commit here - let main() handle the transaction
            print(f"  ✓ Imported: {feature_data['file_name']} ({len(feature_data['scenarios'])} scenarios)")

        except Exception as e:
            # Clear step cache on error to prevent FK violations
            self.step_cache.clear()
            print(f"  ✗ Failed to import {feature_data['file_name']}: {e}")
            raise
        finally:
            cursor.close()

def main():
    """Main entry point"""
    if len(sys.argv) < 3:
        print("Usage: python import_gherkin.py <project_name> <features_directory>")
        print("Example: python import_gherkin.py CareSync /Users/srowe/RiderProjects/caresync/tests/CareSync.Specs/Features")
        sys.exit(1)

    project_name = sys.argv[1]
    features_dir = Path(sys.argv[2])

    if not features_dir.exists():
        print(f"✗ Directory not found: {features_dir}")
        sys.exit(1)

    # Find all .feature files
    feature_files = list(features_dir.rglob('*.feature'))
    print(f"\n{'='*60}")
    print(f"Gherkin Feature Importer")
    print(f"{'='*60}")
    print(f"Project: {project_name}")
    print(f"Directory: {features_dir}")
    print(f"Found {len(feature_files)} feature files")
    print(f"{'='*60}\n")

    # Initialize importer
    importer = GherkinImporter()
    importer.connect()
    importer.project_id = importer.get_or_create_project(project_name)

    # Import each feature file with individual commits (to handle errors gracefully)
    imported_count = 0
    failed_count = 0

    for feature_file in feature_files:
        try:
            parser = GherkinParser(str(feature_file))
            feature_data = parser.parse()

            if feature_data['feature_name']:
                importer.import_feature(feature_data)
                # Commit after each successful import
                importer.conn.commit()
                imported_count += 1
            else:
                print(f"  ⚠ Skipped (no feature name): {feature_file.name}")
        except Exception as e:
            print(f"  ✗ Error parsing {feature_file.name}: {e}")
            failed_count += 1
            # Rollback the failed transaction and continue with next feature
            importer.conn.rollback()
            importer.step_cache.clear()

    print(f"\n✓ Import process completed")

    importer.close()

    print(f"\n{'='*60}")
    print(f"Import Complete")
    print(f"{'='*60}")
    print(f"Imported: {imported_count} features")
    print(f"Failed: {failed_count} features")
    print(f"{'='*60}\n")

if __name__ == '__main__':
    main()
