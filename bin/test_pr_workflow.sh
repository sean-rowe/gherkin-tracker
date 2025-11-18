#!/bin/bash
# Test PR Creation Workflow
# Runs agent on a single task to verify individual PR creation

set -e  # Exit on error

echo "========================================="
echo "PR Workflow Test"
echo "========================================="

# Check preconditions
echo ""
echo "Checking preconditions..."

# 1. Check gh auth
echo "  - Checking GitHub CLI authentication..."
if ! gh auth status > /dev/null 2>&1; then
    echo "❌ GitHub CLI not authenticated"
    echo "   Run: gh auth login"
    exit 1
fi
echo "  ✓ GitHub CLI authenticated"

# 2. Check we're in cuemap repo on main branch
cd /Users/srowe/Projects/cuemap
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "❌ Not on main branch (currently on: $CURRENT_BRANCH)"
    echo "   Run: git checkout main"
    exit 1
fi
echo "  ✓ On main branch"

# 3. Check clean working directory
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️  Working directory has uncommitted changes"
    echo "   Stashing..."
    git stash push -m "Auto-stash before PR workflow test"
fi
echo "  ✓ Working directory clean"

# 4. Pull latest
echo "  - Pulling latest from origin..."
git pull origin main
echo "  ✓ Up to date with origin"

echo ""
echo "Running agent on 1 task..."
echo "========================================="

# Run agent with max 1 task
cd /Users/srowe/Projects/gherkin-tracker
python3 agent_claude.py \
    --project cuemap \
    --max-tasks 1 \
    --verbose \
    --log test_pr_workflow_$(date +%Y%m%d_%H%M%S).log

EXIT_CODE=$?

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Agent completed successfully"
    echo ""
    echo "Checking results..."

    # Check if PR was created
    echo "  - Recent PRs with agent-generated label:"
    gh pr list --label agent-generated --limit 5

    echo ""
    echo "  - Current branch:"
    cd /Users/srowe/Projects/cuemap
    git branch --show-current

    echo ""
    echo "✅ PR Workflow Test PASSED"
    echo ""
    echo "Expected outcome:"
    echo "  1. A new PR was created"
    echo "  2. Current branch is 'main' (not a feature branch)"
    echo "  3. No uncommitted changes"

else
    echo "❌ Agent failed with exit code: $EXIT_CODE"
    echo ""
    echo "Check the log file for details:"
    echo "  tail -100 test_pr_workflow_*.log"
    exit 1
fi
