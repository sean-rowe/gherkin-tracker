#!/usr/bin/env python3
"""
Claude Code Integrated Agent System - Multi-Project Support
Uses Claude Code CLI for actual BDD implementation across multiple languages and frameworks
"""

import os
import sys
import uuid
import psycopg2
import psycopg2.extras
from psycopg2.extras import RealDictCursor
from datetime import datetime
from typing import Optional, Dict, List
import json
import subprocess
import time
import re
import logging
from pathlib import Path
from gherkin_tracker.domain.project_config import ProjectConfigManager, ProjectConfig

# Setup logging
def setup_logging(log_file=None, verbose=False):
    """Setup comprehensive logging for agent operations"""
    log_level = logging.DEBUG if verbose else logging.INFO

    # Create formatters
    detailed_formatter = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    # Setup root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)

    # Remove existing handlers
    root_logger.handlers = []

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)
    console_handler.setFormatter(detailed_formatter)
    root_logger.addHandler(console_handler)

    # File handler (detailed format)
    if log_file:
        file_handler = logging.FileHandler(log_file, mode='a')
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(detailed_formatter)
        root_logger.addHandler(file_handler)

        logging.info("=" * 100)
        logging.info(f"NEW AGENT SESSION STARTED")
        logging.info("=" * 100)

    return root_logger

# Register UUID adapter for psycopg2
psycopg2.extras.register_uuid()

# Database connection parameters
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432
}


