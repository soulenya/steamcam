#!/bin/bash
# Health check script for the streaming service

# Configuration
LOG_DIR="/home/pi/steamcam/logs"
CHECK_LOG="$LOG_DIR/health_check.log"
SERVICE_NAME="camerapi-stream.service"
MAX_LOG_SIZE=10485760  # 10MB in bytes

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Rotate logs if they get too large
if [ -f "$CHECK_LOG" ] && [ $(stat -c%s "$CHECK_LOG") -gt $MAX_LOG_SIZE ]; then
    mv "$CHECK_LOG" "${CHECK_LOG}.old"
    touch "$CHECK_LOG"
    echo "Log rotated at $(date)" > "$CHECK_LOG"
fi

# Function to check if a process is running
check_process() {
    NAME=$1
    if pgrep -x "$NAME" > /dev/null; then
        echo "✓ $NAME is running"
        return 0
    else
        echo "✗ $NAME is NOT running"
        return 1
    fi
}

# Start the health check
echo "======== Stream Health Check: $(date) ========" | tee -a "$CHECK_LOG"

# Check if the service is running
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✓ $SERVICE_NAME is active" | tee -a "$CHECK_LOG"
else
    echo "✗ $SERVICE_NAME is NOT active" | tee -a "$CHECK_LOG"
    echo "Last service log entries:" | tee -a "$CHECK_LOG"
    journalctl -u "$SERVICE_NAME" -n 10 | tee -a "$CHECK_LOG"
fi

# Check important processes
check_process "libcamera-vid" | tee -a "$CHECK_LOG"
check_process "ffmpeg" | tee -a "$CHECK_LOG"

# Check network connectivity to restream.io
echo "Testing network connectivity to restream.io..." | tee -a "$CHECK_LOG"
if ping -c 1 live.restream.io > /dev/null 2>&1; then
    echo "✓ Network connection to restream.io is OK" | tee -a "$CHECK_LOG"
else
    echo "✗ Cannot reach restream.io" | tee -a "$CHECK_LOG"
fi

# Check disk space
DISK_SPACE=$(df -h / | awk 'NR==2 {print $5}')
echo "Disk usage: $DISK_SPACE" | tee -a "$CHECK_LOG"

echo "Health check completed" | tee -a "$CHECK_LOG"
