# Gherkin Parser Integration

## Official Gherkin Parser

The gherkin-tracker system uses the official Cucumber Gherkin parser for Python.

### Installation

```bash
pip install gherkin-official
```

### Usage

```python
from gherkin.parser import Parser
from gherkin.token_scanner import TokenScanner

# Parse a feature file
parser = Parser()
feature_file_content = open('path/to/feature.feature', 'r').read()
token_scanner = TokenScanner(feature_file_content)

try:
    gherkin_document = parser.parse(token_scanner)
    
    # Access parsed elements
    feature = gherkin_document['feature']
    print(f"Feature: {feature['name']}")
    
    for child in feature['children']:
        if 'scenario' in child:
            scenario = child['scenario']
            print(f"  Scenario: {scenario['name']}")
            
            for step in scenario['steps']:
                print(f"    {step['keyword']}{step['text']}")
                
except Exception as e:
    print(f"Parse error: {e}")
```

### Parsing Feature Files to Database

```python
def parse_feature_to_tasks(feature_file_path, project_id):
    """
    Parse a Gherkin feature file and create implementation tasks.
    
    Returns:
        List of task dictionaries with dependencies
    """
    with open(feature_file_path, 'r') as f:
        content = f.read()
    
    parser = Parser()
    scanner = TokenScanner(content)
    gherkin_doc = parser.parse(scanner)
    
    feature = gherkin_doc['feature']
    tasks = []
    task_dependencies = []
    
    for child in feature['children']:
        if 'scenario' in child:
            scenario = child['scenario']
            scenario_tasks = []
            
            for i, step in enumerate(scenario['steps']):
                task = {
                    'feature_name': feature['name'],
                    'scenario_name': scenario['name'],
                    'step_type': step['keyword'].strip(),  # Given, When, Then
                    'step_text': step['text'],
                    'execution_order': i,
                    'status': 'pending'
                }
                
                tasks.append(task)
                scenario_tasks.append(task)
                
                # Create dependencies based on step order
                if i > 0:
                    # This step depends on the previous step
                    dependency = {
                        'task': task,
                        'depends_on': scenario_tasks[i-1],
                        'dependency_type': 'Required',
                        'reason': f"{task['step_type']} step depends on previous step in scenario"
                    }
                    task_dependencies.append(dependency)
    
    return tasks, task_dependencies
```

### Example: Parse All Features in a Directory

```python
import os
from pathlib import Path

def import_all_features(features_directory, project_config):
    """
    Recursively parse all .feature files and create tasks.
    """
    features_path = Path(features_directory)
    all_tasks = []
    all_dependencies = []
    
    for feature_file in features_path.rglob('*.feature'):
        print(f"Parsing: {feature_file}")
        
        try:
            tasks, deps = parse_feature_to_tasks(
                feature_file, 
                project_config['name']
            )
            all_tasks.extend(tasks)
            all_dependencies.extend(deps)
            
            print(f"  ✓ Created {len(tasks)} tasks")
            
        except Exception as e:
            print(f"  ✗ Error: {e}")
    
    print(f"\nTotal: {len(all_tasks)} tasks, {len(all_dependencies)} dependencies")
    return all_tasks, all_dependencies
```

### Automatic Dependency Detection

```python
def detect_entity_dependencies(tasks):
    """
    Detect when tasks reference the same entities and create dependencies.
    
    Example:
      Given medication exists    (creates Medication entity)
      When user adds medication  (uses Medication entity - depends on above)
    """
    entity_creators = {}  # Maps entity name to task that creates it
    dependencies = []
    
    for task in tasks:
        step_text_lower = task['step_text'].lower()
        
        # Check if this step creates an entity (typically Given steps)
        if task['step_type'] == 'Given':
            for keyword in ['user', 'medication', 'symptom', 'trial']:
                if keyword in step_text_lower:
                    # This task might create this entity
                    entity_creators[keyword] = task
        
        # Check if this step uses an entity that was created earlier
        if task['step_type'] in ['When', 'Then']:
            for keyword, creator_task in entity_creators.items():
                if keyword in step_text_lower:
                    # This task depends on the creator task
                    if creator_task != task:  # Don't depend on self
                        dependencies.append({
                            'task': task,
                            'depends_on': creator_task,
                            'dependency_type': 'Suggested',
                            'reason': f"Uses {keyword} entity"
                        })
    
    return dependencies
```

### CLI Tool

```python
# gherkin_import.py
import argparse
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description='Import Gherkin features to task database')
    parser.add_argument('--project', required=True, help='Project name')
    parser.add_argument('--features-dir', required=True, help='Path to features directory')
    parser.add_argument('--auto-deps', action='store_true', help='Auto-detect dependencies')
    
    args = parser.parse_args()
    
    # Load project config
    project_config = load_project_config(args.project)
    
    # Import all features
    tasks, deps = import_all_features(args.features_dir, project_config)
    
    # Auto-detect additional dependencies
    if args.auto_deps:
        auto_deps = detect_entity_dependencies(tasks)
        deps.extend(auto_deps)
        print(f"Auto-detected {len(auto_deps)} additional dependencies")
    
    # Save to database
    save_tasks_to_database(tasks, deps)
    print("✓ Import complete")

if __name__ == '__main__':
    main()
```

### Usage

```bash
# Import all features for a project
python gherkin_import.py \
    --project caresync \
    --features-dir /path/to/project/tests/features \
    --auto-deps

# Output:
# Parsing: tests/features/UserAuthentication.feature
#   ✓ Created 15 tasks
# Parsing: tests/features/MedicationManagement.feature
#   ✓ Created 23 tasks
# ...
# Total: 234 tasks, 189 dependencies
# Auto-detected 45 additional dependencies
# ✓ Import complete
```

## Benefits

✅ **Official Parser** - Uses Cucumber's official Gherkin implementation
✅ **Standards Compliant** - Parses all valid Gherkin syntax
✅ **Automatic Dependencies** - Infers step order and entity dependencies
✅ **Bulk Import** - Process entire feature directories
✅ **Error Handling** - Clear error messages for invalid Gherkin

## Next Steps

1. Install: `pip install gherkin-official`
2. Create `gherkin_import.py` script
3. Run on your features directory
4. Review auto-detected dependencies
5. Start agent to implement tasks in order
