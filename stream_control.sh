#!/bin/bash
# Control script for the CameraPi4 streaming service
# Usage: ./stream_control.sh [start|stop|restart|status]

SERVICE_NAME="camerapi-stream.service"
LOG_DIR="/home/pi/steamcam/logs"
LOG_FILE="$LOG_DIR/camera_stream.log"

# Ensure log directory exists
mkdir -p $LOG_DIR
touch $LOG_FILE

case "$1" in
  start)
    echo "Starting CameraPi4 streaming..."
    # Remove the intentional stop flag if it exists
    sudo rm -f /tmp/stream_stopped_intentionally
    sudo systemctl start $SERVICE_NAME
    echo "Service started"
    ;;
    
  stop)
    echo "Stopping CameraPi4 streaming..."
    
    # Create intentional stop flag (used by the service)
    sudo touch /tmp/stream_stopped_intentionally
    
    # Kill the processes first (more reliable than waiting for systemd)
    echo "Killing streaming processes..."
    sudo killall -9 ffmpeg libcamera-vid 2>/dev/null
    
    # Find and kill the script directly
    SCRIPT_PID=$(pgrep -f "camera_stream.sh")
    if [ -n "$SCRIPT_PID" ]; then
      echo "Killing script PID: $SCRIPT_PID"
      sudo kill -9 $SCRIPT_PID 2>/dev/null
    fi
    
    # Now stop the service with a timeout
    echo "Stopping systemd service..."
    timeout 5 sudo systemctl stop $SERVICE_NAME
    
    # Double-check that everything is dead
    if pgrep -f "ffmpeg|libcamera-vid|camera_stream.sh" > /dev/null; then
      echo "Some processes still running, forcing termination..."
      sudo killall -9 ffmpeg libcamera-vid 2>/dev/null
      SCRIPT_PID=$(pgrep -f "camera_stream.sh")
      if [ -n "$SCRIPT_PID" ]; then
        sudo kill -9 $SCRIPT_PID 2>/dev/null
      fi
    fi
    
    echo "Stream stopped"
    ;;
    
  restart)
    echo "Restarting CameraPi4 streaming..."
    $0 stop
    sleep 3
    $0 start
    ;;
    
  status)
    echo "Checking CameraPi4 streaming service status..."
    sudo systemctl status $SERVICE_NAME
    
    # Show quick status summary
    if systemctl is-active --quiet $SERVICE_NAME; then
      echo "✓ Service is active and running"
    else
      echo "✗ Service is not active"
      # Check if it was intentionally stopped
      if [ -f /tmp/stream_stopped_intentionally ]; then
        echo "  (Service was intentionally stopped)"
      fi
    fi
    
    # Check if the streaming processes are running
    if pgrep -x "libcamera-vid" > /dev/null; then
      echo "✓ Camera process (libcamera-vid) is running"
    else
      echo "✗ Camera process is NOT running"
    fi
    
    if pgrep -x "ffmpeg" > /dev/null; then
      echo "✓ FFmpeg process is running"
    else
      echo "✗ FFmpeg process is NOT running"
    fi
    
    # Show latest log entries
    echo "Latest log entries:"
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
      tail -n 10 "$LOG_FILE"
    else
      echo "Log file does not exist or is empty."
    fi
    ;;
    
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

exit 0
