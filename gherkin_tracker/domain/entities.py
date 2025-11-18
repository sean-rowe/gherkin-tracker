"""Domain entities and value objects for the gherkin tracker DDD layout."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional
from uuid import UUID


@dataclass(frozen=True)
class StepTask:
    """Aggregate root representing a BDD implementation task."""

    id: UUID
    name: str
    feature_name: str
    scenario_name: str
    step_type: str
    step_text: str


@dataclass(frozen=True)
class StepImplementation:
    """Value object describing a generated BDD step definition."""

    file_path: str
    method_name: str
    notes: str


@dataclass(frozen=True)
class BusinessLogicImplementation:
    """Value object describing a generated service/controller implementation."""

    location: str
    notes: str


@dataclass(frozen=True)
class TestExecution:
    """Value object summarizing build and test execution."""

    build_succeeded: bool
    tests_passed: bool
    output: str


@dataclass(frozen=True)
class AgentStatistics:
    """Aggregate statistics for reporting progress."""

    total: int
    completed: int
    pending: int
    failed: int
    in_progress: int
    bdd_implemented: int
    business_logic_implemented: int
    fully_implemented: int


@dataclass(frozen=True)
class AgentIdentity:
    """Value object describing an agent's identity in the system."""

    id: UUID
    name: str
    agent_type: str

