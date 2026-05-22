#!/bin/sh
current=$(cat /tmp/current-workspace 2>/dev/null || echo 1)
if [ "$current" = "1" ]; then printf "●"; else printf "○"; fi
