#!/bin/bash
# cmd-enter-claude.sh — runs until you press Ctrl+C
APP="Claude"
INTERVAL=1

trap 'echo; echo "Stopped."; exit 0' INT TERM

echo "Running: Cmd+Enter every ${INTERVAL}s while $APP is in front. Ctrl+C to stop."

while true; do
  sleep "$INTERVAL"
  FRONT=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true')
  if [ "$FRONT" = "$APP" ]; then
    osascript -e 'tell application "System Events" to key code 36 using command down'
  fi
done
