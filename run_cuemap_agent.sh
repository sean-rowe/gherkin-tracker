#!/bin/bash
# CueMap BDD Agent Runner
# Runs continuously to pick up and implement BDD tasks

# Set environment for cron (PATH, HOME for Claude Code auth)
export PATH="/Users/srowe/bin:/Users/srowe/.local/bin:/Users/srowe/.pyenv/shims:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="/Users/srowe"

cd /Users/srowe/projects/gherkin-tracker

# Count current agents running
AGENT_COUNT=$(pgrep -f "agent_claude.py.*CueMap" | wc -l)

# Max 5 agents running in parallel
if [ "$AGENT_COUNT" -ge 5 ]; then
    echo "Already 5 agents running, skipping..."
    exit 0
fi

# Run agent with max 10 tasks per run, with 5 parallel workers
python3 -u agent_claude.py \
    --project CueMap \
    --max-tasks 10 \
    --parallel 5 \
    --verbose \
    --log-file cuemap_agent.log \
    >> cuemap_agent_cron.log 2>&1