class ClaudeCodeAgent:
    """Agent that uses Claude Code CLI to implement BDD steps, with local LLM fallback"""

    def __init__(self, agent_id: uuid.UUID, agent_type: str, name: str, conn, config_manager: ProjectConfigManager, project_filter: Optional[str] = None, use_local_llm: bool = False):
        self.agent_id = agent_id
        self.agent_type = agent_type
        self.name = name
        self.conn = conn
        self.config_manager = config_manager
        self.current_task = None
        self.current_project_config = None
        self.project_filter = project_filter
        self.use_local_llm = use_local_llm
        self.local_llm = None

        # Initialize local LLM if requested
        if use_local_llm:
            from gherkin_tracker.infrastructure.local_llm import LocalLLM
            self.local_llm = LocalLLM()
            logging.info("Local LLM fallback enabled")

    def get_next_task(self) -> Optional[Dict]:
        """Get the next task to work on"""
        cursor = self.conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM sp_get_next_task(%s, %s)", (self.agent_type, self.project_filter))
        task = cursor.fetchone()
        cursor.close()

        if task:
            self.current_task = dict(task)

            # Get project configuration
            project_name = task.get('project_name', 'CareSync')
            self.current_project_config = self.config_manager.get_project(project_name)

            if not self.current_project_config:
                print(f"[{self.name}] ERROR: No configuration found for project '{project_name}'")
                print(f"[{self.name}] Available projects: {', '.join(self.config_manager.list_projects())}")
                return None

            print(f"\n{'='*80}")
            print(f"[{self.name}] NEW TASK ASSIGNED")
            print(f"{'='*80}")
            print(f"Project:  {project_name} ({self.current_project_config.language}/{self.current_project_config.test_framework})")
            print(f"Feature:  {task['feature_name']}")
            print(f"Scenario: {task['scenario_name']}")
            print(f"Step:     {task['step_type']} {task['step_text']}")
            print(f"{'='*80}\n")
            return self.current_task
        else:
            print(f"\n[{self.name}] No more tasks available")
            return None

    def assign_task(self, task_id: uuid.UUID) -> bool:
        """Assign a task to this agent"""
        cursor = self.conn.cursor()
        try:
            cursor.execute(
                "SELECT * FROM sp_assign_task_to_agent(%s, %s)",
                (task_id, self.agent_id)
            )
            self.conn.commit()
            cursor.close()
            return True
        except Exception as e:
            self.conn.rollback()
            cursor.close()
            print(f"[{self.name}] Failed to assign task: {e}")
            return False

    def validate_generated_code(self, file_path: str) -> Dict:
        """
        Scan generated code for forbidden patterns that indicate placeholder/incomplete code.
        Returns dict with 'valid' bool and list of 'violations' found.
        """
        if not os.path.exists(file_path):
            return {'valid': True, 'violations': []}

        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        violations = []

        # Forbidden comment patterns (case-insensitive)
        forbidden_patterns = [
            (r'//\s*TODO', 'TODO comment'),
            (r'//\s*FIXME', 'FIXME comment'),
            (r'//\s*HACK', 'HACK comment'),
            (r'//\s*In a real implementation', '"In a real implementation" placeholder comment'),
            (r'//\s*This would be', '"This would be" placeholder comment'),
            (r'//\s*This should', '"This should" placeholder comment'),
            (r'//\s*Not implemented yet', '"Not implemented yet" comment'),
            (r'//\s*To be completed', '"To be completed" comment'),
            (r'//\s*Placeholder', 'Placeholder comment'),
            (r'//\s*Stub', 'Stub comment'),
            (r'//\s*Mock implementation', 'Mock implementation comment'),
            (r'//\s*For testing purposes only', '"For testing purposes only" comment'),
            (r'//\s*Temporary', 'Temporary comment'),
        ]

        # Forbidden code patterns
        forbidden_code = [
            (r'throw new NotImplementedException\(\)', 'NotImplementedException'),
            (r'return null!;\s*$', 'return null! with no logic'),
            (r'await Task\.CompletedTask;\s*$', 'await Task.CompletedTask stub'),
        ]

        import re

        for pattern, description in forbidden_patterns:
            matches = re.finditer(pattern, content, re.IGNORECASE | re.MULTILINE)
            for match in matches:
                line_num = content[:match.start()].count('\n') + 1
                violations.append(f"Line {line_num}: {description}")

        for pattern, description in forbidden_code:
            matches = re.finditer(pattern, content, re.MULTILINE)
            for match in matches:
                line_num = content[:match.start()].count('\n') + 1
                violations.append(f"Line {line_num}: {description}")

        return {
            'valid': len(violations) == 0,
            'violations': violations
        }

    def run_claude(self, prompt: str, timeout: int = 600, log_prompt: bool = True) -> Dict:
        """
        Run Claude Code CLI with a prompt, with fallback to local LLM.

        Tries Claude Code first. If that fails or use_local_llm is True, uses local model.

        Args:
            prompt: Prompt to send
            timeout: Timeout in seconds (only for Claude Code)
            log_prompt: Whether to log the prompt

        Returns: {
            'success': bool,
            'output': str,
            'error': str,
            'model_used': 'claude' | 'local'
        }
        """
        if not self.current_project_config:
            return {
                'success': False,
                'output': '',
                'error': 'No project configuration available',
                'model_used': 'none'
            }

        try:
            project_path = Path(self.current_project_config.path)

            # Verify project path exists
            if not project_path.exists():
                return {
                    'success': False,
                    'output': '',
                    'error': f'Project path does not exist: {project_path}',
                    'model_used': 'none'
                }

            # Log the prompt if requested
            if log_prompt:
                logging.debug("=" * 100)
                logging.debug("SENDING PROMPT TO LLM:")
                logging.debug("-" * 100)
                # Log first 500 chars of prompt
                prompt_preview = prompt[:500] + "..." if len(prompt) > 500 else prompt
                logging.debug(prompt_preview)
                logging.debug("=" * 100)

            # Try Claude Code first (unless use_local_llm is explicitly set)
            if not self.use_local_llm:
                try:
                    # Run claude with the prompt
                    # Use --dangerously-skip-permissions for automated agent use
                    # This bypasses ALL permission checks so Claude can write files without approval
                    logging.info(f"Executing Claude Code CLI (timeout: {timeout}s)...")
                    result = subprocess.run(
                        ['claude', '-p', '--dangerously-skip-permissions', prompt],
                        capture_output=True,
                        text=True,
                        timeout=timeout,
                        cwd=str(project_path),
                        stdin=subprocess.DEVNULL  # Provide empty stdin to prevent hanging
                    )

                    if result.returncode == 0:
                        logging.info("✓ Claude Code execution successful")
                        return {
                            'success': True,
                            'output': result.stdout,
                            'error': '',
                            'model_used': 'claude'
                        }
                    else:
                        logging.warning(f"Claude Code failed (exit {result.returncode}), falling back to local LLM")
                        logging.debug(f"Claude stderr: {result.stderr[:200]}")

                except (subprocess.TimeoutExpired, FileNotFoundError) as e:
                    logging.warning(f"Claude Code unavailable: {e}, falling back to local LLM")

            # Fallback to local LLM
            logging.info("Using local LLM...")

            if self.local_llm is None:
                from gherkin_tracker.infrastructure.local_llm import LocalLLM
                self.local_llm = LocalLLM()

            # Generate using local model
            result = self.local_llm.generate(
                prompt,
                max_tokens=4096,
                temperature=0.1  # Low temperature for code generation
            )

            result['model_used'] = 'local'
            return result

        except Exception as e:
            logging.error(f"✗ LLM execution error: {e}")
            return {
                'success': False,
                'output': '',
                'error': str(e),
                'model_used': 'none'
            }

    def implement_bdd_step(self, task: Dict) -> Dict:
        """
        Use Claude Code to implement a BDD step definition
        """
        print(f"[{self.name}] Implementing BDD step with Claude Code...")

        step_type = task['step_type']
        step_text = task['step_text']
        feature_name = task['feature_name']
        scenario_name = task['scenario_name']

        config = self.current_project_config

        # Use project-specific template
        prompt = config.step_definition_template.format(
            feature_name=feature_name,
            scenario_name=scenario_name,
            step_type=step_type,
            step_text=step_text,
            test_directory=config.test_directory
        )

        result = self.run_claude(prompt)

        if result['success']:
            # Parse Claude's output to extract file location and method name
            bdd_file, method_name = self._parse_claude_output(
                result['output'],
                step_type,
                step_text,
                config
            )

            return {
                'success': True,
                'bdd_step_file': bdd_file,
                'bdd_method_name': method_name,
                'implementation_notes': 'Claude Code implemented BDD step definition',
                'output': result['output']
            }
        else:
            return {
                'success': False,
                'bdd_step_file': None,
                'bdd_method_name': None,
                'implementation_notes': f"Failed: {result['error']}",
                'output': result.get('error', 'Unknown error')
            }

    def implement_business_logic(self, task: Dict) -> Dict:
        """
        Use Claude Code to implement business logic (service/controller)
        """
        print(f"[{self.name}] Implementing business logic with Claude Code...")

        feature_name = task['feature_name']
        step_text = task['step_text']
        config = self.current_project_config

        # Use project-specific template
        prompt = config.service_template.format(
            feature_name=feature_name,
            step_text=step_text,
            implementation_directory=config.implementation_directory
        )

        result = self.run_claude(prompt)

        if result['success']:
            service_location = self._parse_service_location(
                result['output'],
                feature_name,
                config
            )

            return {
                'success': True,
                'service_location': service_location,
                'implementation_notes': 'Claude Code implemented business logic',
                'output': result['output']
            }
        else:
            return {
                'success': False,
                'service_location': None,
                'implementation_notes': f"Failed: {result['error']}",
                'output': result.get('error', 'Unknown error')
            }

    def run_tests(self, incremental_build: bool = True) -> Dict:
        """
        Run build and test commands based on project configuration
        """
        print(f"[{self.name}] Running build and tests...")

        config = self.current_project_config
        project_path = Path(config.path)

        # Build command with optional incremental build optimization
        build_cmd = config.build_command
        if incremental_build and config.language == 'csharp':
            # Add --no-restore for faster incremental builds
            build_cmd = build_cmd + " --no-restore"

        print(f"[{self.name}] Executing: {build_cmd}")
        build_result = subprocess.run(
            build_cmd.split(),
            capture_output=True,
            text=True,
            cwd=str(project_path)
        )

        build_succeeded = build_result.returncode == 0

        if not build_succeeded:
            return {
                'build_succeeded': False,
                'tests_passed': False,
                'output': f"Build failed:\n{build_result.stderr}"
            }

        # Run test command
        print(f"[{self.name}] Executing: {config.test_command}")
        test_result = subprocess.run(
            config.test_command.split(),
            capture_output=True,
            text=True,
            cwd=str(project_path)
        )

        tests_passed = test_result.returncode == 0

        output = f"Build: {'SUCCESS' if build_succeeded else 'FAILED'}\n"
        output += f"Tests: {'PASSED' if tests_passed else 'FAILED'}\n"
        output += f"\n{test_result.stdout}"

        return {
            'build_succeeded': build_succeeded,
            'tests_passed': tests_passed,
            'output': output
        }

    def complete_task(self, task_id: uuid.UUID, work_accomplished: str,
                      build_succeeded: bool, tests_passed: bool,
                      bdd_step_file: Optional[str] = None,
                      bdd_method_name: Optional[str] = None) -> bool:
        """Mark task as complete"""
        cursor = self.conn.cursor()
        try:
            cursor.execute(
                "SELECT * FROM sp_complete_task(%s, %s, %s, %s, %s, %s, %s)",
                (task_id, self.agent_id, work_accomplished, build_succeeded,
                 tests_passed, bdd_step_file, bdd_method_name)
            )
            self.conn.commit()
            cursor.close()

            status = 'COMPLETED' if (tests_passed and bdd_step_file) else 'FAILED'
            print(f"\n{'='*80}")
            print(f"[{self.name}] TASK {status}")
            print(f"{'='*80}\n")
            return True
        except Exception as e:
            self.conn.rollback()
            cursor.close()
            print(f"[{self.name}] Failed to complete task: {e}")
            return False

    def extract_domain_knowledge(self, feature_name: str, step_text: str, config: 'ProjectConfig') -> str:
        """
        Extract relevant domain knowledge from CLAUDE.md for this specific step.
        Returns a string with relevant entities, DTOs, and services.
        """
        project_path = Path(config.path)
        claude_md_path = project_path / "CLAUDE.md"

        if not claude_md_path.exists():
            return "No CLAUDE.md found - use your best judgment based on existing code."

        with open(claude_md_path, 'r', encoding='utf-8') as f:
            claude_md = f.read()

        # Extract relevant sections based on keywords from the step
        keywords = step_text.lower().split()
        relevant_sections = []

        # Look for entity definitions
        if 'medication' in step_text.lower():
            relevant_sections.append("RELEVANT ENTITIES: Medication, MedicationLog, Patient, User")
        if 'symptom' in step_text.lower():
            relevant_sections.append("RELEVANT ENTITIES: Symptom, SymptomLog, Patient")
        if 'behavior' in step_text.lower():
            relevant_sections.append("RELEVANT ENTITIES: Behavior, BehaviorLog, Patient")
        if 'offline' in step_text.lower() or 'sync' in step_text.lower():
            relevant_sections.append("RELEVANT ENTITIES: SyncQueue, OfflineData, Patient, User")
        if 'user' in step_text.lower() or 'login' in step_text.lower() or 'auth' in step_text.lower():
            relevant_sections.append("RELEVANT ENTITIES: User, Patient, CareTeam")

        if not relevant_sections:
            return "DOMAIN CONTEXT: Review existing entities in src/1-Core/CareSync.Domain/Entities/ before implementing."

        return "\n".join(relevant_sections)

    def check_missing_dependencies(self, step_text: str, config: 'ProjectConfig') -> Dict:
        """
        Check if entities/DTOs referenced in the step text actually exist in the codebase.
        Returns dict with 'missing' list and 'found' list.

        This method is project-agnostic - uses config.entity_path and config.entity_keywords
        """
        logging.debug(f"Checking for missing dependencies in step: {step_text[:100]}...")
        project_path = Path(config.path)

        # Get entity path from config (e.g., "src/Domain/Entities" or "lib/models")
        entities_path = project_path / getattr(config, 'entity_path', 'src/Domain/Entities')
        logging.debug(f"Entity path: {entities_path}")

        # Get entity keywords from config, or use common defaults
        # Format: {'keyword_in_text': 'EntityClassName'}
        default_keywords = {
            'medication': 'Medication',
            'symptom': 'Symptom',
            'behavior': 'Behavior',
            'user': 'User',
            'patient': 'Patient',
            'trial': 'Trial',
            'study': 'Study',
            'consent': 'Consent',
            'protocol': 'Protocol',
            'survey': 'Survey',
            'questionnaire': 'Questionnaire',
            'order': 'Order',
            'product': 'Product',
            'customer': 'Customer',
            'invoice': 'Invoice',
            'payment': 'Payment',
        }

        keywords = getattr(config, 'entity_keywords', default_keywords)

        missing = []
        found = []

        # Get file extension from config (e.g., ".cs", ".java", ".py")
        file_ext = getattr(config, 'entity_file_extension', '.cs')

        step_lower = step_text.lower()
        for keyword, entity_name in keywords.items():
            if keyword in step_lower:
                entity_file = entities_path / f"{entity_name}{file_ext}"
                if entity_file.exists():
                    found.append(entity_name)
                    logging.debug(f"✓ Found entity: {entity_name}")
                else:
                    missing.append(entity_name)
                    logging.warning(f"✗ Missing entity: {entity_name}")

        if missing:
            logging.warning(f"Pre-flight check: {len(missing)} missing entities: {', '.join(missing)}")
        else:
            logging.info(f"Pre-flight check: All required entities exist ({len(found)} found)")

        return {
            'missing': missing,
            'found': found
        }

    def create_missing_entity(self, entity_name: str, step_text: str, config: 'ProjectConfig') -> Dict:
        """
        Use Claude Code to create a missing entity based on step requirements.
        Project-agnostic - uses config to determine language, paths, and patterns.
        """
        print(f"[{self.name}] Creating missing entity: {entity_name}")
        logging.info(f"Creating missing entity: {entity_name} for step: {step_text[:80]}...")

        # Get project-specific paths and settings
        entity_path = getattr(config, 'entity_path', 'src/Domain/Entities')
        file_ext = getattr(config, 'entity_file_extension', '.cs')
        language = getattr(config, 'language', 'csharp')
        logging.debug(f"Entity creation config - path: {entity_path}, ext: {file_ext}, language: {language}")

        # Language-specific entity template guidance
        language_templates = {
            'csharp': """
LANGUAGE: C#
FILE EXTENSION: .cs
PATTERN: Use C# record type with init-only properties

EXAMPLE PATTERN:
```csharp
namespace MyProject.Domain.Entities;

/// <summary>
/// Represents a {entity_name} in the system.
/// </summary>
public record {entity_name}
{{
    public Guid Id {{ get; init; }}
    // Add domain-specific properties here
    public DateTime CreatedAt {{ get; init; }}
    public DateTime? UpdatedAt {{ get; set; }}
}}
```
""",
            'java': """
LANGUAGE: Java
FILE EXTENSION: .java
PATTERN: Use Java class with getters/setters or Java 17+ record

EXAMPLE PATTERN:
```java
package com.myproject.domain.entities;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Represents a {entity_name} in the system.
 */
public class {entity_name} {{
    private UUID id;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // Add domain-specific properties and methods
}}
```
""",
            'python': """
LANGUAGE: Python
FILE EXTENSION: .py
PATTERN: Use Python dataclass or Pydantic model

EXAMPLE PATTERN:
```python
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

@dataclass
class {entity_name}:
    \"\"\"Represents a {entity_name} in the system.\"\"\"
    id: UUID
    created_at: datetime
    updated_at: datetime | None = None

    # Add domain-specific properties
```
"""
        }

        lang_template = language_templates.get(language, language_templates['csharp'])

        prompt = f"""
You need to create a domain entity that is missing from the codebase.

ENTITY TO CREATE: {entity_name}
CONTEXT: This entity is needed for the Gherkin step: "{step_text}"

INSTRUCTIONS:
1. Look at existing entities in {entity_path}/ to understand the pattern
2. Create {entity_path}/{entity_name}{file_ext}
3. Follow the language-specific pattern below
4. Include essential properties based on the step requirements
5. Add proper documentation (XML doc, JavaDoc, or docstrings)
6. Follow existing naming conventions and patterns

{lang_template}

STEPS TO FOLLOW:
1. First, read 2-3 existing entity files from {entity_path}/ to understand the project's patterns
2. Note the common properties, namespaces/packages, imports, and documentation style
3. Create the new {entity_name} entity following those exact patterns
4. Include properties that make sense for {entity_name} based on:
   - The Gherkin step requirements
   - Common domain modeling practices
   - Existing entity patterns in this project

DO NOT:
- Use placeholder code or TODO comments
- Make up property names that don't fit the domain
- Skip documentation
- Deviate from the project's existing patterns

Create the entity file now.
"""

        result = self.run_claude(prompt)
        return result

    def implement_combined(self, task: Dict) -> Dict:
        """
        Use Claude Code to implement BOTH BDD step and business logic in one call.
        Includes pre-flight check for missing dependencies.
        """
        print(f"[{self.name}] Implementing BDD step AND business logic with Claude Code...")

        step_type = task['step_type']
        step_text = task['step_text']
        feature_name = task['feature_name']
        scenario_name = task['scenario_name']
        config = self.current_project_config

        # PRE-FLIGHT CHECK: Scan for missing dependencies
        print(f"[{self.name}] Pre-flight check: Scanning for missing dependencies...")
        dependencies = self.check_missing_dependencies(step_text, config)

        if dependencies['missing']:
            print(f"[{self.name}] Found missing entities: {', '.join(dependencies['missing'])}")
            for entity_name in dependencies['missing']:
                create_result = self.create_missing_entity(entity_name, step_text, config)
                if create_result['success']:
                    print(f"[{self.name}] ✓ Created {entity_name}")
                else:
                    print(f"[{self.name}] ✗ Failed to create {entity_name}: {create_result.get('error')}")
        else:
            print(f"[{self.name}] ✓ All dependencies found: {', '.join(dependencies['found']) if dependencies['found'] else 'none needed'}")

        # Extract domain knowledge for this step
        domain_knowledge = self.extract_domain_knowledge(feature_name, step_text, config)

        # Combined prompt for both BDD and business logic
        combined_prompt = f"""
╔═══════════════════════════════════════════════════════════════════════════════╗
║                        EXPLICIT IMPLEMENTATION INSTRUCTIONS                    ║
║                  (Read EVERY word before writing ANY code)                     ║
╚═══════════════════════════════════════════════════════════════════════════════╝

WHAT YOU ARE IMPLEMENTING:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You must implement this SINGLE, SPECIFIC Gherkin step:

Feature:  {feature_name}
Scenario: {scenario_name}
Step:     {step_type} {step_text}

THIS IS THE ONLY STEP YOU ARE IMPLEMENTING. NOT THE WHOLE FEATURE. NOT THE WHOLE SCENARIO.
JUST THIS ONE STEP. NOTHING MORE. NOTHING LESS.

DOMAIN KNOWLEDGE FOR THIS STEP:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{domain_knowledge}

BEFORE WRITING ANY CODE (MANDATORY DISCOVERY PHASE):
1. Look in src/1-Core/CareSync.Domain/Entities/ to see what entities exist
2. Look in src/2-Application/CareSync.Application/DTOs/ to see what DTOs exist
3. Look in src/3-Infrastructure/CareSync.Infrastructure/Services/ to see what services exist
4. Look in tests/CareSync.Specs/Steps/ to see if similar step definitions exist
5. Use EXISTING entities and properties - DO NOT make up property names

IF AN ENTITY/DTO IS MISSING:
- You MAY create it if it's clearly needed for this step
- Follow the existing patterns in the codebase
- Add proper XML documentation
- Use C# record types for entities and DTOs
- Include all necessary properties based on the step requirements

EXAMPLE:
If step says "database contains medications" but no Medication entity exists:
✅ CREATE: src/1-Core/CareSync.Domain/Entities/Medication.cs
✅ CREATE: The step definition that uses it
❌ DON'T: Create placeholder code or skip the entity

╔═══════════════════════════════════════════════════════════════════════════════╗
║                           WHAT YOU MUST CREATE                                 ║
╚═══════════════════════════════════════════════════════════════════════════════╝

MANDATORY:
1. A BDD STEP DEFINITION FILE (*.cs in {config.test_directory}/)

CONDITIONAL (depends on step type):
2. A SERVICE IMPLEMENTATION FILE (*.cs in {config.implementation_directory}/)
   - REQUIRED for "When" steps (actions that call business logic)
   - REQUIRED for "Then" steps that verify complex business rules
   - NOT REQUIRED for "Given" steps (test setup can use _context directly)

WHEN TO CREATE A SERVICE:
- "When user does X" → YES, create service method for the action
- "Then system should X" → MAYBE, if X is complex business logic
- "Given user has X" → NO, just seed test data in the step method

You MAY also need to:
- Update an EXISTING service interface (IXxxService.cs) if creating a new service method
- Update an EXISTING DTO if the step requires data transfer objects
- Create a NEW DTO ONLY if absolutely necessary for this specific step

DO NOT CREATE:
❌ Multiple new interfaces
❌ Comprehensive service interfaces with 8+ methods you don't need
❌ Multiple DTOs "just in case"
❌ Architecture or infrastructure code
❌ Base classes or abstract classes
❌ Helper utilities "that might be useful later"
❌ Configuration classes
❌ Factories or builders
❌ Any code that is not DIRECTLY required to make THIS SPECIFIC STEP execute

╔═══════════════════════════════════════════════════════════════════════════════╗
║                     PART 1: BDD STEP DEFINITION (MANDATORY)                    ║
╚═══════════════════════════════════════════════════════════════════════════════╝

FILE LOCATION: {config.test_directory}/[FeatureName]Steps.cs
EXAMPLE: tests/CareSync.Specs/Steps/OfflineCapabilitySteps.cs (for OfflineCapability feature)

MANDATORY STRUCTURE - Copy this pattern EXACTLY:

```csharp
#nullable enable
using CareSync.Application.Interfaces;  // For service interfaces
using CareSync.Infrastructure.Data;     // For DbContext
using FluentAssertions;                  // For assertions
using TechTalk.SpecFlow;                 // For [Binding] and step attributes
// Add other necessary using statements

namespace CareSync.Specs.Steps;

[Binding]
public class [FeatureName]Steps
{{
    private readonly ScenarioContext _scenarioContext;
    private readonly CareSyncDbContext _context;
    private readonly I[ServiceName]Service _service;

    // Store results from When steps to assert in Then steps
    private [ResultType]? _lastResult;
    private Exception? _caughtException;

    public [FeatureName]Steps(ScenarioContext scenarioContext)
    {{
        _scenarioContext = scenarioContext;

        // Setup DI container for testing
        ServiceProvider services = new ServiceCollection()
            .AddDbContext<CareSyncDbContext>(options =>
                options.UseInMemoryDatabase($"TestDb_{{Guid.NewGuid()}}"))
            .AddLogging()
            .AddScoped<I[ServiceName]Service, [ServiceName]Service>()
            .BuildServiceProvider();

        _context = services.GetRequiredService<CareSyncDbContext>();
        _service = services.GetRequiredService<I[ServiceName]Service>();
    }}

    [{step_type}(@"EXACT REGEX PATTERN FROM STEP TEXT")]
    public async Task MethodName([parameters from regex groups])
    {{
        // IMPLEMENT THE STEP HERE
        // For Given: Setup test data in _context or _scenarioContext
        // For When: Call _service.MethodAsync() and store result in _lastResult
        // For Then: Use FluentAssertions to assert _lastResult or _scenarioContext data

        // EXAMPLE PATTERNS:

        // Given example:
        // _scenarioContext["Key"] = value;

        // When example:
        // _lastResult = await _service.DoSomethingAsync(param1, param2);

        // Then example:
        // _lastResult.Should().NotBeNull();
        // _lastResult!.PropertyName.Should().Be(expectedValue);
    }}
}}
```

CRITICAL RULES FOR STEP DEFINITIONS:
1. The [{step_type}] attribute MUST have a regex pattern that EXACTLY matches "{step_text}"
2. Extract ANY numeric values, strings in quotes, or variable parts as parameters using regex groups
3. Method name should be descriptive: {step_type}[DescriptionFromStepText]
4. For Then steps: ALWAYS use FluentAssertions (.Should().Be(), .Should().NotBeNull(), etc.)
5. Use _scenarioContext to pass data between Given/When/Then steps
6. The step method MUST be async Task if it calls any async service methods
7. DO NOT create stub implementations - this must actually test something

╔═══════════════════════════════════════════════════════════════════════════════╗
║                   PART 2: SERVICE IMPLEMENTATION (MANDATORY)                   ║
╚═══════════════════════════════════════════════════════════════════════════════╝

FILE LOCATION: {config.implementation_directory}/Services/[ServiceName]Service.cs
EXAMPLE: src/3-Infrastructure/CareSync.Infrastructure/Services/OfflineCapabilityService.cs

MANDATORY STRUCTURE - Follow this pattern:

```csharp
using CareSync.Application.DTOs.[Category];  // For DTOs
using CareSync.Application.Interfaces;       // For service interface
using CareSync.Domain.Entities;              // For domain entities
using CareSync.Infrastructure.Data;          // For DbContext
using Microsoft.EntityFrameworkCore;         // For EF Core
using Microsoft.Extensions.Logging;          // For logging

namespace CareSync.Infrastructure.Services;

/// <summary>
/// Service for [brief description of what this service does]
/// Implements [requirement ID if known]
/// </summary>
public class [ServiceName]Service(
    CareSyncDbContext context,
    ILogger<[ServiceName]Service> logger
) : I[ServiceName]Service
{{
    // ONLY implement the methods needed for THIS STEP
    // Do NOT create 8 methods "just to be complete"

    /// <summary>
    /// [Description of what this method does]
    /// </summary>
    public async Task<[ReturnType]> MethodNameAsync(
        [parameters],
        CancellationToken cancellationToken = default)
    {{
        logger.LogInformation("Descriptive log message with {{Param}}", paramValue);

        try
        {{
            // ACTUAL IMPLEMENTATION HERE
            // Query the database using context
            // Perform business logic
            // Return the result

            // DO NOT USE:
            // - throw new NotImplementedException()
            // - return null! with no logic
            // - // TODO: implement this
            // - Placeholder comments

            return result;
        }}
        catch (Exception ex)
        {{
            logger.LogError(ex, "Error message describing what failed");
            throw;  // Or handle appropriately
        }}
    }}
}}
```

INTERFACE FILE: src/2-Application/CareSync.Application/Interfaces/I[ServiceName]Service.cs

```csharp
namespace CareSync.Application.Interfaces;

/// <summary>
/// Service interface for [description]
/// </summary>
public interface I[ServiceName]Service
{{
    /// <summary>
    /// [Method description]
    /// </summary>
    Task<[ReturnType]> MethodNameAsync([parameters], CancellationToken cancellationToken = default);
}}
```

CRITICAL RULES FOR SERVICES:
1. ONLY create methods that THIS SPECIFIC STEP needs
2. If the step says "should contain 600 entries", implement a method that counts entries
3. If the step says "should use less than 100MB", implement a method that calculates storage
4. DO NOT create methods for future steps you aren't implementing yet
5. Use primary constructor syntax: `public class MyService(Dep1 dep1, Dep2 dep2) : IMyService`
6. Always use ILogger for logging
7. Always use async/await for database operations
8. MUST return actual data, not placeholders

╔═══════════════════════════════════════════════════════════════════════════════╗
║                            DTOs (ONLY IF NEEDED)                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

ONLY create DTOs if the service method needs to return structured data.

FILE LOCATION: src/2-Application/CareSync.Application/DTOs/[Category]/[Name]Dto.cs

```csharp
namespace CareSync.Application.DTOs.[Category];

/// <summary>
/// Data transfer object for [description]
/// </summary>
public record [Name]Dto
{{
    /// <summary>
    /// [Property description]
    /// </summary>
    public [Type] PropertyName {{ get; set; }}
}}
```

RULES FOR DTOs:
1. ONLY create DTOs if your service method needs to return complex data
2. If returning a simple type (int, bool, string), DO NOT create a DTO
3. Use C# record types for DTOs
4. Keep DTOs minimal - only properties needed for THIS step
5. DO NOT create 4 different DTOs "just in case"

╔═══════════════════════════════════════════════════════════════════════════════╗
║                  LANGUAGE-SPECIFIC CODE QUALITY STANDARDS                      ║
╚═══════════════════════════════════════════════════════════════════════════════╝

C# SPECIFIC REQUIREMENTS:
✅ NO magic strings or magic numbers
   - Use existing enums if available (check the codebase first)
   - Create new enums or const fields if no suitable enum exists
   - Example: Use ConnectionType.WiFi instead of "WiFi"

✅ NO inline comments within methods
   - ONLY use XML documentation comments (///) above methods, classes, properties
   - XML docs must be comprehensive and describe purpose, parameters, returns
   - NO // comments inside method bodies

✅ Prefer primary constructors for services and classes
   - Example: public class MyService(IDep1 dep1, IDep2 dep2) : IMyService
   - Use record types for immutable data objects
   - Only use traditional classes with explicit constructors when mutability is required

✅ Comprehensive XML documentation
   - Every public member must have /// XML docs
   - Include <summary>, <param>, <returns>, <exception> tags as appropriate

✅ NEVER use 'object' type in C#
   - Always use specific types
   - Use generics when type varies: T instead of object
   - Example: List<T> instead of List<object>

✅ NO unused variables or parameters
   - Remove any variable declared but never used
   - Remove any method parameter that isn't referenced in the method body
   - Use _ discard if you must ignore a parameter: void Method(string needed, _ unused)

✅ Invert if statements to reduce nesting
   - Example WRONG: if (x != null) {{ DoSomething(); }}
   - Example RIGHT: if (x is null) return; DoSomething();
   - Use early returns to avoid deep nesting

✅ Use pattern matching instead of && operators
   - Example WRONG: if (obj != null && obj.Type == "Admin")
   - Example RIGHT: if (obj is {{ Type: "Admin" }})
   - Use property patterns and type patterns

✅ ALWAYS use await for async operations
   - Never use .Result or .Wait() on Task
   - Always use async/await pattern
   - Example: var result = await service.GetDataAsync();

✅ Make methods static when possible
   - If a method doesn't use instance members, make it static
   - Example: private static bool IsValid(string input) instead of private bool IsValid(string input)
   - Static methods are faster and clearer about dependencies

JAVA SPECIFIC REQUIREMENTS (if applicable):
✅ Use JavaDoc comments instead of XML docs
✅ Prefer immutable classes with builder pattern
✅ Use enums for constants
✅ NO magic strings or numbers

PYTHON SPECIFIC REQUIREMENTS (if applicable):
✅ Use docstrings (triple quotes) for all functions and classes
✅ Use Enums from enum module for constants
✅ Type hints on all function signatures
✅ NO magic strings or numbers - use constants or Enums

╔═══════════════════════════════════════════════════════════════════════════════╗
║                    ABSOLUTE PROHIBITIONS (ZERO TOLERANCE)                      ║
╚═══════════════════════════════════════════════════════════════════════════════╝

The following will cause IMMEDIATE FAILURE and require a complete rewrite:

⚠️  CRITICAL: Any comment suggesting the code is incomplete, temporary, or simulated is STRICTLY FORBIDDEN.
    Examples of FORBIDDEN comments:
    - "In production, this would..."
    - "For now, simulate..."
    - "This would normally..."
    - "Eventually this will..."
    - "Placeholder for..."

    These comments indicate you are NOT implementing the feature - you are faking it.
    IMPLEMENT THE ACTUAL FUNCTIONALITY. NO SIMULATIONS. NO PLACEHOLDERS.

❌ FORBIDDEN CODE PATTERNS:
   - throw new NotImplementedException()
   - // TODO: implement this
   - // Placeholder
   - // Stub
   - // Not implemented yet
   - // To be completed
   - // This should...
   - // In production, this would...
   - // For now, simulate...
   - // In a real implementation...
   - // This is a placeholder...
   - // Temporary implementation...
   - return null!; (with no logic above it)
   - Creating interfaces with 8+ methods when you only need 1
   - Creating 4+ DTOs when you only use 1
   - Removing existing code without replacement
   - Referencing properties/methods that don't exist in the codebase
   - Magic strings or magic numbers (use enums/constants instead)
   - Inline comments within methods (use XML doc comments only)
   - Classes when records or primary constructors would be better for immutable objects
   - Missing using statements
   - Compilation errors of ANY kind
   - Using 'object' type (use specific types or generics)
   - Unused variables or parameters in any method
   - Nested if statements (use early returns and guard clauses)
   - Using && with null checks (use pattern matching)
   - Using .Result or .Wait() on async Task (use await)
   - Non-static methods that don't use instance members

❌ FORBIDDEN ARCHITECTURAL PATTERNS:
   - Creating "comprehensive" service interfaces
   - Building infrastructure for future features
   - Creating base classes or abstract classes
   - Factory patterns for simple object creation
   - Repository patterns (use DbContext directly)
   - Creating multiple helper classes
   - Configuration builders
   - Custom exceptions (use built-in exceptions)

╔═══════════════════════════════════════════════════════════════════════════════╗
║                          STEP-BY-STEP PROCESS                                  ║
╚═══════════════════════════════════════════════════════════════════════════════╝

FOLLOW THIS EXACT SEQUENCE:

1. READ THE STEP TEXT CAREFULLY
   - What is it asking you to test?
   - Is it Given (setup), When (action), or Then (assertion)?
   - What data does it need?
   - What should it verify?

2. DETERMINE THE MINIMAL SERVICE METHOD NEEDED
   - What ONE method does this step require?
   - What should it return?
   - What parameters does it need?
   - Does it need a DTO or can it return a primitive?

3. CHECK IF SERVICE/INTERFACE ALREADY EXISTS
   - Search the codebase for existing services
   - Use existing services if they already do what you need
   - Only create a NEW service if no existing service fits

4. WRITE THE SERVICE METHOD FIRST
   - Implement the ACTUAL logic, not a stub
   - Use real database queries with EF Core
   - Return real data
   - Add proper error handling and logging

5. UPDATE/CREATE THE SERVICE INTERFACE
   - Add ONLY the method(s) you actually implemented
   - DO NOT add 7 other methods "for completeness"

6. WRITE THE BDD STEP DEFINITION
   - Create the step method with correct [{step_type}] attribute
   - Call the service method you just created
   - Store results in _lastResult or _scenarioContext
   - Add assertions for Then steps using FluentAssertions

7. VERIFY BEFORE RETURNING
   - Does the code compile?
   - Did you use correct property/method names from existing entities?
   - Did you add all necessary using statements?
   - Did you avoid ALL forbidden patterns?
   - Does the step method actually test something?

╔═══════════════════════════════════════════════════════════════════════════════╗
║                     CONCRETE EXAMPLE (DO EXACTLY THIS)                         ║
╚═══════════════════════════════════════════════════════════════════════════════╝

GIVEN THIS STEP:
"Then local database should contain all 600 entries"

CORRECT IMPLEMENTATION:

FILE 1: tests/CareSync.Specs/Steps/OfflineCapabilitySteps.cs
```csharp
#nullable enable
using CareSync.Application.Interfaces;
using CareSync.Infrastructure.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using TechTalk.SpecFlow;

namespace CareSync.Specs.Steps;

[Binding]
public class OfflineCapabilitySteps
{{
    private readonly ScenarioContext _scenarioContext;
    private readonly CareSyncDbContext _context;

    public OfflineCapabilitySteps(ScenarioContext scenarioContext)
    {{
        _scenarioContext = scenarioContext;
        ServiceProvider services = new ServiceCollection()
            .AddDbContext<CareSyncDbContext>(options =>
                options.UseInMemoryDatabase($"TestDb_{{Guid.NewGuid()}}"))
            .BuildServiceProvider();
        _context = services.GetRequiredService<CareSyncDbContext>();
    }}

    [Then(@"local database should contain all (\d+) entries")]
    public async Task ThenLocalDatabaseShouldContainAllEntries(int expectedCount)
    {{
        // Count all tracking entries in the local database
        int actualCount = await _context.SymptomLogs.CountAsync() +
                          await _context.MedicationLogs.CountAsync() +
                          await _context.BehaviorLogs.CountAsync();

        actualCount.Should().Be(expectedCount,
            $"local database should contain exactly {{expectedCount}} entries");
    }}
}}
```

THIS IS CORRECT BECAUSE:
✅ Creates only ONE step method (not a whole feature)
✅ Uses existing entities (SymptomLogs, MedicationLogs, etc.)
✅ Performs actual database query using EF Core
✅ Has proper FluentAssertions
✅ No placeholder code
✅ No unnecessary services or DTOs
✅ Actually tests what the step asks for

WRONG IMPLEMENTATION (DO NOT DO THIS):
```csharp
// ❌ Creates comprehensive interface
public interface IOfflineCapabilityService
{{
    Task<DataAccessibilityResult> CheckAccessibility(...);
    Task<IntegrityResult> VerifyIntegrity(...);
    Task<StorageStats> GetStats(...);
    Task<int> GetEntryCount(...);  // Only this is needed!
    // ... 4 more methods
}}

// ❌ Creates DTOs for methods not being implemented
public record DataAccessibilityResult {{ ... }}
public record IntegrityResult {{ ... }}
public record StorageStats {{ ... }}

// ❌ Step method doesn't test anything
[Then(@"local database should contain all (\d+) entries")]
public async Task ThenLocalDatabaseShouldContainAllEntries(int expectedCount)
{{
    // TODO: implement this
    throw new NotImplementedException();
}}
```

╔═══════════════════════════════════════════════════════════════════════════════╗
║                              FINAL CHECKLIST                                   ║
╚═══════════════════════════════════════════════════════════════════════════════╝

Before you return your implementation, verify ALL of these:

□ I created ONLY the files needed for THIS ONE STEP (not the whole feature)
□ The BDD step method has the correct [{step_type}] attribute matching the step text
□ The service method contains ACTUAL implementation (no TODOs or NotImplementedException)
□ I used existing domain entities and properties (didn't make up property names)
□ All using statements are included
□ The code compiles with ZERO errors
□ For Then steps: I used FluentAssertions for assertions
□ I did NOT create 8+ method interfaces when I only need 1 method
□ I did NOT create 4+ DTOs when I only need 0 or 1
□ The implementation actually does what the step text says
□ I verified property/method names exist in the codebase before using them

╔═══════════════════════════════════════════════════════════════════════════════╗
║                         NOW IMPLEMENT THE STEP                                 ║
╚═══════════════════════════════════════════════════════════════════════════════╝

Implement: {step_type} {step_text}

Return ONLY:
1. The file path(s) you created/modified
2. The step method name
3. The service method name (if you created one)
4. Brief description of what you implemented

DO NOT return explanations of what you "could" implement or what "should" be implemented next.
"""

        result = self.run_claude(combined_prompt)

        if result['success']:
            # Parse output for both BDD and service info
            bdd_file, method_name = self._parse_claude_output(
                result['output'],
                step_type,
                step_text,
                config
            )
            service_location = self._parse_service_location(
                result['output'],
                feature_name,
                config
            )

            return {
                'success': True,
                'bdd_step_file': bdd_file,
                'bdd_method_name': method_name,
                'service_location': service_location,
                'implementation_notes': 'Claude Code implemented BDD step and business logic',
                'output': result['output']
            }
        else:
            error_msg = result.get('error', 'Unknown error')
            print(f"[{self.name}] ERROR: Claude Code failed: {error_msg}")
            print(f"[{self.name}] Claude stdout: {result.get('output', 'No output')}")
            return {
                'success': False,
                'bdd_step_file': None,
                'bdd_method_name': None,
                'service_location': None,
                'implementation_notes': f"Failed: {error_msg}",
                'output': error_msg
            }

    def create_feature_branch(self, task: Dict) -> Dict:
        """
        Create a new git branch for implementing the task.
        Starts from the main branch to ensure clean state.
        Returns dict with 'success', 'branch_name', and optionally 'error'.
        """
        try:
            config = self.current_project_config
            project_path = config.path

            # SAFEGUARD: Check current branch to detect batch commit scenarios
            current_branch_result = subprocess.run(
                ['git', 'branch', '--show-current'],
                cwd=project_path,
                capture_output=True,
                text=True,
                check=True
            )
            current_branch = current_branch_result.stdout.strip()

            if current_branch.startswith('feat/bdd-') or current_branch.startswith('feature/BDD-'):
                logging.error(f"❌ SAFEGUARD TRIGGERED: Still on feature branch '{current_branch}'")
                logging.error(f"❌ Previous task may have failed to create PR")
                logging.error(f"❌ Refusing to reuse feature branch to prevent batch commits")
                raise RuntimeError(
                    f"Agent is still on feature branch '{current_branch}'. "
                    f"Each task must create its own branch and PR. "
                    f"Previous task likely failed PR creation. "
                    f"Manually checkout main and fix the issue."
                )

            # Stash any uncommitted changes first
            subprocess.run(['git', 'stash', 'push', '-m', 'Auto-stash before agent task'], cwd=project_path)

            # First, ensure we're starting from a clean state on main
            subprocess.run(['git', 'checkout', 'main'], cwd=project_path, check=True)
            subprocess.run(['git', 'pull'], cwd=project_path, check=True)

            # Generate branch name from task
            feature_slug = re.sub(r'[^a-z0-9]+', '-', task['feature_name'].lower()).strip('-')[:30]
            step_slug = re.sub(r'[^a-z0-9]+', '-', task['step_text'][:40].lower()).strip('-')
            branch_name = f"feat/bdd-{feature_slug}-{step_slug}"

            # Check if branch already exists
            result = subprocess.run(
                ['git', 'rev-parse', '--verify', branch_name],
                cwd=project_path,
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                # Branch exists, create unique name
                import random
                branch_name = f"{branch_name}-{random.randint(1000, 9999)}"

            # Create and checkout new branch
            subprocess.run(
                ['git', 'checkout', '-b', branch_name],
                cwd=project_path,
                check=True
            )

            # Store branch name in task for later use
            self.current_branch = branch_name

            return {
                'success': True,
                'branch_name': branch_name
            }

        except subprocess.CalledProcessError as e:
            return {
                'success': False,
                'error': f"Git command failed: {e.stderr if hasattr(e, 'stderr') else str(e)}"
            }
        except Exception as e:
            return {
                'success': False,
                'error': f"Unexpected error: {str(e)}"
            }

    def commit_and_create_pr(self, task: Dict) -> Dict:
        """
        Commit changes and create a PR for the completed task.
        Returns dict with 'success', 'pr_url', and optionally 'error'.
        """
        try:
            config = self.current_project_config
            project_path = config.path

            # Add all changes
            subprocess.run(
                ['git', 'add', '-A'],
                cwd=project_path,
                check=True
            )

            # Create commit message
            commit_msg = f"""feat(bdd): {task['step_type']} {task['step_text']}

Feature: {task['feature_name']}
Scenario: {task['scenario_name']}

Implemented by autonomous BDD agent.

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
"""

            # Commit changes
            subprocess.run(
                ['git', 'commit', '-m', commit_msg],
                cwd=project_path,
                check=True
            )

            # Push to remote
            branch_name = self.current_branch
            subprocess.run(
                ['git', 'push', '-u', 'origin', branch_name],
                cwd=project_path,
                check=True
            )

            # Create PR using gh CLI
            pr_title = f"feat(bdd): {task['step_type']} {task['step_text'][:60]}"
            pr_body = f"""## BDD Step Implementation

**Feature:** {task['feature_name']}
**Scenario:** {task['scenario_name']}
**Step:** {task['step_type']} {task['step_text']}

### Implementation Details

This PR implements the BDD step definition and any necessary business logic to make the step pass.

### Test Status

✅ Build passes
✅ No regressions detected

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
"""

            pr_result = subprocess.run(
                ['gh', 'pr', 'create',
                 '--title', pr_title,
                 '--body', pr_body,
                 '--label', 'agent-generated',
                 '--label', 'bdd'],
                cwd=project_path,
                capture_output=True,
                text=True,
                check=True
            )

            pr_url = pr_result.stdout.strip()

            return {
                'success': True,
                'pr_url': pr_url
            }

        except subprocess.CalledProcessError as e:
            return {
                'success': False,
                'error': f"Git command failed: {e.stderr if hasattr(e, 'stderr') else str(e)}"
            }
        except Exception as e:
            return {
                'success': False,
                'error': f"Unexpected error: {str(e)}"
            }

    def work_on_task(self, task: Dict, incremental_build: bool = True) -> bool:
        """Complete workflow for implementing a task with build verification and retry logic"""
        work_log = []
        start_time = time.time()
        max_fix_attempts = 2  # Allow up to 2 attempts to fix build errors

        logging.info("=" * 80)
        logging.info(f"WORKING ON TASK: {task.get('step_type')} {task.get('step_text')}")
        logging.info(f"Feature: {task.get('feature_name')} | Scenario: {task.get('scenario_name')}")
        logging.info(f"Project: {task.get('project_name')}")
        logging.info("=" * 80)

        # STEP 0: Create git branch before implementation
        print(f"\n{'='*80}")
        print(f"STEP 0: GIT BRANCH CREATION")
        print(f"{'='*80}")
        branch_result = self.create_feature_branch(task)
        if not branch_result['success']:
            logging.error(f"Failed to create branch: {branch_result.get('error')}")
            work_log.append(f"Branch creation failed: {branch_result.get('error')}")
            return self.complete_task(
                task['task_id'],
                '\n'.join(work_log),
                False, False, None, None
            )

        work_log.append(f"Created branch: {branch_result['branch_name']}")
        logging.info(f"✓ Created branch: {branch_result['branch_name']}")

        # OPTIMIZED: Single combined implementation instead of two separate calls
        print(f"\n{'='*80}")
        print(f"STEP 1: COMBINED IMPLEMENTATION (BDD + Business Logic)")
        print(f"{'='*80}")
        logging.info("STEP 1: Starting combined BDD + Business Logic implementation")
        combined_result = self.implement_combined(task)
        logging.debug(f"Combined implementation result: {combined_result.get('implementation_notes')}")
        work_log.append(f"Combined Implementation:")
        work_log.append(f"  {combined_result['implementation_notes']}")

        if combined_result.get('output'):
            work_log.append(f"  Output: {combined_result['output'][:200]}...")

        if not combined_result['success']:
            elapsed = time.time() - start_time
            work_log.append(f"\nFailed after {elapsed:.1f} seconds")
            return self.complete_task(
                task['task_id'],
                '\n'.join(work_log),
                False, False, None, None
            )

        # Step 2: Run tests with optional incremental build
        print(f"\n{'='*80}")
        print(f"STEP 2: BUILD & TEST{' (incremental)' if incremental_build else ''}")
        print(f"{'='*80}")
        logging.info(f"STEP 2: Running build and tests ({'incremental' if incremental_build else 'full build'})")
        test_result = self.run_tests(incremental_build=incremental_build)
        logging.info(f"Build result: {'SUCCESS' if test_result['build_succeeded'] else 'FAILED'}")
        logging.debug(f"Test output preview: {test_result['output'][:300]}")
        work_log.append(f"\nBuild & Test:")
        work_log.append(f"  {test_result['output'][:300]}")

        # Step 2.5: If build failed, try to fix it
        fix_attempt = 0
        while not test_result['build_succeeded'] and fix_attempt < max_fix_attempts:
            fix_attempt += 1
            print(f"\n{'='*80}")
            print(f"BUILD FAILED - ATTEMPTING FIX #{fix_attempt}/{max_fix_attempts}")
            print(f"{'='*80}")
            logging.warning(f"Build failed - attempting fix #{fix_attempt}/{max_fix_attempts}")

            # Extract only NEW build errors (not pre-existing Gherkin errors)
            build_errors = test_result.get('output', '')

            # Filter out pre-existing errors that aren't related to our changes
            if 'OfflineCapability.feature(60,5)' in build_errors:
                print(f"[{self.name}] Detected pre-existing Gherkin error - not attempting to fix")
                work_log.append(f"\n  Note: Build has pre-existing errors unrelated to this implementation")
                break

            # Check if error is due to missing type/entity
            import re
            missing_types = re.findall(r"error CS0246: The type or namespace name '(\w+)' could not be found", build_errors)
            missing_types.extend(re.findall(r"does not contain a definition for '(\w+)'", build_errors))

            if missing_types:
                print(f"[{self.name}] Detected missing types/properties: {', '.join(set(missing_types))}")
                logging.warning(f"Missing types detected: {', '.join(set(missing_types))}")
                work_log.append(f"\n  Missing types detected: {', '.join(set(missing_types))}")

                # Try to create missing entities
                for missing_type in set(missing_types):
                    # Check if it's an entity (capitalized, likely a class name)
                    if missing_type[0].isupper() and missing_type not in ['String', 'Int32', 'DateTime', 'Guid', 'Boolean']:
                        print(f"[{self.name}] Attempting to create missing entity: {missing_type}")
                        logging.info(f"Attempting to create missing entity: {missing_type}")
                        create_result = self.create_missing_entity(missing_type, task['step_text'], config)
                        if create_result['success']:
                            print(f"[{self.name}] ✓ Created {missing_type}")
                            logging.info(f"✓ Successfully created entity: {missing_type}")
                            work_log.append(f"  ✓ Created missing entity: {missing_type}")
                        else:
                            print(f"[{self.name}] ✗ Failed to create {missing_type}")
                            logging.error(f"✗ Failed to create entity: {missing_type}")

            # Ask Claude to fix the build errors
            fix_prompt = f"""
The code you just implemented has build errors. Please fix them immediately.

BUILD ERRORS:
{build_errors}

CRITICAL INSTRUCTIONS:
1. Review the error messages carefully
2. Fix ALL compilation errors
3. Ensure all property names, method names, and class names match existing code
4. Add any missing using statements
5. Do NOT add TODO comments or placeholder code
6. Do NOT remove code - only fix what's broken
7. The build MUST pass after your fixes

Review the existing codebase to understand the correct property/method names, then fix the errors.
"""

            print(f"[{self.name}] Asking Claude to fix build errors...")
            work_log.append(f"\nBuild Fix Attempt #{fix_attempt}:")

            fix_result = self.run_claude(fix_prompt)

            if not fix_result['success']:
                work_log.append(f"  Fix attempt failed: {fix_result.get('error', 'Unknown error')}")
                break

            work_log.append(f"  Claude attempted fixes")

            # Re-run build to check if fixes worked
            print(f"[{self.name}] Re-running build after fixes...")
            test_result = self.run_tests(incremental_build=incremental_build)
            work_log.append(f"  Re-build result: {'SUCCESS' if test_result['build_succeeded'] else 'FAILED'}")

            if test_result['build_succeeded']:
                print(f"[{self.name}] ✓ Build fixed successfully!")
                work_log.append(f"  ✓ Build now passing after {fix_attempt} attempt(s)")
                break
            else:
                print(f"[{self.name}] Build still failing, errors:")
                print(test_result.get('output', '')[:500])

        elapsed = time.time() - start_time
        work_log.append(f"\nCompleted in {elapsed:.1f} seconds")

        # Step 3: Determine success - build must pass, but we accept test failures for BDD
        # However, we need to ensure we didn't BREAK existing passing tests (regression detection)
        build_passed = test_result['build_succeeded']

        # Parse test output to detect regressions
        # A regression is when tests that were previously passing now fail
        has_regression = self._detect_test_regression(test_result.get('output', ''))

        if has_regression:
            logging.error("REGRESSION DETECTED: Previously passing tests are now failing!")
            work_log.append("\n⚠️  REGRESSION: Existing tests that were passing are now failing")
            task_success = False
        elif build_passed:
            # Build passed and no regression - task is successful
            # (New BDD test failures are expected and acceptable)
            task_success = True
            logging.info("✓ Task successful: Build passes, no regressions detected")
        else:
            # Build failed - task failed
            task_success = False
            logging.error("✗ Task failed: Build did not pass")

        # Step 4: Commit and create PR if successful
        # SAFEGUARD: ALWAYS create individual PRs, NEVER allow batch commits
        if task_success and build_passed:
            print(f"\n{'='*80}")
            print(f"STEP 3: GIT WORKFLOW (Commit + PR)")
            print(f"{'='*80}")
            logging.info("STEP 3: Committing changes and creating PR")

            git_result = self.commit_and_create_pr(task)
            if git_result['success']:
                logging.info(f"✓ Successfully created PR: {git_result.get('pr_url')}")
                work_log.append(f"\nGit Workflow:")
                work_log.append(f"  PR: {git_result.get('pr_url')}")
            else:
                # CRITICAL: If PR creation fails, this is a HARD ERROR
                # We do NOT want to continue with more tasks on the same branch
                logging.error(f"❌ CRITICAL: PR creation failed - {git_result.get('error')}")
                logging.error("❌ Stopping agent to prevent batch commits on single branch")
                work_log.append(f"\nGit Workflow: FAILED - {git_result.get('error')}")
                work_log.append(f"⚠️  Agent stopped to prevent batch commits")
                raise RuntimeError(f"PR creation failed: {git_result.get('error')}. "
                                 f"Each task MUST create an individual PR. "
                                 f"Check gh CLI auth: gh auth status")
        else:
            # Task failed - checkout main to ensure next task starts clean
            logging.warning("Task failed - ensuring clean state for next task")
            try:
                config = self.current_project_config
                subprocess.run(['git', 'checkout', 'main'], cwd=config.path, check=False)
            except Exception as e:
                logging.error(f"Failed to checkout main: {e}")

        return self.complete_task(
            task['task_id'],
            '\n'.join(work_log),
            build_passed,
            task_success,  # Task succeeds if build passes AND no regressions
            combined_result.get('bdd_step_file'),
            combined_result.get('bdd_method_name')
        )

    def _parse_claude_output(self, output: str, step_type: str, step_text: str, config: ProjectConfig) -> tuple:
        """Parse Claude's output to extract file path and method name"""
        # Language-specific parsing
        if config.language == 'csharp':
            # C# SpecFlow pattern
            file_match = re.search(r'(tests/[^/]+/StepDefinitions/\w+Steps\.cs)', output)
            if file_match:
                bdd_file = file_match.group(1)
            else:
                bdd_file = f"{config.test_directory}/GeneratedSteps.cs"

            method_match = re.search(rf'(?:public\s+)?(?:async\s+)?(?:Task\s+)?(\w+{step_type}\w+)\s*\(', output)
            if method_match:
                method_name = method_match.group(1)
            else:
                words = re.sub(r'[^a-zA-Z0-9]', ' ', step_text).split()
                method_name = step_type + ''.join(word.capitalize() for word in words[:5])

        elif config.language == 'cpp':
            # C++ Google Test pattern
            file_match = re.search(r'(tests/\w+_test\.cc)', output)
            if file_match:
                bdd_file = file_match.group(1)
            else:
                bdd_file = f"{config.test_directory}/generated_test.cc"

            test_match = re.search(r'TEST(?:_F)?\s*\(\s*\w+\s*,\s*(\w+)\s*\)', output)
            if test_match:
                method_name = test_match.group(1)
            else:
                words = re.sub(r'[^a-zA-Z0-9]', ' ', step_text).split()
                method_name = step_type + '_' + '_'.join(words[:5])

        elif config.language == 'python':
            # Python Behave pattern
            file_match = re.search(r'(features/steps/\w+_steps\.py)', output)
            if file_match:
                bdd_file = file_match.group(1)
            else:
                bdd_file = f"{config.test_directory}/generated_steps.py"

            func_match = re.search(rf'@{step_type.lower()}\s*\([^)]+\)\s*\ndef\s+(\w+)', output)
            if func_match:
                method_name = func_match.group(1)
            else:
                words = re.sub(r'[^a-zA-Z0-9]', ' ', step_text).split()
                method_name = step_type.lower() + '_' + '_'.join(words[:5])

        else:
            # Generic fallback
            bdd_file = f"{config.test_directory}/generated_test.{self._get_file_extension(config.language)}"
            words = re.sub(r'[^a-zA-Z0-9]', ' ', step_text).split()
            method_name = step_type + '_' + '_'.join(words[:5])

        return bdd_file, method_name

    def _parse_service_location(self, output: str, feature_name: str, config: ProjectConfig) -> str:
        """Parse service location from Claude's output"""
        # Language-specific parsing
        if config.language == 'csharp':
            service_match = re.search(r'(src/[^/]+/[^/]+/Services/\w+Service\.cs)', output)
            if service_match:
                return service_match.group(1)
            return f"{config.implementation_directory}/GeneratedService.cs"

        elif config.language == 'cpp':
            service_match = re.search(r'(src/\w+\.(cc|cpp|h|hpp))', output)
            if service_match:
                return service_match.group(1)
            return f"{config.implementation_directory}/generated_service.cc"

        elif config.language == 'python':
            service_match = re.search(r'(src/\w+\.py)', output)
            if service_match:
                return service_match.group(1)
            return f"{config.implementation_directory}/generated_service.py"

        return f"{config.implementation_directory}/generated_service"

    def _detect_test_regression(self, test_output: str) -> bool:
        """
        Detect if previously passing tests are now failing (regression).

        For BDD, we expect NEW tests to fail (missing steps), but we should
        NOT break existing passing tests.

        This is a heuristic - we look for tests that were passing before
        and are now failing due to our changes.
        """
        # For now, we'll use a simple heuristic:
        # If there are NO test failures, no regression
        # If there are test failures but they're all "No matching step definition" errors,
        # that's expected for BDD (new steps not yet implemented)
        # If there are test failures with actual exceptions or errors, that's a regression

        if not test_output:
            return False

        # Check for actual test failures (not just missing step definitions)
        regression_patterns = [
            r'Failed:.*\n.*Exception:',  # Actual exceptions
            r'Error:.*at ',  # Stack traces indicating real errors
            r'Expected.*but was',  # Assertion failures
            r'NullReferenceException',  # Null reference errors
            r'ArgumentException',  # Argument errors
            r'InvalidOperationException',  # Invalid operation errors
        ]

        for pattern in regression_patterns:
            if re.search(pattern, test_output):
                logging.warning(f"Potential regression detected: {pattern}")
                return True

        # No regressions detected
        return False

    def _get_file_extension(self, language: str) -> str:
        """Get file extension for language"""
        extensions = {
            'csharp': 'cs',
            'cpp': 'cc',
            'python': 'py',
            'java': 'java',
            'javascript': 'js',
            'typescript': 'ts'
        }
        return extensions.get(language, 'txt')


# Module-level worker function for multiprocessing (must be picklable)
def _parallel_worker(agent_id: str, agent_type: str, agent_num: int, completed_count, failed_count, max_tasks, project_filter: Optional[str], incremental_build: bool):
    """Worker process that runs one agent - must be at module level for pickling"""
    # Each process needs its own database connection
    worker_conn = psycopg2.connect(**DB_PARAMS)
    worker_conn.autocommit = False

    # Create config manager for this worker
    config_manager = ProjectConfigManager()

    agent = ClaudeCodeAgent(
        agent_id,
        agent_type,
        f"Claude-Agent-{agent_num}",
        worker_conn,
        config_manager,
        project_filter=project_filter
    )

    while True:
        # Check if we've hit max tasks
        current_total = completed_count.value + failed_count.value
        if max_tasks and current_total >= max_tasks:
            break

        task = agent.get_next_task()
        if not task:
            break

        if agent.assign_task(task['task_id']):
            success = agent.work_on_task(task, incremental_build=incremental_build)
            if success:
                cursor = worker_conn.cursor(cursor_factory=RealDictCursor)
                cursor.execute("SELECT status FROM task WHERE id = %s", (task['task_id'],))
                status = cursor.fetchone()['status']
                cursor.close()

                if status == 'Completed':
                    completed_count.value += 1
                else:
                    failed_count.value += 1
            else:
                failed_count.value += 1

            print(f"\n[Agent-{agent_num}] Progress: {completed_count.value} completed | {failed_count.value} failed\n")

    worker_conn.close()


class ClaudeOrchestrator:
    """Orchestrator for Claude Code agents"""

    def __init__(self, config_manager: ProjectConfigManager = None, project_filter: Optional[str] = None):
        self.conn = None
        self.agents = []
        self.config_manager = config_manager or ProjectConfigManager()
        self.project_filter = project_filter
        # Optimization flags
        self.num_parallel = 1
        self.incremental_build = True
        self.tasks_processed = 0

    def connect(self):
        """Connect to database"""
        try:
            self.conn = psycopg2.connect(**DB_PARAMS)
            self.conn.autocommit = False
            print(f"✓ Connected to database: {DB_PARAMS['dbname']}")
            print(f"✓ Loaded {len(self.config_manager.list_projects())} project configurations\n")
        except Exception as e:
            print(f"✗ Database connection failed: {e}")
            sys.exit(1)

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()

    def create_agent(self, agent_type: str = 'BDD_IMPLEMENTER',
                     name: Optional[str] = None) -> ClaudeCodeAgent:
        """Create a new Claude Code agent"""
        cursor = self.conn.cursor(cursor_factory=RealDictCursor)

        agent_name = name or f"Claude-Agent-{len(self.agents) + 1}"
        agent_id = uuid.uuid4()

        cursor.execute(
            """INSERT INTO agent (id, agent_name, agent_type, status, created_at, updated_at)
               VALUES (%s, %s, %s, 'Idle', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
               RETURNING id""",
            (agent_id, agent_name, agent_type)
        )

        result = cursor.fetchone()
        self.conn.commit()
        cursor.close()

        use_local_llm = os.getenv('USE_LOCAL_LLM', 'false').lower() in ['true', '1', 'yes']
        agent = ClaudeCodeAgent(agent_id, agent_type, agent_name, self.conn, self.config_manager, self.project_filter, use_local_llm)
        self.agents.append(agent)

        print(f"✓ Created Claude Code agent: {agent_name}\n")
        return agent

    def run(self, max_tasks: Optional[int] = None):
        """Run agent to process tasks"""
        print(f"\n{'='*80}")
        print("CLAUDE CODE AGENT SYSTEM - STARTING")
        print(f"{'='*80}\n")

        if not self.agents:
            self.create_agent()

        agent = self.agents[0]
        tasks_completed = 0
        tasks_failed = 0

        while True:
            if max_tasks and (tasks_completed + tasks_failed) >= max_tasks:
                print(f"\n✓ Reached maximum task limit: {max_tasks}")
                break

            task = agent.get_next_task()
            if not task:
                break

            if agent.assign_task(task['task_id']):
                success = agent.work_on_task(task, incremental_build=self.incremental_build)
                if success:
                    # Check if actually completed or failed
                    cursor = self.conn.cursor(cursor_factory=RealDictCursor)
                    cursor.execute("SELECT status FROM task WHERE id = %s", (task['task_id'],))
                    status = cursor.fetchone()['status']
                    cursor.close()

                    if status == 'Completed':
                        tasks_completed += 1
                    else:
                        tasks_failed += 1
                else:
                    tasks_failed += 1

                print(f"\n{'='*80}")
                print(f"PROGRESS: {tasks_completed} completed | {tasks_failed} failed")
                print(f"{'='*80}\n")

        self.print_statistics()

    def run_parallel(self, num_agents: int = 4, max_tasks: Optional[int] = None):
        """
        Run multiple agents in parallel using multiprocessing
        """
        import multiprocessing as mp
        from multiprocessing import Process, Queue, Manager

        print(f"\n{'='*80}")
        print(f"CLAUDE CODE AGENT SYSTEM - PARALLEL EXECUTION ({num_agents} agents)")
        print(f"{'='*80}\n")

        # Create agents
        while len(self.agents) < num_agents:
            self.create_agent()

        # Shared counters for progress tracking
        manager = Manager()
        completed_count = manager.Value('i', 0)
        failed_count = manager.Value('i', 0)

        # Start worker processes using module-level function
        processes = []
        for i in range(num_agents):
            p = Process(
                target=_parallel_worker,
                args=(
                    self.agents[i].agent_id,
                    self.agents[i].agent_type,
                    i + 1,
                    completed_count,
                    failed_count,
                    max_tasks,
                    self.project_filter,
                    self.incremental_build
                )
            )
            p.start()
            processes.append(p)

        # Wait for all processes to complete
        for p in processes:
            p.join()

        print(f"\n{'='*80}")
        print("PARALLEL EXECUTION COMPLETE")
        print(f"{'='*80}")
        print(f"Final: {completed_count.value} completed | {failed_count.value} failed")
        print(f"{'='*80}\n")

        self.print_statistics()

    def print_statistics(self):
        """Print statistics (filtered by project if project_filter is set)"""
        cursor = self.conn.cursor(cursor_factory=RealDictCursor)

        if self.project_filter:
            # Filter by specific project
            cursor.execute("""
                SELECT
                    COUNT(*) FILTER (WHERE t.status = 'Completed') as completed,
                    COUNT(*) FILTER (WHERE t.status = 'Pending') as pending,
                    COUNT(*) FILTER (WHERE t.status = 'Failed') as failed,
                    COUNT(*) FILTER (WHERE t.bdd_implemented = TRUE AND t.business_logic_implemented = TRUE) as fully_implemented,
                    COUNT(*) as total
                FROM task t
                JOIN step s ON t.step_id = s.id
                JOIN scenario_step ss ON ss.step_id = s.id
                JOIN scenario sc ON ss.scenario_id = sc.id
                JOIN feature f ON sc.feature_id = f.id
                JOIN project p ON f.project_id = p.id
                WHERE p.name = %s
            """, (self.project_filter,))
        else:
            # Global statistics across all projects
            cursor.execute("""
                SELECT
                    COUNT(*) FILTER (WHERE status = 'Completed') as completed,
                    COUNT(*) FILTER (WHERE status = 'Pending') as pending,
                    COUNT(*) FILTER (WHERE status = 'Failed') as failed,
                    COUNT(*) FILTER (WHERE bdd_implemented = TRUE AND business_logic_implemented = TRUE) as fully_implemented,
                    COUNT(*) as total
                FROM task
            """)

        stats = dict(cursor.fetchone())
        cursor.close()

        print(f"\n{'='*80}")
        if self.project_filter:
            print(f"FINAL STATISTICS - {self.project_filter}")
        else:
            print("FINAL STATISTICS - ALL PROJECTS")
        print(f"{'='*80}")
        print(f"Total tasks:        {stats['total']:,}")
        print(f"Completed:          {stats['completed']:,} ({stats['completed']/stats['total']*100:.1f}%)")
        print(f"Failed:             {stats['failed']:,} ({stats['failed']/stats['total']*100:.1f}%)")
        print(f"Pending:            {stats['pending']:,} ({stats['pending']/stats['total']*100:.1f}%)")
        print(f"Fully implemented:  {stats['fully_implemented']:,} ({stats['fully_implemented']/stats['total']*100:.1f}%)")
        print(f"{'='*80}\n")


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='Claude Code BDD Agent System - Multi-Project Support')
    parser.add_argument('--max-tasks', type=int, default=None,
                       help='Maximum number of tasks to process')
    parser.add_argument('--project', type=str, default=None,
                       help='Specific project to process (default: process all)')
    parser.add_argument('--parallel', type=int, default=1,
                       help='Number of parallel agents to run (e.g., --parallel 4)')
    parser.add_argument('--no-incremental-build', dest='incremental_build', action='store_false', default=True,
                       help='Disable incremental builds (run full dotnet restore each time)')
    parser.add_argument('--use-local-llm', action='store_true',
                       help='Use local LLM instead of Claude Code (requires setup via setup_local_llm.sh)')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging (DEBUG level)')
    parser.add_argument('--log-file', type=str, default=None,
                       help='Path to log file (default: no file logging)')
    args = parser.parse_args()

    # Setup logging if requested
    if args.verbose or args.log_file:
        setup_logging(log_file=args.log_file, verbose=args.verbose)
        logging.info(f"Starting Claude Code BDD Agent System")
        logging.info(f"Config: max_tasks={args.max_tasks}, project={args.project}, parallel={args.parallel}")
        logging.info(f"Logging: verbose={args.verbose}, log_file={args.log_file}")

    # Load project configurations
    config_manager = ProjectConfigManager()

    if len(config_manager.list_projects()) == 0:
        print("No project configurations found. Creating default configuration...")
        logging.warning("No project configurations found - creating defaults")
        from gherkin_tracker.domain.project_config import create_default_configs
        config_manager = create_default_configs()
    else:
        logging.info(f"Loaded {len(config_manager.list_projects())} project configurations")

    # Set environment variable for local LLM if requested
    if args.use_local_llm:
        os.environ['USE_LOCAL_LLM'] = '1'
        logging.info("Using local LLM (fallback from Claude Code)")

    orchestrator = ClaudeOrchestrator(config_manager, project_filter=args.project)
    orchestrator.connect()

    # Pass optimization flags to orchestrator
    orchestrator.num_parallel = args.parallel
    orchestrator.incremental_build = args.incremental_build

    try:
        if args.parallel > 1:
            orchestrator.run_parallel(num_agents=args.parallel, max_tasks=args.max_tasks)
        else:
            orchestrator.run(max_tasks=args.max_tasks)
    finally:
        orchestrator.close()


if __name__ == '__main__':
    main()
