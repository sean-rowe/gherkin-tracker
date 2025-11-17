#!/bin/bash
# PR Review Daemon Runner
# Monitors and auto-fixes PRs created by agents

# Set environment for cron (PATH, HOME for Claude Code auth)
export PATH="/Users/srowe/bin:/Users/srowe/.local/bin:/Users/srowe/.pyenv/shims:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="/Users/srowe"

cd /Users/srowe/projects/gherkin-tracker

# Run daemon (stateless - each run is independent)
env REPO_PATH=/Users/srowe/Projects/cuemap \
    python3 pr_review_daemon.py \
    >> pr_daemon_cron.log 2>&1
