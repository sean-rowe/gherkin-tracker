"""Infrastructure layer for local LLM support."""
from .local_llm import LocalLLM, get_recommended_model_config
from .postgres_repositories import PostgresTaskRepository, PostgresStatisticsRepository

__all__ = [
    'LocalLLM',
    'get_recommended_model_config',
    'PostgresTaskRepository',
    'PostgresStatisticsRepository',
]

