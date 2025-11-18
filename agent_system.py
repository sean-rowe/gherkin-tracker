#!/usr/bin/env python3
"""
Autonomous Agent System for BDD Implementation
Structured with Domain-Driven Design layers (domain/application/infrastructure)
"""

import argparse
import logging
import os
import sys
import uuid
from pathlib import Path
from typing import Optional

import psycopg2

from gherkin_tracker.application.use_cases import AgentApplicationService, WorkSummary
from gherkin_tracker.domain.entities import AgentIdentity
from gherkin_tracker.infrastructure.postgres_repositories import (
    PostgresStatisticsRepository,
    PostgresTaskRepository,
)

DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': os.getenv('USER'),
    'host': 'localhost',
    'port': 5432,
}


class Agent:
    """Application-layer façade coordinating work for a single agent."""

    def __init__(self, agent_id: uuid.UUID, agent_type: str, name: str, service: AgentApplicationService):
        self.identity = AgentIdentity(agent_id, name, agent_type)
        self.service = service
        self.current_task = None

    def fetch_next_task(self, project_filter: Optional[str] = None):
        task = self.service.next_task(self.identity.agent_type, project_filter)
        if task:
            self.current_task = task
            logging.info(
                "Assigned task: %s | Feature: %s | Scenario: %s",
                task.name,
                task.feature_name,
                task.scenario_name,
            )
        else:
            logging.info("No more tasks available")
        return task

    def assign(self) -> bool:
        if not self.current_task:
            return False
        return self.service.assign_task(self.current_task.id, self.identity.id)

    def work(self) -> Optional[WorkSummary]:
        if not self.current_task:
            return None
        summary = self.service.work_on_task(self.current_task, self.identity)
        if summary:
            logging.info("Completed task %s", self.current_task.name)
        else:
            logging.error("Failed to complete task %s", self.current_task.name)
        return summary


class AgentOrchestrator:
    """Coordinates agents and database connections within the DDD structure."""

    def __init__(self, project_filter: Optional[str] = None):
        self.conn = None
        self.agent: Optional[Agent] = None
        self.project_filter = project_filter
        self.service: Optional[AgentApplicationService] = None

    def connect(self):
        try:
            self.conn = psycopg2.connect(**DB_PARAMS)
            self.conn.autocommit = False
            task_repo = PostgresTaskRepository(self.conn)
            stats_repo = PostgresStatisticsRepository(self.conn)
            self.service = AgentApplicationService(task_repo, stats_repo)
            logging.info("Connected to database %s", DB_PARAMS['dbname'])
        except Exception as exc:
            logging.error("Database connection failed: %s", exc)
            sys.exit(1)

    def close(self):
        if self.conn:
            self.conn.close()

    def create_agent(self, agent_type: str = 'BDD_IMPLEMENTER', name: Optional[str] = None):
        if not self.service:
            raise RuntimeError("Service not initialized; call connect() first")
        agent_id = uuid.uuid4()
        agent_name = name or f"Agent-{agent_id.hex[:8]}"
        self.agent = Agent(agent_id, agent_type, agent_name, self.service)
        logging.info("Created agent %s (%s)", agent_name, agent_type)
        return self.agent

    def run(self, max_tasks: Optional[int] = None):
        if not self.agent:
            self.create_agent()
        completed = failed = 0
        while True:
            if max_tasks and (completed + failed) >= max_tasks:
                break
            task = self.agent.fetch_next_task(self.project_filter)
            if not task:
                break
            if not self.agent.assign():
                failed += 1
                continue
            result = self.agent.work()
            if result:
                completed += 1
            else:
                failed += 1
        logging.info("Run complete: %s done, %s failed", completed, failed)

    def stats(self):
        if not self.service:
            raise RuntimeError("Service not initialized")
        stats = self.service.statistics(self.project_filter)
        logging.info("Statistics: %s", stats)
        return stats


def setup_logging(verbose: bool):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format='%(asctime)s | %(levelname)s | %(message)s')


def main():
    parser = argparse.ArgumentParser(description='DDD-structured BDD agent system')
    parser.add_argument('command', choices=['stats', 'run'])
    parser.add_argument('--max-tasks', type=int, default=None)
    parser.add_argument('--project', type=str, default=None)
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    setup_logging(args.verbose)
    orchestrator = AgentOrchestrator(project_filter=args.project)
    orchestrator.connect()

    try:
        if args.command == 'stats':
            stats = orchestrator.stats()
            print(stats)
        elif args.command == 'run':
            orchestrator.create_agent()
            orchestrator.run(args.max_tasks)
            orchestrator.stats()
    finally:
        orchestrator.close()


if __name__ == '__main__':
    main()
