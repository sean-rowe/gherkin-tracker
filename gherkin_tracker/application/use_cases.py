"""Application layer orchestration for agents."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional
from uuid import UUID

from gherkin_tracker.domain.entities import (
    AgentIdentity,
    BusinessLogicImplementation,
    StepImplementation,
    StepTask,
    TestExecution,
)
from gherkin_tracker.domain.repositories import StatisticsRepository, TaskRepository
from gherkin_tracker.domain.services import StepGenerationService


@dataclass
class WorkSummary:
    task: StepTask
    step_impl: StepImplementation
    logic_impl: BusinessLogicImplementation
    tests: TestExecution

    def format_work_log(self) -> str:
        sections = [
            f"BDD Step: {self.step_impl.notes}",
            f"Business Logic: {self.logic_impl.notes}",
            f"Tests: {self.tests.output}",
        ]
        return '\n'.join(sections)


class AgentApplicationService:
    """Coordinates domain services and repositories for a single agent."""

    def __init__(
        self,
        repo: TaskRepository,
        stats_repo: StatisticsRepository,
        generation_service: Optional[StepGenerationService] = None,
    ):
        self.repo = repo
        self.stats_repo = stats_repo
        self.generation_service = generation_service or StepGenerationService()

    def next_task(self, agent_type: str, project_filter: Optional[str] = None) -> Optional[StepTask]:
        return self.repo.get_next_task(agent_type, project_filter)

    def assign_task(self, task_id: UUID, agent_id: UUID) -> bool:
        return self.repo.assign_task(task_id, agent_id)

    def work_on_task(self, task: StepTask, agent: AgentIdentity) -> Optional[WorkSummary]:
        step_impl = self.generation_service.build_step_implementation(task)
        logic_impl = self.generation_service.build_logic_implementation(task)
        tests = self.generation_service.simulate_tests()
        work_log = WorkSummary(task, step_impl, logic_impl, tests)

        completed = self.repo.complete_task(
            task.id,
            agent.id,
            work_log.format_work_log(),
            tests.build_succeeded,
            tests.tests_passed,
            step_impl.file_path,
            step_impl.method_name,
            service_location=logic_impl.location,
        )
        return work_log if completed else None

    def statistics(self, project_filter: Optional[str] = None):
        return self.stats_repo.get_statistics(project_filter)

