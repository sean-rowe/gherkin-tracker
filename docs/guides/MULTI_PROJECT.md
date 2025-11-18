# Multi-Project Support

The Claude Code agent system now supports multiple projects in different languages and testing frameworks.

## Overview

The agent system is no longer limited to C# and SpecFlow. You can now use it with:
- **C#** with SpecFlow
- **C++** with Google Test
- **Python** with Behave
- Any other language/framework combination (with custom configuration)

## Project Configuration

Projects are configured in `~/projects/gherkin-tracker/projects.json`. Each project defines:

- `name`: Project identifier
- `path`: Absolute path to project directory
- `language`: Programming language (csharp, cpp, python, etc.)
- `test_framework`: BDD framework (specflow, googletest, behave, etc.)
- `build_command`: Command to build the project
- `test_command`: Command to run tests
- `test_directory`: Where BDD test files are located
- `implementation_directory`: Where implementation files go
- `step_definition_template`: Claude prompt template for BDD steps
- `service_template`: Claude prompt template for business logic

## Adding a New Project

### Method 1: Edit projects.json

```json
{
  "MyProject": {
    "name": "MyProject",
    "path": "/path/to/myproject",
    "language": "cpp",
    "test_framework": "googletest",
    "build_command": "cmake --build build",
    "test_command": "ctest --test-dir build",
    "test_file_pattern": "*_test.cc",
    "test_directory": "tests",
    "implementation_directory": "src",
    "step_definition_template": "...",
    "service_template": "..."
  }
}
```

### Method 2: Use Python API

```python
from project_config import ProjectConfigManager, ProjectConfig, PREDEFINED_CONFIGS

manager = ProjectConfigManager()

# Use a predefined config
cpp_config = PREDEFINED_CONFIGS['cpp_googletest']
cpp_config.name = 'MyProject'
cpp_config.path = '/path/to/myproject'
manager.add_project(cpp_config)

# Or create custom config
custom_config = ProjectConfig(
    name='CustomProject',
    path='/path/to/project',
    language='java',
    test_framework='cucumber',
    build_command='mvn compile',
    test_command='mvn test',
    test_file_pattern='*Steps.java',
    test_directory='src/test/java/steps',
    implementation_directory='src/main/java',
    step_definition_template='...',
    service_template='...'
)
manager.add_project(custom_config)
```

## Database Setup for New Project

After adding a project configuration, import its Gherkin features into the database:

```bash
cd ~/projects/gherkin-tracker

# Import features for the new project
python3 import_gherkin.py MyProject /path/to/myproject/features

# Verify import
python3 agent_system.py stats
```

Update the project record in the database:

```sql
UPDATE project
SET
    project_path = '/path/to/myproject',
    language = 'cpp',
    test_framework = 'googletest'
WHERE name = 'MyProject';
```

## Running the Agent

The agent automatically uses the correct configuration for each task based on the project:

```bash
# Process tasks from all projects
python3 agent_claude.py --max-tasks 5

# Process tasks from a specific project (future enhancement)
python3 agent_claude.py --project MyProject --max-tasks 5
```

## How It Works

1. **Agent gets next task**: Includes project info (name, path, language, framework)
2. **Loads project config**: Looks up configuration from projects.json
3. **Generates prompts**: Uses language-specific templates
4. **Runs Claude Code**: Executes in the project directory
5. **Parses output**: Uses language-specific patterns to extract file names
6. **Runs build/test**: Uses project-specific commands
7. **Updates database**: Records implementation details

## Language-Specific Features

### C# / SpecFlow

**Test Pattern**: `*Steps.cs` in `tests/CareSync.Specs/StepDefinitions/`

```csharp
[Given(@"user ""(.*)"" exists")]
public void GivenUserExists(string userName)
{
    // Implementation
}
```

**Build**: `dotnet build`
**Test**: `dotnet test --no-build`

### C++ / Google Test

**Test Pattern**: `*_test.cc` in `tests/`

```cpp
TEST_F(UserTest, UserExists) {
    // Given user "john" exists
    User user("john");

    // Then
    EXPECT_TRUE(user.Exists());
}
```

**Build**: `cmake --build build`
**Test**: `ctest --test-dir build`

### Python / Behave

**Test Pattern**: `*_steps.py` in `features/steps/`

```python
@given('user "{username}" exists')
def step_impl(context, username):
    # Implementation
    context.user = User(username)
    assert context.user.exists()
```

**Build**: `python -m pip install -e .`
**Test**: `behave`

## Prompt Templates

Each language has customized Claude Code prompts. Example for C++:

```python
step_definition_template = '''
Implement a Google Test BDD-style test for this Gherkin step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Requirements:
1. Create or update the test file in {test_directory}/
2. Use Google Test TEST_F or TEST macro
3. Implement the test with REAL code (not placeholders)
4. Use descriptive test names that match the Gherkin step
5. Add proper assertions using EXPECT_* or ASSERT_* macros
6. Follow the Given-When-Then pattern in test structure

IMPORTANT:
- NO placeholder code
- Production-ready implementation
- Include proper setup and teardown
'''
```

## Supported Predefined Configurations

The system includes predefined configurations for:

1. **csharp_specflow** - C# with SpecFlow (.NET)
2. **cpp_googletest** - C++ with Google Test
3. **python_behave** - Python with Behave

See `project_config.py` for full templates.

## Extending to New Languages

To add support for a new language:

1. Create a `ProjectConfig` with appropriate settings
2. Define `step_definition_template` for BDD step generation
3. Define `service_template` for business logic generation
4. Specify `build_command` and `test_command`
5. Update `_parse_claude_output()` in `agent_claude.py` if needed for language-specific parsing

## Example: Adding Java/Cucumber Support

```python
java_cucumber_config = ProjectConfig(
    name='JavaProject',
    path='/path/to/java/project',
    language='java',
    test_framework='cucumber',
    build_command='mvn compile',
    test_command='mvn test',
    test_file_pattern='*Steps.java',
    test_directory='src/test/java/steps',
    implementation_directory='src/main/java/services',
    step_definition_template='''
Implement a Cucumber step definition for this Gherkin step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Requirements:
1. Create or update the step definition class in {test_directory}/
2. Use the appropriate @{step_type} annotation
3. Implement with REAL code (no TODOs)
4. Use JUnit assertions
5. Follow existing patterns

IMPORTANT:
- Production-ready code only
- Include proper error handling
''',
    service_template='''
Implement the business logic for this feature step:

Feature: {feature_name}
Step: {step_text}

Requirements:
1. Create/update service class in {implementation_directory}/
2. REAL implementation (no placeholders)
3. Add proper error handling
4. Use Spring dependency injection
5. Add JavaDoc comments

IMPORTANT:
- Production-ready code only
'''
)
```

## Current Status

- **CareSync (C#/SpecFlow)**: Fully configured with 102 features, 1,895 scenarios, 11,692 steps
- Ready to add C++ projects
- Ready to add Python projects
- Extensible to any language

## Files

- `project_config.py` - Project configuration manager
- `projects.json` - Project configurations
- `agent_claude.py` - Multi-project agent implementation
- `scripts/04-add-project-support.sql` - Database migration
