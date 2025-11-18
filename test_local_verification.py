#!/usr/bin/env python3
"""
Test Local LLM Verification on Single Task
Uses Qwen 2.5 Coder 32B to check if a Gherkin step is implemented
"""

import os
import sys
import psycopg2
from pathlib import Path
from local_llm import LocalLLM
import json

DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}

def get_single_pending_task(project_name: str):
    """Get one pending task from database"""
    conn = psycopg2.connect(**DB_PARAMS)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            t.id as task_id,
            t.task_name,
            s.step_type,
            s.step_text,
            f.feature_name,
            sc.scenario_name
        FROM task t
        JOIN step s ON t.step_id = s.id
        JOIN scenario_step ss ON s.id = ss.step_id
        JOIN scenario sc ON ss.scenario_id = sc.id
        JOIN feature f ON sc.feature_id = f.id
        JOIN project p ON f.project_id = p.id
        WHERE t.status = 'Pending'
        AND p.name = %s
        AND t.business_logic_implemented = false
        ORDER BY RANDOM()
        LIMIT 1
    """, (project_name,))

    row = cursor.fetchone()
    cursor.close()
    conn.close()

    if row:
        return {
            'task_id': row[0],
            'task_name': row[1],
            'step_type': row[2],
            'step_text': row[3],
            'feature_name': row[4],
            'scenario_name': row[5]
        }
    return None

def check_implementation_with_local_llm(task: dict, codebase_path: Path, llm: LocalLLM) -> dict:
    """Use local LLM to check if step is implemented"""

    prompt = f"""You are analyzing a C# codebase to determine if a BDD Gherkin step is already implemented.

PROJECT: CareSync (Multi-platform health tracking application)
CODEBASE: {codebase_path}

GHERKIN STEP TO CHECK:
Feature: {task['feature_name']}
Scenario: {task['scenario_name']}
Step: {task['step_type']} {task['step_text']}

TASK:
1. Check if there's a SpecFlow step definition for this in *Steps.cs files
2. Check if there's business logic (services/controllers) that implements this functionality
3. Determine if this is truly implemented or just placeholder/stub code

RESPOND WITH VALID JSON ONLY (no markdown, no code blocks):
{{
    "is_implemented": true/false,
    "has_step_definition": true/false,
    "has_business_logic": true/false,
    "confidence": "high/medium/low",
    "evidence": "brief description of what you found",
    "files_checked": ["file1", "file2"]
}}

IMPORTANT:
- Only set is_implemented=true if you find REAL working code (not NotImplementedException or TODO)
- Be conservative - if unsure, set is_implemented=false
- Keep evidence brief (1-2 sentences)

JSON RESPONSE:"""

    print("\n" + "="*80)
    print("SENDING TO LOCAL LLM (Qwen 2.5 Coder 32B)")
    print("="*80)
    print(f"Prompt length: {len(prompt)} characters")
    print("="*80)

    # Generate response
    response = llm.generate(
        prompt=prompt,
        max_tokens=500,
        temperature=0.1,  # Low temperature for factual analysis
        stop=["```"]  # Stop at code blocks
    )

    print("\n" + "="*80)
    print("LLM RESPONSE")
    print("="*80)
    print(response)
    print("="*80)

    # Try to parse JSON
    try:
        # Clean up response - remove markdown if present
        clean_response = response.strip()
        if clean_response.startswith('```'):
            # Extract JSON from markdown code block
            lines = clean_response.split('\n')
            clean_response = '\n'.join([l for l in lines if not l.startswith('```')])

        # Find JSON object
        if '{' in clean_response and '}' in clean_response:
            start = clean_response.find('{')
            end = clean_response.rfind('}') + 1
            json_str = clean_response[start:end]
            result = json.loads(json_str)
            return result
        else:
            print("⚠ No JSON found in response")
            return {
                "is_implemented": False,
                "confidence": "low",
                "evidence": "Could not parse LLM response",
                "error": "No JSON in response"
            }
    except json.JSONDecodeError as e:
        print(f"⚠ JSON parse error: {e}")
        return {
            "is_implemented": False,
            "confidence": "low",
            "evidence": "JSON parse error",
            "error": str(e)
        }

def main():
    if len(sys.argv) < 3:
        print("Usage: python test_local_verification.py <project_name> <codebase_path>")
        print("Example: python test_local_verification.py CareSync /Users/srowe/RiderProjects/caresync")
        sys.exit(1)

    project_name = sys.argv[1]
    codebase_path = Path(sys.argv[2])

    print("\n" + "="*80)
    print("LOCAL LLM VERIFICATION TEST")
    print("="*80)
    print(f"Project: {project_name}")
    print(f"Codebase: {codebase_path}")
    print(f"Model: Qwen 2.5 Coder 32B (22GB)")
    print("="*80)

    # Get a random pending task
    print("\nFetching random pending task from database...")
    task = get_single_pending_task(project_name)

    if not task:
        print("✗ No pending tasks found!")
        sys.exit(1)

    print(f"\n✓ Selected task:")
    print(f"  Feature: {task['feature_name']}")
    print(f"  Scenario: {task['scenario_name']}")
    print(f"  Step: {task['step_type']} {task['step_text']}")

    # Initialize local LLM with Qwen
    print("\n" + "="*80)
    print("INITIALIZING QWEN 2.5 CODER 32B")
    print("="*80)
    print("Loading model (this may take 30-60 seconds)...")

    llm = LocalLLM(
        model_path=str(Path.home() / 'models' / 'qwen2.5-coder-32b-instruct-q5_k_m.gguf'),
        n_ctx=16384,  # 16K context should be enough
        n_gpu_layers=0,  # CPU only (your AMD GPU isn't compatible)
        n_threads=10  # Use 10 CPU cores
    )

    if not llm.load_model():
        print("✗ Failed to load model!")
        sys.exit(1)

    print("✓ Model loaded successfully!")

    # Check implementation
    print("\n" + "="*80)
    print("ANALYZING IMPLEMENTATION")
    print("="*80)

    result = check_implementation_with_local_llm(task, codebase_path, llm)

    # Display results
    print("\n" + "="*80)
    print("VERIFICATION RESULT")
    print("="*80)
    print(f"Is Implemented: {result.get('is_implemented', False)}")
    print(f"Has Step Definition: {result.get('has_step_definition', 'unknown')}")
    print(f"Has Business Logic: {result.get('has_business_logic', 'unknown')}")
    print(f"Confidence: {result.get('confidence', 'unknown')}")
    print(f"Evidence: {result.get('evidence', 'none')}")
    if 'files_checked' in result:
        print(f"Files: {', '.join(result['files_checked'])}")
    if 'error' in result:
        print(f"Error: {result['error']}")
    print("="*80 + "\n")

if __name__ == '__main__':
    main()
