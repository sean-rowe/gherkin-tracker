# Gherkin Tracker

**A Domain-Driven Design (DDD) system for automating BDD test implementation across multiple projects and languages.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## 🎯 Overview

Autonomous agent system that:
- Reads Gherkin feature files from your codebase
- Uses Claude Code or DeepSeek local LLM to implement BDD step definitions
- Generates business logic (services/controllers)
- Runs builds and tests automatically
- Tracks progress in PostgreSQL
- Supports multiple projects and languages (C#, C++, Python, etc.)

**Status**: Production-ready, DDD architecture

---

## 📁 Project Structure (DDD)

```
gherkin-tracker/
├── gherkin_tracker/          # Core application (DDD layers)
│   ├── domain/               # Business logic, entities, domain services
│   │   ├── entities.py       # StepTask, StepImplementation, etc.
│   │   ├── repositories.py   # Abstract repository ports
│   │   ├── services.py       # Domain services (file naming, etc.)
│   │   └── project_config.py # Project configuration domain model
│   ├── application/          # Use cases and orchestration
│   │   └── use_cases.py      # AgentApplicationService
│   └── infrastructure/       # External adapters
│       ├── postgres_repositories.py  # PostgreSQL implementation
│       ├── local_llm.py      # DeepSeek LLM integration
│       └── import_gherkin.py # Gherkin file parser
│
├── bin/                      # Executable scripts
│   ├── setup.sh              # Database setup
│   ├── setup_local_llm.sh    # DeepSeek LLM setup
│   ├── watch_agent.sh        # Real-time log viewer
│   ├── run_cuemap_agent.sh   # CueMap daemon
│   └── run_pr_daemon.sh      # PR review daemon
│
├── scripts/                  # Maintenance & utility scripts
│   ├── deployment/           # PR management, git workflows
│   ├── verification/         # Verification and auditing
│   └── setup/                # Database initialization
│
├── database/                 # Database schema and migrations
│   ├── schema.sql
│   ├── migrations/
│   └── scripts/
│
├── config/                   # Configuration files
│   └── projects.json         # Multi-project settings
│
├── docs/                     # Documentation
│   ├── guides/               # User guides
│   └── architecture/         # Architecture docs (coming soon)
│
├── logs/                     # Runtime logs (git-ignored)
│
├── agent_system.py           # DDD-based agent CLI (stub/framework)
├── agent_claude.py           # Production agent with Claude/DeepSeek
├── requirements.txt          # Python dependencies
├── docker-compose.yml        # PostgreSQL + PgAdmin containers
└── README.md                 # This file
```

---

## 🚀 Quick Start

### 1. Setup Database

```bash
# Start PostgreSQL
brew install postgresql@17
brew services start postgresql@17

# Initialize database
./bin/setup.sh
```

### 2. Setup DeepSeek Local LLM (Recommended)

```bash
# Install and configure DeepSeek
./bin/setup_local_llm.sh

# Test local LLM
python3 -m gherkin_tracker.infrastructure.local_llm
```

### 3. Import Gherkin Features

```bash
python3 -m gherkin_tracker.infrastructure.import_gherkin \
    ProjectName /path/to/features
```

### 4. Run Agent

```bash
# DDD framework agent (stub implementation)
python3 agent_system.py run --max-tasks 5 --project ProjectName

# Production agent with Claude/DeepSeek
python3 agent_claude.py --max-tasks 5 --project ProjectName --use-local-llm

# Watch logs in real-time
./bin/watch_agent.sh
```

---

## 📚 Documentation

- **[Quick Start Guide](docs/guides/QUICKSTART.md)** - Database setup
- **[Usage Guide](docs/guides/USAGE.md)** - Complete usage examples
- **[Local LLM Setup](docs/guides/LOCAL_LLM_SETUP.md)** - DeepSeek configuration
- **[Multi-Project Support](docs/guides/MULTI_PROJECT.md)** - Working with multiple codebases
- **[Agent System](docs/guides/AGENT_SYSTEM.md)** - Architecture details
- **[Logging](docs/guides/LOGGING.md)** - Log management

---

## 🏗️ Architecture (DDD)

### Domain Layer
- **Entities**: `StepTask`, `AgentIdentity`, `AgentStatistics`
- **Value Objects**: `StepImplementation`, `BusinessLogicImplementation`, `TestExecution`
- **Domain Services**: `StepGenerationService` (file naming, method generation)
- **Repositories (Ports)**: `TaskRepository`, `StatisticsRepository`

### Application Layer
- **Use Cases**: `AgentApplicationService` (orchestrates domain and infrastructure)
- **DTOs**: `WorkSummary`

### Infrastructure Layer
- **Repository Adapters**: `PostgresTaskRepository`, `PostgresStatisticsRepository`
- **External Services**: `LocalLLM` (DeepSeek integration)
- **File Parsers**: `import_gherkin` (Gherkin feature file parser)

### Presentation Layer
- **CLI**: `agent_system.py` (DDD framework), `agent_claude.py` (production)
- **Scripts**: Various maintenance and deployment scripts

---

## 🔧 Configuration

### Project Configuration

Edit `config/projects.json`:

```json
{
  "CareSync": {
    "name": "CareSync",
    "path": "/path/to/caresync",
    "language": "csharp",
    "test_framework": "specflow",
    "build_command": "dotnet build",
    "test_command": "dotnet test --no-build"
  }
}
```

### Environment Variables

```bash
# Use local LLM instead of Claude
export USE_LOCAL_LLM=1

# Custom model path
export LOCAL_LLM_MODEL_PATH="$HOME/models/deepseek-coder-6.7b-instruct.Q5_K_M.gguf"
```

---

## 🤖 Agent Modes

### 1. DDD Framework Agent (Stub)
Clean architecture demonstration with simulated implementations:
```bash
python3 agent_system.py run --max-tasks 5
```

### 2. Production Agent (Claude/DeepSeek)
Real BDD implementation using AI:
```bash
# With Claude Code
python3 agent_claude.py --max-tasks 10

# With DeepSeek local LLM
python3 agent_claude.py --max-tasks 10 --use-local-llm
```

---

## 📊 Statistics

```bash
# View progress
python3 agent_system.py stats --project CareSync

# SQL queries
psql -d gherkin_tracker -c "SELECT * FROM vw_feature_bdd_progress"
```

---

## 🛠️ Development

### Running Tests

```bash
# Verify local LLM setup
python3 scripts/verification/benchmark_local_llm.py

# Test BDD implementations
python3 scripts/verification/verify_bdd_implementations.py
```

### Log Management

All logs go to `logs/` (git-ignored):
```bash
# Watch real-time
./bin/watch_agent.sh logs/agent.log

# Archive old logs
gzip logs/agent_$(date -v-7d +%Y%m%d).log
```

---

## 🐳 Docker Support

```bash
# Start PostgreSQL + PgAdmin
docker-compose up -d

# Access PgAdmin
open http://localhost:5050
```

---

## 🤝 Contributing

This project follows Domain-Driven Design principles:
1. Keep domain logic pure (no infrastructure dependencies)
2. Use ports/adapters for external services
3. Application layer orchestrates use cases
4. Infrastructure layer implements adapters

---

## 📝 License

MIT License - see [LICENSE](LICENSE)

---

## 🙏 Credits

Built for multi-project BDD automation with Clean Architecture and DDD principles.

**Key Technologies:**
- PostgreSQL 17
- Python 3.11+
- Claude Code / DeepSeek LLM
- llama-cpp-python (GPU-accelerated inference)

