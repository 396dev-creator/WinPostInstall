#!/bin/bash
# Keep the WinPostInstall dev server running for testing
# Run with: bash /home/z/my-project/scripts/keep-alive.sh &

PROJECT_DIR="/home/z/my-project"
LOG_FILE="$PROJECT_DIR/dev.log"
HEALTH_URL="http://localhost:3000"
CHECK_INTERVAL=30  # seconds

echo "[keep-alive] Monitoring dev server at $HEALTH_URL every ${CHECK_INTERVAL}s"

while true; do
  # Check if server responds
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null)
  
  if [ "$HTTP_CODE" != "200" ]; then
    echo "[keep-alive] Server down (HTTP $HTTP_CODE). Restarting..."
    
    # Kill any existing process on port 3000
    PID=$(lsof -t -i :3000 2>/dev/null)
    if [ -n "$PID" ]; then
      kill -9 $PID 2>/dev/null
      sleep 2
    fi
    
    # Restart dev server
    cd "$PROJECT_DIR"
    nohup bun run dev > "$LOG_FILE" 2>&1 &
    echo "[keep-alive] Restarted with PID $!"
    
    # Wait for it to come up
    for i in $(seq 1 12); do
      sleep 5
      CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null)
      if [ "$CODE" = "200" ]; then
        echo "[keep-alive] Server is back up!"
        break
      fi
    done
  fi
  
  sleep $CHECK_INTERVAL
done
