#!/bin/bash
# Phase 1: Basic streaming script for CameraPi4
# Streams from IMX708 camera with ICS43434 audio to restream.io

# If this file exists, we were stopped intentionally - exit right away
if [ -f /tmp/stream_stopped_intentionally ]; then
    rm -f /tmp/stream_stopped_intentionally
    echo "Service was intentionally stopped - exiting without retry"
    exit 0
fi

# Create logging directory
LOG_DIR="/home/pi/steamcam/logs"
mkdir -p $LOG_DIR
LOG_FILE="$LOG_DIR/camera_stream.log"
echo "Starting IMX708 stream with built-in audio at $(date)" > "$LOG_FILE"

# Rest of your script continues as before...
# Configuration
STREAMING_KEY="re_5751192_event7ab5b3bad33544b0af06984c6db4cc23"
RETRY_LIMIT=5
RETRY_COUNT=0
RETRY_DELAY=10

# Function to clean up processes and pipes
cleanup() {
    echo "Performing cleanup..." >> "$LOG_FILE"
    killall -9 ffmpeg libcamera-vid 2>/dev/null
    if [ -n "$CAM_PID" ] && ps -p $CAM_PID > /dev/null; then
        kill $CAM_PID 2>/dev/null
    fi
    rm -f "$PIPE_FILE" 2>/dev/null
    echo "Cleanup completed at $(date)" >> "$LOG_FILE"
}

# Handle interrupts gracefully
trap cleanup EXIT INT TERM

# Make sure camera is not in use
echo "Stopping any existing camera processes..." >> "$LOG_FILE"
killall -9 ffmpeg libcamera-vid 2>/dev/null
sleep 2

# Set up video pipe
PIPE_FILE="/tmp/camera_pipe"
rm -f "$PIPE_FILE"
mkfifo "$PIPE_FILE"

# Main streaming function
start_stream() {
    # Start libcamera-vid with 180-degree rotation
    echo "Starting libcamera-vid at 720p/30fps with rotation..." >> "$LOG_FILE"
    libcamera-vid -t 0 --width 1280 --height 720 --framerate 30 --codec h264 --hflip --vflip -o "$PIPE_FILE" &
    CAM_PID=$!
    echo "Camera process started with PID: $CAM_PID" >> "$LOG_FILE"

    # Wait for camera to initialize
    sleep 2

    # Check if camera is actually running
    if ! ps -p $CAM_PID > /dev/null; then
        echo "ERROR: Camera process failed to start" >> "$LOG_FILE"
        return 1
    fi

    echo "Camera ready, starting FFmpeg with ICS43434 audio..." >> "$LOG_FILE"

    # Set keyframe interval to 2 seconds (60 frames at 30fps)
    KEYFRAME_INTERVAL=60

    ffmpeg -hide_banner -loglevel warning \
        -thread_queue_size 2048 -f h264 -i "$PIPE_FILE" \
        -thread_queue_size 2048 -f alsa -i plughw:1,0 -ac 1 \
        -sample_rate 44100 -use_wallclock_as_timestamps 1 \
        -map 0:v -map 1:a \
        -c:v libx264 -preset veryfast -b:v 2000k \
        -maxrate 2500k -bufsize 5000k \
        -g $KEYFRAME_INTERVAL -keyint_min $KEYFRAME_INTERVAL \
        -force_key_frames "expr:gte(t,n_forced*2)" \
        -af "aresample=44100:out_sample_fmt=s16:async=2000,volume=4.0" \
        -c:a aac -b:a 96k -ar 44100 \
        -f flv "rtmp://live.restream.io/live/$STREAMING_KEY" \
        >> "$LOG_FILE" 2>&1
        
    FFMPEG_STATUS=$?
    echo "FFmpeg exited with status: $FFMPEG_STATUS" >> "$LOG_FILE"

    # Check if we were stopped intentionally via the flag file
    if [ -f /tmp/stream_stopped_intentionally ]; then
        echo "Stream was stopped intentionally via control script" >> "$LOG_FILE"
        return 0  # Return success to prevent retry
    fi

    return $FFMPEG_STATUS
}

# Main retry loop
while [ $RETRY_COUNT -lt $RETRY_LIMIT ]; do
    echo "Stream attempt $((RETRY_COUNT+1))/$RETRY_LIMIT at $(date)" >> "$LOG_FILE"
    
    if start_stream; then
        echo "Stream ended normally at $(date)" >> "$LOG_FILE"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -lt $RETRY_LIMIT ]; then
            echo "Stream failed, retrying in $RETRY_DELAY seconds..." >> "$LOG_FILE"
            sleep $RETRY_DELAY
        else
            echo "Stream failed after $RETRY_LIMIT attempts, giving up at $(date)" >> "$LOG_FILE"
        fi
    fi
done

# Final cleanup
cleanup
echo "Script completed at $(date)" >> "$LOG_FILE"
