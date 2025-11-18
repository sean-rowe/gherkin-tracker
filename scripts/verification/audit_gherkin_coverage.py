#!/usr/bin/env python3
"""
Audit Gherkin Coverage Against Requirements
Compares CLAUDE.md requirements with imported Gherkin features
"""

import re
import psycopg2
from pathlib import Path
import os

DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

CUEMAP_PROJECT_ID = 'e8c1d48b-972d-483c-9644-d3d0accf6c8e'
CLAUDE_MD_PATH = '/Users/srowe/Projects/cuemap/docs/CLAUDE.md'

def parse_requirements(claude_md_path):
    """Extract all functional requirements from CLAUDE.md"""
    content = Path(claude_md_path).read_text()

    # Find Phase 1 and Phase 2 sections
    requirements = []

    # Pattern to match requirement sections
    phase_pattern = r'(?:Phase [12]|MVP|Core Features?).*?(?=Phase [23]|Advanced|$)'
    requirement_pattern = r'(?:^|\n)(?:#+\s*)?\**(\d+\.?\d*\.?\s*[^\n]+?)(?:\**)?(?:\n|$)'

    phases = re.findall(phase_pattern, content, re.DOTALL | re.IGNORECASE)

    for phase_content in phases:
        # Extract numbered requirements
        matches = re.findall(r'(?:^|\n)(?:#+\s*)?\**(\d+\.?\d*\.?\s+[^:\n]+?)(?:\**)?[::\n]', phase_content, re.MULTILINE)
        for match in matches:
            clean_req = match.strip().strip('*').strip()
            if clean_req and not clean_req.startswith('#'):
                requirements.append(clean_req)

    return list(set(requirements))  # Deduplicate

def get_imported_features():
    """Get all features imported to the database"""
    conn = psycopg2.connect(**DB_PARAMS)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            feature_name,
            file_name,
            COUNT(DISTINCT s.id) as scenario_count
        FROM feature f
        LEFT JOIN scenario s ON f.id = s.feature_id
        WHERE f.project_id = %s
        AND f.is_active = TRUE
        GROUP BY f.id, f.feature_name, f.file_name
        ORDER BY f.feature_name
    """, (CUEMAP_PROJECT_ID,))

    features = cursor.fetchall()
    cursor.close()
    conn.close()

    return features

def analyze_coverage(requirements, features):
    """Analyze which requirements are covered by features"""

    # Normalize requirement text for matching
    def normalize(text):
        return re.sub(r'[^\w\s]', '', text.lower())

    feature_names = [normalize(f[0]) for f in features]

    covered = []
    not_covered = []

    for req in requirements:
        req_norm = normalize(req)

        # Check if any feature name matches this requirement
        matched = False
        for fname in feature_names:
            # Check for key words match
            req_words = set(req_norm.split())
            fname_words = set(fname.split())

            # If more than 50% of requirement words are in feature name, consider it covered
            if len(req_words) > 0:
                overlap = len(req_words & fname_words) / len(req_words)
                if overlap > 0.4:  # 40% word overlap threshold
                    matched = True
                    break

        if matched:
            covered.append(req)
        else:
            not_covered.append(req)

    return covered, not_covered

def main():
    print("=" * 80)
    print("Gherkin Coverage Audit")
    print("=" * 80)
    print()

    # Parse requirements
    print(f"Reading requirements from: {CLAUDE_MD_PATH}")
    requirements = parse_requirements(CLAUDE_MD_PATH)
    print(f"Found {len(requirements)} requirements in CLAUDE.md\n")

    # Get imported features
    print(f"Querying database for imported features...")
    features = get_imported_features()
    print(f"Found {len(features)} features in database\n")

    # Analyze coverage
    covered, not_covered = analyze_coverage(requirements, features)

    # Print results
    print("=" * 80)
    print(f"COVERAGE SUMMARY")
    print("=" * 80)
    print(f"Total Requirements: {len(requirements)}")
    print(f"Covered: {len(covered)} ({len(covered)/len(requirements)*100:.1f}%)")
    print(f"Not Covered: {len(not_covered)} ({len(not_covered)/len(requirements)*100:.1f}%)")
    print()

    if not_covered:
        print("=" * 80)
        print("POTENTIALLY MISSING COVERAGE")
        print("=" * 80)
        for i, req in enumerate(not_covered, 1):
            print(f"{i}. {req}")
        print()

    print("=" * 80)
    print("ALL IMPORTED FEATURES")
    print("=" * 80)
    for fname, ffile, scount in features:
        print(f"• {fname} ({scount} scenarios) - {ffile}")
    print()

    print("=" * 80)
    print("MANUAL REVIEW NEEDED")
    print("=" * 80)
    print("The above analysis uses keyword matching which may have false negatives.")
    print("Please manually review the 'Potentially Missing Coverage' list against")
    print("the imported features to confirm if any requirements are truly missing.")
    print("=" * 80)

if __name__ == '__main__':
    main()
