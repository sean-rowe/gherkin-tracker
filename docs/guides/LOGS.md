# Logs Directory

All runtime and daemon logs now live under `logs/`. Scripts should reference files inside that directory instead of cluttering the repository root.

Examples:
- Agent run: `logs/agent.log`
- CueMap cron: `logs/cuemap_agent_cron.log`
- PR daemon: `logs/pr_daemon_cron.log`

Rotate or prune logs by deleting files within `logs/` as needed; the directory is git-ignored.

