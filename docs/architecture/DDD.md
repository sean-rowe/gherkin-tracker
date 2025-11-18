# Architecture Documentation

## Domain-Driven Design Structure

This project follows strict DDD principles with clear separation of concerns across three main layers.

### Layer Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Presentation Layer                    │
│  (CLI interfaces: agent_system.py, agent_claude.py)     │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
│      (Use Cases: AgentApplicationService)                │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                      Domain Layer                        │
│   (Entities, Value Objects, Domain Services, Ports)     │
└─────────────────────────────────────────────────────────┘
                            ↑
┌─────────────────────────────────────────────────────────┐
│                  Infrastructure Layer                    │
│    (Adapters: PostgreSQL, LLM, File System)             │
└─────────────────────────────────────────────────────────┘
```

---

## Domain Layer (`gherkin_tracker/domain/`)

### Entities
- `StepTask` - Aggregate root representing a BDD implementation task
- `AgentIdentity` - Value object for agent identification
- `AgentStatistics` - Aggregate statistics for reporting

### Value Objects
- `StepImplementation` - Immutable BDD step definition metadata
- `BusinessLogicImplementation` - Service/controller implementation metadata
- `TestExecution` - Build and test results

### Domain Services
- `StepGenerationService` - Encapsulates file naming, method generation policies

### Repository Ports (Interfaces)
- `TaskRepository` - Abstract interface for task persistence
- `StatisticsRepository` - Abstract interface for aggregate queries

### Configuration
- `ProjectConfig` - Domain model for project settings
- `ProjectConfigManager` - Manages multiple project configurations

**Key Principle**: Domain layer has ZERO dependencies on infrastructure or application layers.

---

## Application Layer (`gherkin_tracker/application/`)

### Use Cases
- `AgentApplicationService` - Orchestrates domain services and repositories
  - `next_task()` - Retrieve next pending task
  - `assign_task()` - Assign task to agent
  - `work_on_task()` - Execute full workflow (generate + test + persist)
  - `statistics()` - Get aggregate statistics

### DTOs
- `WorkSummary` - Encapsulates completed work for reporting

**Key Principle**: Application layer orchestrates domain and infrastructure but contains no business logic.

---

## Infrastructure Layer (`gherkin_tracker/infrastructure/`)

### Repository Adapters
- `PostgresTaskRepository` - PostgreSQL implementation of `TaskRepository`
- `PostgresStatisticsRepository` - PostgreSQL implementation of `StatisticsRepository`

### External Service Adapters
- `LocalLLM` - DeepSeek/Qwen local LLM integration
  - GPU acceleration (Metal on macOS, CUDA on Linux)
  - Model loading and generation
  - Prompt formatting

### File System Adapters
- `import_gherkin` - Gherkin feature file parser
  - Reads `.feature` files
  - Parses scenarios and steps
  - Imports into database

**Key Principle**: Infrastructure implements domain ports and has NO dependency on domain internals.

---

## Presentation Layer (Root scripts)

### CLIs
- `agent_system.py` - DDD framework CLI (clean architecture demo)
- `agent_claude.py` - Production CLI with Claude/DeepSeek integration

### Utilities (bin/)
- `setup.sh` - Database initialization
- `setup_local_llm.sh` - LLM configuration
- `watch_agent.sh` - Real-time log viewer

---

## Data Flow Example

### Agent Processes a Task

```
1. CLI (agent_system.py)
   ↓
2. AgentApplicationService.next_task()
   ↓
3. PostgresTaskRepository.get_next_task()
   ↓ (Database query)
4. Returns StepTask (domain entity)
   ↓
5. AgentApplicationService.work_on_task()
   ↓
6. StepGenerationService.build_step_implementation()
   ↓ (Domain logic: file naming, method generation)
7. Returns StepImplementation (value object)
   ↓
8. PostgresTaskRepository.complete_task()
   ↓ (Database update)
9. Returns success/failure
   ↓
10. CLI displays result
```

---

## Design Patterns Used

### Ports and Adapters (Hexagonal Architecture)
- Domain defines ports (`TaskRepository`, `StatisticsRepository`)
- Infrastructure provides adapters (`PostgresTaskRepository`, etc.)

### Repository Pattern
- Abstract data access behind domain interfaces
- Allows swapping PostgreSQL for other databases

### Domain Services
- Encapsulate domain logic that doesn't belong to entities
- Example: `StepGenerationService` for file naming conventions

### Value Objects
- Immutable data structures (`StepImplementation`, `TestExecution`)
- No identity, compared by value

### Application Services
- Coordinate use cases
- Transaction boundaries
- No business logic

---

## Testing Strategy

### Unit Tests (Domain)
Test pure domain logic in isolation:
- Entity behavior
- Domain service algorithms
- Value object validation

### Integration Tests (Infrastructure)
Test adapters:
- Repository queries
- LLM integration
- File parsing

### Acceptance Tests (Application)
Test complete use cases:
- Full agent workflow
- Multi-step scenarios

---

## Extension Points

### Adding New LLM Provider
1. Create adapter in `infrastructure/` implementing generation interface
2. Update `agent_claude.py` to use new adapter
3. No changes needed to domain or application layers

### Adding New Database
1. Implement `TaskRepository` and `StatisticsRepository` interfaces
2. Update dependency injection in `agent_system.py`
3. No changes to domain or application

### Adding New Language Support
1. Update `ProjectConfig` domain model
2. Add language-specific templates
3. No infrastructure changes needed

---

## Benefits of This Architecture

✅ **Testability**: Domain logic testable without database or LLM  
✅ **Flexibility**: Swap PostgreSQL, LLM, or UI without breaking domain  
✅ **Maintainability**: Clear separation of concerns  
✅ **Scalability**: Easy to add new features within layers  
✅ **Portability**: Domain logic reusable across different infrastructures  

---

## Further Reading

- [Domain-Driven Design (Evans)](https://www.domainlanguage.com/ddd/)
- [Clean Architecture (Martin)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Ports and Adapters](https://alistair.cockburn.us/hexagonal-architecture/)

