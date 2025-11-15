#!/usr/bin/env python3
"""
Project Configuration System
Defines project-specific settings for BDD implementation
"""

import json
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict


@dataclass
class ProjectConfig:
    """Configuration for a project"""
    name: str
    path: str
    language: str
    test_framework: str
    build_command: str
    test_command: str
    test_file_pattern: str
    test_directory: str
    implementation_directory: str
    step_definition_template: str
    service_template: str
    entity_path: Optional[str] = None
    entity_file_extension: Optional[str] = None
    entity_keywords: Optional[Dict[str, str]] = None

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict) -> 'ProjectConfig':
        """Create from dictionary"""
        return cls(**data)


class ProjectConfigManager:
    """Manages project configurations"""

    def __init__(self, config_file: str = None):
        if config_file is None:
            config_file = str(Path.home() / 'projects' / 'gherkin-tracker' / 'projects.json')
        self.config_file = Path(config_file)
        self.projects: Dict[str, ProjectConfig] = {}
        self._load_configs()

    def _load_configs(self):
        """Load project configurations from file"""
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                data = json.load(f)
                for name, config_data in data.items():
                    self.projects[name] = ProjectConfig.from_dict(config_data)

    def save_configs(self):
        """Save project configurations to file"""
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        data = {name: config.to_dict() for name, config in self.projects.items()}
        with open(self.config_file, 'w') as f:
            json.dump(data, f, indent=2)

    def add_project(self, config: ProjectConfig):
        """Add a project configuration"""
        self.projects[config.name] = config
        self.save_configs()

    def get_project(self, name: str) -> Optional[ProjectConfig]:
        """Get a project configuration by name"""
        return self.projects.get(name)

    def list_projects(self) -> List[str]:
        """List all project names"""
        return list(self.projects.keys())


# Predefined project configurations
PREDEFINED_CONFIGS = {
    'csharp_specflow': ProjectConfig(
        name='CareSync',
        path='/Users/srowe/RiderProjects/caresync',
        language='csharp',
        test_framework='specflow',
        build_command='dotnet build',
        test_command='dotnet test --no-build',
        test_file_pattern='*Steps.cs',
        test_directory='tests/CareSync.Specs/StepDefinitions',
        implementation_directory='src/3-Infrastructure/CareSync.Infrastructure/Services',
        step_definition_template='''
Implement a SpecFlow BDD step definition for this Gherkin step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Requirements:
1. Create or update the step definition file in {test_directory}/
2. Use the appropriate [{step_type}] attribute with the step text pattern
3. Implement the step method with REAL code (not placeholders or TODO comments)
4. Call the appropriate service methods
5. Add proper assertions for Then steps using FluentAssertions
6. Handle parameters correctly (extract from step text using regex groups)
7. Use dependency injection to get services from _serviceProvider
8. Follow existing code patterns in the codebase

IMPORTANT:
- NO placeholder code like "// TODO" or "throw new NotImplementedException()"
- This must be production-ready implementation
- Include proper error handling
- Add XML documentation comments
''',
        service_template='''
Implement the business logic required for this feature step:

Feature: {feature_name}
Step: {step_text}

Requirements:
1. Identify or create the appropriate service class in {implementation_directory}/
2. Implement the necessary business logic method
3. Use REAL implementation (no placeholders, no NotImplementedException)
4. Add proper error handling and validation
5. Add logging using ILogger
6. Follow Clean Architecture and DDD principles
7. Update the service interface if needed
8. Add XML documentation comments

IMPORTANT:
- Production-ready code only
- Follow existing patterns in the codebase
- Use proper dependency injection
- Include unit tests if appropriate
'''
    ),

    'cpp_googletest': ProjectConfig(
        name='CppProject',
        path='/path/to/cpp/project',
        language='cpp',
        test_framework='googletest',
        build_command='cmake --build build',
        test_command='ctest --test-dir build',
        test_file_pattern='*_test.cc',
        test_directory='tests',
        implementation_directory='src',
        step_definition_template='''
Implement a Google Test BDD-style test for this Gherkin step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Requirements:
1. Create or update the test file in {test_directory}/
2. Use Google Test TEST_F or TEST macro
3. Implement the test with REAL code (not placeholders or TODO comments)
4. Use descriptive test names that match the Gherkin step
5. Add proper assertions using EXPECT_* or ASSERT_* macros
6. Follow the Given-When-Then pattern in test structure
7. Follow existing code patterns in the codebase

IMPORTANT:
- NO placeholder code like "// TODO" or "FAIL() << 'Not implemented'"
- This must be production-ready implementation
- Include proper setup and teardown
- Add comments explaining the test logic
''',
        service_template='''
Implement the business logic required for this feature step:

Feature: {feature_name}
Step: {step_text}

Requirements:
1. Identify or create the appropriate class in {implementation_directory}/
2. Implement the necessary business logic method
3. Use REAL implementation (no placeholders, no TODOs)
4. Add proper error handling and validation
5. Follow SOLID principles and existing code patterns
6. Update header files if needed
7. Add documentation comments

IMPORTANT:
- Production-ready code only
- Follow existing patterns in the codebase
- Use proper encapsulation
- Consider const-correctness and RAII
'''
    ),

    'python_behave': ProjectConfig(
        name='PythonProject',
        path='/path/to/python/project',
        language='python',
        test_framework='behave',
        build_command='python -m pip install -e .',
        test_command='behave',
        test_file_pattern='*_steps.py',
        test_directory='features/steps',
        implementation_directory='src',
        step_definition_template='''
Implement a Behave BDD step definition for this Gherkin step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Requirements:
1. Create or update the step definition file in {test_directory}/
2. Use the appropriate @{step_type} decorator with the step text pattern
3. Implement the step function with REAL code (not placeholders or pass statements)
4. Call the appropriate service/class methods
5. Add proper assertions for Then steps
6. Handle parameters correctly (use named groups in regex)
7. Access the context object for sharing state
8. Follow existing code patterns in the codebase

IMPORTANT:
- NO placeholder code like "# TODO" or "pass"
- This must be production-ready implementation
- Include proper error handling
- Add docstrings
''',
        service_template='''
Implement the business logic required for this feature step:

Feature: {feature_name}
Step: {step_text}

Requirements:
1. Identify or create the appropriate class/module in {implementation_directory}/
2. Implement the necessary business logic method
3. Use REAL implementation (no placeholders, no TODOs)
4. Add proper error handling and validation
5. Add logging if appropriate
6. Follow best practices and existing code patterns
7. Add type hints
8. Add docstrings

IMPORTANT:
- Production-ready code only
- Follow existing patterns in the codebase
- Use proper encapsulation
- Include unit tests if appropriate
'''
    )
}


def create_default_configs():
    """Create default project configurations"""
    manager = ProjectConfigManager()

    # Add CareSync C# project
    caresync_config = PREDEFINED_CONFIGS['csharp_specflow']
    manager.add_project(caresync_config)

    print(f"✓ Created default project configurations")
    print(f"  Config file: {manager.config_file}")
    print(f"  Projects: {', '.join(manager.list_projects())}")

    return manager


if __name__ == '__main__':
    # Create default configurations
    create_default_configs()
