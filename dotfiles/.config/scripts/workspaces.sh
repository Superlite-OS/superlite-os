#!/bin/sh
# SuperLite OS — Workspace indicator daemon
# Listens on /tmp/workspace pipe, writes state to /tmp/current-workspace

NUMBER=5
PIPE=/tmp/workspace

rm -f "$PIPE"
mkfifo "$PIPE"

current=1
echo "$current" > /tmp/current-workspace

while true; do
    # Read from pipe (blocks until someone writes)
    if read input < "$PIPE"; then
        case "$input" in
            [1-9])
                if [ "$input" -ge 1 ] && [ "$input" -le "$NUMBER" ]; then
                    current=$input
                fi
                ;;
            left)
                current=$((current - 1))
                [ "$current" -lt 1 ] && current=$NUMBER
                ;;
            right)
                current=$((current + 1))
                [ "$current" -gt "$NUMBER" ] && current=1
                ;;
        esac
        echo "$current" > /tmp/current-workspace
    fi
    # Loop back to read again (pipe reconnect)
done
