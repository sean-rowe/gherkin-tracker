# File Organization Guide

## Directory Structure

```
gherkin-tracker/
├── gherkin_tracker/          # Core Python package (DDD layers)
│   ├── __init__.py           # Package metadata
│   ├── domain/               # Business logic (no external dependencies)
│   ├── application/          # Use case orchestration
│   └── infrastructure/       # External adapters (DB, LLM, files)
│
├── bin/                      # Executable shell scripts
│   ├── setup.sh
│   ├── setup_local_llm.sh
│   ├── watch_agent.sh
│   ├── run_cuemap_agent.sh
│   └── run_pr_daemon.sh
│
├── scripts/                  # Python utility scripts
│   ├── deployment/           # PR management, git workflows
│   │   ├── pr_manager.py
│   │   ├── pr_review_daemon.py
│   │   ├── git_worktree_manager.py
│   │   ├── create_thematic_prs.py
│   │   └── retroactive_pr_creator.py
│   ├── verification/         # Testing and auditing
│   │   ├── verify_bdd_implementations.py
│   │   ├── verify_uptrms_implementations.py
│   │   ├── audit_gherkin_coverage.py
│   │   ├── mark_completed_tasks.py
│   │   ├── mark_business_logic.py
│   │   ├── test_local_verification.py
│   │   ├── agent_verify_implementations.py
│   │   └── benchmark_local_llm.py
│   └── setup/                # Database initialization scripts
│       └── (SQL scripts from database/)
│
├── database/                 # Database schema and migrations
│   ├── schema.sql
│   ├── migrations/
│   ├── scripts/
│   └── procedures/
│
├── config/                   # Configuration files
│   └── projects.json         # Multi-project settings
│
├── docs/                     # Documentation
│   ├── guides/               # User guides (markdown)
│   │   ├── QUICKSTART.md
│   │   ├── USAGE.md
│   │   ├── LOCAL_LLM_SETUP.md
│   │   ├── MULTI_PROJECT.md
│   │   ├── AGENT_SYSTEM.md
│   │   ├── LOGGING.md
│   │   ├── LOGS.md
│   │   ├── OPTIMIZATION.md
│   │   ├── DOCKER_SETUP.md
│   │   ├── PARALLEL_WORKFLOW_README.md
│   │   ├── OVERNIGHT_RUN_STATUS.md
│   │   ├── TASK_DEPENDENCIES.md
│   │   ├── GHERKIN_PARSER.md
│   │   └── AGENT_USAGE.md
│   └── architecture/         # Architecture documentation
│       ├── DDD.md            # Domain-Driven Design overview
│       └── FILE_ORGANIZATION.md  # This file
│
├── logs/                     # Runtime logs (git-ignored)
│   ├── agent.log
│   ├── cuemap_agent.log
│   ├── pr_daemon_cron.log
│   └── ...
│
├── agent_system.py           # DDD framework CLI (clean architecture)
├── agent_claude.py           # Production CLI (Claude/DeepSeek)
├── requirements.txt          # Python dependencies
├── docker-compose.yml        # PostgreSQL + PgAdmin
├── Dockerfile                # Database container
├── .gitignore                # Git exclusions
├── .env.example              # Environment template
├── LICENSE                   # MIT license
└── README.md                 # Main documentation
```

---

## File Placement Rules

