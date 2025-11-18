#!/bin/bash
# Real-time agent monitoring dashboard

LOG_FILE="$1"

if [ -z "$LOG_FILE" ]; then
    LOG_FILE=$(ls -t agent_production_run_*.log 2>/dev/null | head -1)
    if [ -z "$LOG_FILE" ]; then
        echo "No log file found. Usage: ./monitor.sh <log-file>"
        exit 1
    fi
fi

echo "Monitoring: $LOG_FILE"
echo ""

while true; do
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "  CLAUDE CODE AGENT - LIVE DASHBOARD"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Log File: $LOG_FILE"
    echo "  Last Updated: $(date '+%H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Count task completions
    COMPLETED=$(grep -c "TASK COMPLETED" "$LOG_FILE" 2>/dev/null || echo 0)
    FAILED=$(grep -c "TASK FAILED" "$LOG_FILE" 2>/dev/null || echo 0)
    
    echo "📊 PROGRESS:"
    echo "   ✅ Completed: $COMPLETED"
    echo "   ❌ Failed:    $FAILED"
    echo ""
    
    # Show current task
    echo "🔄 CURRENT TASK:"
    CURRENT=$(grep "WORKING ON TASK:" "$LOG_FILE" | tail -1 | sed 's/.*WORKING ON TASK: //')
    echo "   $CURRENT"
    echo ""
    
    # Show recent log entries (last 10 INFO/WARNING/ERROR)
    echo "📝 RECENT ACTIVITY:"
    grep -E "(INFO|WARNING|ERROR)" "$LOG_FILE" | tail -10 | while read line; do
        if [[ "$line" == *"ERROR"* ]]; then
            echo -e "   \033[0;31m$line\033[0m"
        elif [[ "$line" == *"WARNING"* ]]; then
            echo -e "   \033[0;33m$line\033[0m"
        else
            echo "   $line"
        fi
    done
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Press Ctrl+C to exit"
    
    sleep 5
done
