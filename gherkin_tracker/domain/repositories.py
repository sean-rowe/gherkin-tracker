"""Abstract repositories and unit-of-work boundaries."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Iterable, Optional
from uuid import UUID

from .entities import StepTask, AgentStatistics


class TaskRepository(ABC):
    """Port for retrieving and updating tasks."""

    @abstractmethod
    def get_next_task(self, agent_type: str, project_filter: Optional[str] = None) -> Optional[StepTask]:
        raise NotImplementedError

    @abstractmethod
    def assign_task(self, task_id: UUID, agent_id: UUID) -> bool:
        raise NotImplementedError

    @abstractmethod
    def complete_task(
        self,
        task_id: UUID,
        agent_id: UUID,
        work_accomplished: str,
        build_succeeded: bool,
        tests_passed: bool,
        bdd_step_file: Optional[str],
        bdd_method_name: Optional[str],
        service_location: Optional[str] = None,
    ) -> bool:
        raise NotImplementedError


class StatisticsRepository(ABC):
    """Port for reporting aggregate task statistics."""

    @abstractmethod
    def get_statistics(self, project_filter: Optional[str] = None) -> AgentStatistics:
        raise NotImplementedError