### When to add a file to `gherkin_tracker/domain/`
- Pure business logic entities
- Value objects (immutable data structures)
- Domain services (logic that doesn't belong to entities)
- Repository interfaces (ports)
- Configuration domain models

**Examples:**
- `entities.py` - StepTask, AgentIdentity
- `services.py` - StepGenerationService
- `repositories.py` - TaskRepository interface
- `project_config.py` - ProjectConfig domain model

### When to add a file to `gherkin_tracker/application/`
- Use case orchestration
- Application services coordinating domain + infrastructure
- DTOs for cross-layer communication

**Examples:**
- `use_cases.py` - AgentApplicationService

### When to add a file to `gherkin_tracker/infrastructure/`
- Database adapters (PostgreSQL, SQLite, etc.)
- External service integrations (LLM, APIs)
- File system operations
- Repository implementations

**Examples:**
- `postgres_repositories.py` - PostgreSQL adapters
- `local_llm.py` - DeepSeek LLM integration
- `import_gherkin.py` - Feature file parser

### When to add a file to `bin/`
- Executable shell scripts
- Setup/installation scripts
- Daemon runners
- Monitoring utilities

**Examples:**
- `setup.sh` - Database setup
- `watch_agent.sh` - Log viewer
- `run_cuemap_agent.sh` - Cron daemon

### When to add a file to `scripts/deployment/`
- PR creation and management
- Git workflow automation
- Deployment automation
- Worktree management

**Examples:**
- `pr_manager.py`
- `create_thematic_prs.py`

### When to add a file to `scripts/verification/`
- Test runners
- Code verification tools
- Benchmarking utilities
- Auditing scripts

**Examples:**
- `verify_bdd_implementations.py`
- `benchmark_local_llm.py`

### When to add a file to `database/`
- SQL schema definitions
- Database migrations
- Stored procedures
- Database-specific scripts

### When to add a file to `config/`
- JSON/YAML configuration files
- Environment-specific settings
- Project definitions

### When to add a file to `docs/guides/`
- User-facing documentation
- How-to guides
- Tutorials
- Setup instructions

### When to add a file to `docs/architecture/`
- Architecture decision records
- Design pattern documentation
- System diagrams
- Technical specifications

---

## Import Guidelines

### Domain Layer Imports
```python
# ✅ ALLOWED: Standard library only
from dataclasses import dataclass
from typing import Optional
from uuid import UUID

# ❌ FORBIDDEN: No infrastructure or application imports
from gherkin_tracker.infrastructure.postgres_repositories import ...  # NO!
```

### Application Layer Imports
```python
# ✅ ALLOWED: Domain imports
from gherkin_tracker.domain.entities import StepTask
from gherkin_tracker.domain.repositories import TaskRepository

# ✅ ALLOWED: Infrastructure imports (via dependency injection)
from gherkin_tracker.infrastructure.postgres_repositories import PostgresTaskRepository
```

### Infrastructure Layer Imports
```python
# ✅ ALLOWED: Domain ports
from gherkin_tracker.domain.repositories import TaskRepository

# ✅ ALLOWED: External libraries
import psycopg2
from llama_cpp import Llama
```

### Script Imports
```python
# ✅ ALLOWED: Add project root to path
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# Then import from gherkin_tracker
from gherkin_tracker.infrastructure.local_llm import LocalLLM
```

---

## Naming Conventions

### Files
- Python modules: `snake_case.py`
- Shell scripts: `kebab-case.sh`
- Documentation: `UPPERCASE.md` or `PascalCase.md`
- Config files: `lowercase.json`, `lowercase.yml`

### Python Classes
- Entities: `PascalCase` (e.g., `StepTask`)
- Services: `PascalCaseService` (e.g., `AgentApplicationService`)
- Repositories: `PascalCaseRepository` (e.g., `PostgresTaskRepository`)
- Value Objects: `PascalCase` (e.g., `StepImplementation`)

### Python Functions
- `snake_case` for all functions and methods
- Domain services: verb phrases (e.g., `build_step_implementation`)
- Repository methods: CRUD verbs (e.g., `get_next_task`, `assign_task`)

---

## Migration Checklist

When moving files:

1. ✅ Update import statements in dependent files
2. ✅ Update script references (bin/ scripts)
3. ✅ Update documentation references
4. ✅ Update .gitignore if needed
5. ✅ Run smoke tests to verify imports
6. ✅ Update README.md structure diagram

---

## Git Ignore Rules

Always ignored:
- `logs/` - All runtime logs
- `__pycache__/` - Python bytecode
- `*.pyc`, `*.pyo` - Compiled Python
- `.env`, `.env.local` - Environment secrets
- `*.db`, `*.sqlite` - Local databases
- `.idea/`, `.vscode/` - IDE configs

Conditionally ignored:
- `config/projects.json` - May contain local paths (use `config/projects.json.example`)

---

## Clean Architecture Principles

1. **Dependencies flow inward**: Infrastructure → Application → Domain
2. **Domain is pure**: No external dependencies
3. **Interfaces at boundaries**: Domain defines ports, infrastructure implements
4. **Testability**: Each layer testable in isolation
5. **Replaceability**: Swap infrastructure without touching domain

---

## Quick Reference

| Need to...                        | Add file to...              |
|-----------------------------------|-----------------------------|
| Define business entity            | `gherkin_tracker/domain/`   |
| Implement database query          | `gherkin_tracker/infrastructure/` |
| Orchestrate use case              | `gherkin_tracker/application/` |
| Create deployment script          | `scripts/deployment/`       |
| Create verification tool          | `scripts/verification/`     |
| Add shell utility                 | `bin/`                      |
| Write user guide                  | `docs/guides/`              |
| Document architecture decision    | `docs/architecture/`        |
| Store configuration               | `config/`                   |
| Add database migration            | `database/migrations/`      |

---

## Maintenance

### Regular Cleanup Tasks
- Archive old logs: `gzip logs/agent_$(date -v-7d +%Y%m%d).log`
- Remove unused migrations: Review `database/migrations/`
- Update documentation: Keep `docs/` in sync with code
- Prune old branches: Clean up git worktrees

### Code Quality
- Run linter: `pylint gherkin_tracker/`
- Check imports: Verify no circular dependencies
- Review architecture: Ensure DDD boundaries respected
- Update tests: Keep test coverage high

