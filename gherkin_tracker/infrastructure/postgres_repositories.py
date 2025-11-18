"""PostgreSQL-backed repositories implementing domain ports."""
from __future__ import annotations

from dataclasses import asdict
from typing import Optional
from uuid import UUID

import psycopg2
from psycopg2.extras import RealDictCursor

from gherkin_tracker.domain.entities import AgentStatistics, StepTask
from gherkin_tracker.domain.repositories import StatisticsRepository, TaskRepository


class PostgresTaskRepository(TaskRepository):
    def __init__(self, conn):
        self.conn = conn

    def get_next_task(self, agent_type: str, project_filter: Optional[str] = None) -> Optional[StepTask]:
        cursor = self.conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM sp_get_next_task(%s, %s)", (agent_type, project_filter))
        task = cursor.fetchone()
        cursor.close()
        if not task:
            return None
        return StepTask(
            id=task['task_id'],
            name=task['task_name'],
            feature_name=task['feature_name'],
            scenario_name=task['scenario_name'],
            step_type=task['step_type'],
            step_text=task['step_text'],
        )

    def assign_task(self, task_id: UUID, agent_id: UUID) -> bool:
        cursor = self.conn.cursor()
        try:
            cursor.execute("SELECT * FROM sp_assign_task_to_agent(%s, %s)", (task_id, agent_id))
            self.conn.commit()
            cursor.close()
            return True
        except Exception:
            self.conn.rollback()
            cursor.close()
            return False

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
        cursor = self.conn.cursor()
        try:
            cursor.execute(
                "SELECT * FROM sp_complete_task(%s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    task_id,
                    agent_id,
                    work_accomplished,
                    build_succeeded,
                    tests_passed,
                    bdd_step_file,
                    bdd_method_name,
                    service_location,
                ),
            )
            self.conn.commit()
            cursor.close()
            return True
        except Exception:
            self.conn.rollback()
            cursor.close()
            return False


class PostgresStatisticsRepository(StatisticsRepository):
    def __init__(self, conn):
        self.conn = conn

    def get_statistics(self, project_filter: Optional[str] = None) -> AgentStatistics:
        cursor = self.conn.cursor(cursor_factory=RealDictCursor)
        if project_filter:
            cursor.execute(
                """
                SELECT
                    COUNT(*) FILTER (WHERE t.status = 'Completed') as completed,
                    COUNT(*) FILTER (WHERE t.status = 'Pending') as pending,
                    COUNT(*) FILTER (WHERE t.status = 'Failed') as failed,
                    COUNT(*) FILTER (WHERE t.status = 'In Progress') as in_progress,
                    COUNT(*) FILTER (WHERE t.bdd_implemented = TRUE) as bdd_implemented,
                    COUNT(*) FILTER (WHERE t.business_logic_implemented = TRUE) as logic_implemented,
                    COUNT(*) FILTER (WHERE t.bdd_implemented = TRUE AND t.business_logic_implemented = TRUE) as fully_implemented,
                    COUNT(*) as total
                FROM task t
                JOIN step s ON t.step_id = s.id
                JOIN scenario_step ss ON ss.step_id = s.id
                JOIN scenario sc ON ss.scenario_id = sc.id
                JOIN feature f ON sc.feature_id = f.id
                JOIN project p ON f.project_id = p.id
                WHERE p.name = %s
                """,
                (project_filter,),
            )
        else:
            cursor.execute(
                """
                SELECT
                    COUNT(*) FILTER (WHERE status = 'Completed') as completed,
                    COUNT(*) FILTER (WHERE status = 'Pending') as pending,
                    COUNT(*) FILTER (WHERE status = 'Failed') as failed,
                    COUNT(*) FILTER (WHERE status = 'In Progress') as in_progress,
                    COUNT(*) FILTER (WHERE bdd_implemented = TRUE) as bdd_implemented,
                    COUNT(*) FILTER (WHERE business_logic_implemented = TRUE) as logic_implemented,
                    COUNT(*) FILTER (WHERE bdd_implemented = TRUE AND business_logic_implemented = TRUE) as fully_implemented,
                    COUNT(*) as total
                FROM task
                """,
            )
        stats = cursor.fetchone()
        cursor.close()
        return AgentStatistics(
            total=stats['total'],
            completed=stats['completed'],
            pending=stats['pending'],
            failed=stats['failed'],
            in_progress=stats['in_progress'],
            bdd_implemented=stats['bdd_implemented'],
            business_logic_implemented=stats['logic_implemented'],
            fully_implemented=stats['fully_implemented'],
        )

