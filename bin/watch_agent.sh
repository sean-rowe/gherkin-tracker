#!/bin/bash
# Real-time agent log viewer with color coding

# Check if log file is provided
LOG_FILE="${1:-logs/agent.log}"

# Create log file if it doesn't exist
touch "$LOG_FILE"

echo "====================================================================="
echo "  CLAUDE CODE AGENT - REAL-TIME LOG VIEWER"
echo "====================================================================="
echo "  Watching: $LOG_FILE"
echo "  Press Ctrl+C to stop"
echo "====================================================================="
echo ""

# Watch the log file with color coding
tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Color code based on log level
    if [[ "$line" == *"| ERROR"* ]]; then
        # Red for errors
        echo -e "\033[0;31m$line\033[0m"
    elif [[ "$line" == *"| WARNING"* ]]; then
        # Yellow for warnings
        echo -e "\033[0;33m$line\033[0m"
    elif [[ "$line" == *"| INFO"* ]]; then
        # Green for info
        echo -e "\033[0;32m$line\033[0m"
    elif [[ "$line" == *"| DEBUG"* ]]; then
        # Cyan for debug
        echo -e "\033[0;36m$line\033[0m"
    elif [[ "$line" == *"==="* ]] || [[ "$line" == *"---"* ]]; then
        # Bold for separators
        echo -e "\033[1m$line\033[0m"
    elif [[ "$line" == *"✓"* ]]; then
        # Green for success markers
        echo -e "\033[0;32m$line\033[0m"
    elif [[ "$line" == *"✗"* ]]; then
        # Red for failure markers
        echo -e "\033[0;31m$line\033[0m"
    else
        # Default color
        echo "$line"
    fi
done
