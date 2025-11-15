# Task Dependency Management System

## Problem Statement

The gherkin-tracker agent picks tasks randomly from pending work, which can lead to:
- Implementing "Then" steps before the "When" steps they verify
- Creating integration tests before unit tests exist
- Building complex features before basic infrastructure is in place
- Attempting steps that require entities/services from incomplete scenarios

## Solution: Hierarchical Task Dependencies

### Dependency Types

1. **Required** - Task MUST wait for dependency to complete
2. **Suggested** - Task SHOULD wait, but can proceed if blocked
3. **Optional** - Nice to have, but not necessary

### Automatic Dependency Rules

The system automatically infers dependencies based on:

#### 1. Step Type Order (Within Same Scenario)
```
Given → When → Then
```
- All "When" steps depend on "Given" steps in the same scenario
- All "Then" steps depend on "When" steps in the same scenario

**Example:**
```gherkin
Scenario: User login
  Given user has account          # Task 1 (no dependencies)
  When user enters credentials    # Task 2 (depends on Task 1)
  Then user is logged in          # Task 3 (depends on Task 2)
```

#### 2. Entity Dependencies
If a step references an entity, it depends on:
- The task that creates that entity
- The task that creates the entity's step definition

**Example:**
```gherkin
Scenario: Enroll in trial
  Given clinical trial exists           # Task 1 (creates ClinicalTrial entity)
  When user enrolls in trial            # Task 2 (depends on Task 1)
  Then user receives trial confirmation # Task 3 (depends on Task 2)
```

#### 3. Service Dependencies
If a step needs a service, it depends on:
- Tasks that implement that service
- Tasks that create the service's interface/DTO

**Example:**
```gherkin
Feature: Medication Management
  Scenario: Add medication
    When user adds medication     # Creates IMedicationService
  
  Scenario: Search medications
    When user searches medication # Depends on IMedicationService from above
```

#### 4. Scenario Dependencies
Scenarios can declare dependencies on other scenarios:

```gherkin
@depends-on: UserRegistration
Scenario: User logs in
  # This scenario depends on UserRegistration being implemented first
```

### Execution Order

Tasks are selected based on:

1. **No Unmet Dependencies** - All required dependencies must be complete
2. **Priority** - Higher priority tasks first (manual override)
3. **Step Type** - Given → When → Then (natural BDD flow)
4. **Execution Order** - Manually assigned order number (optional)
5. **Creation Time** - Older tasks first (FIFO)

### Database Schema

```sql
-- Task table additions
ALTER TABLE Task ADD:
  - IsBlocked BOOL (quick check)
  - BlockedReason TEXT (why blocked)
  - ExecutionOrder INT (manual ordering)
  - Priority INT (override natural order)

-- Dependency tracking
CREATE TABLE TaskDependency (
  TaskId UUID,              -- Task that has dependency
  DependsOnTaskId UUID,     -- Task it depends on
  DependencyType VARCHAR,   -- Required/Suggested/Optional
  Reason TEXT               -- Why this dependency exists
);
```

### API Usage

#### Automatic Dependencies (Recommended)
The system infers dependencies automatically when tasks are created:

```python
# Tasks are created from Gherkin parsing
# Dependencies are auto-detected based on:
#  - Step order in scenario
#  - Entity references
#  - Service usage
```

#### Manual Dependencies
For complex cases, explicitly declare dependencies:

```python
# Add dependency: Task B depends on Task A
add_task_dependency(
    task_id=task_b_id,
    depends_on=task_a_id,
    dependency_type='Required',
    reason='Needs MedicationService interface'
)
```

#### Query Available Tasks
Agent queries for next available task:

```python
task = get_next_available_task(
    agent_id=agent.id,
    preferred_step_type='Given'  # Prefer Given steps first
)
```

### Example Dependency Graph

```
Feature: Clinical Trial Support
├── Scenario: Enroll in trial
│   ├── [1] Given trial exists ───────────┐
│   │                                      │
│   ├── [2] When user enrolls ◄───────────┤
│   │                                      │
│   └── [3] Then user is enrolled ◄───────┤
│                                          │
└── Scenario: Complete trial survey        │
    ├── [4] Given user is enrolled ◄───────┘ (depends on scenario above)
    │
    ├── [5] When user completes survey
    │
    └── [6] Then survey is submitted

Execution Order: 1 → 2 → 3 → 4 → 5 → 6
```

### Benefits

✅ **Logical Order** - Given → When → Then flow automatically enforced
✅ **No Failures** - Tasks only run when dependencies are met
✅ **Parallel Work** - Independent tasks can run simultaneously  
✅ **Clear Blocking** - Know exactly why a task is waiting
✅ **Smart Prioritization** - Critical path tasks execute first
✅ **Manual Override** - Can force specific execution order when needed

### Status Tracking

```
Task Status Flow:
  Pending → (dependencies met) → Available
  Available → (agent picks) → In Progress
  In Progress → (completes) → Completed
  Completed → (unblocks) → Dependent tasks now Available
```

### Configuration Examples

#### Priority Override
```python
# Mark critical infrastructure as high priority
set_task_priority(task_id, priority=100)  # Execute first
```

#### Execution Order
```python
# Force specific order (1, 2, 3...)
set_execution_order(task_id, order=1)
```

#### Circular Dependency Detection
```python
# System automatically detects and prevents circular dependencies
try:
    add_task_dependency(A, depends_on=B)
    add_task_dependency(B, depends_on=A)  # ERROR: Circular dependency
except CircularDependencyError:
    # Handle error
```

### Future Enhancements

- **Critical Path Analysis** - Identify longest dependency chain
- **Parallel Execution** - Run independent tasks simultaneously
- **Dependency Visualization** - Generate graphs of task dependencies
- **Smart Scheduling** - ML-based task ordering based on success patterns
- **Automatic Retry** - Re-queue blocked tasks when dependencies complete

## Implementation Status

- [x] Database schema designed
- [x] Dependency detection logic designed
- [ ] PostgreSQL schema implementation
- [ ] Agent integration
- [ ] Automatic dependency inference
- [ ] Manual dependency API
- [ ] Testing with complex scenarios
