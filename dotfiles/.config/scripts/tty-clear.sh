#!/bin/sh
# SuperLite OS — Clear all terminal scrollback buffers
# Linux equivalent of mac-tty-cleaner
# Clears screen + scrollback on all active /dev/pts/* sessions

COUNT=0
for tty in /dev/pts/*; do
    [ -w "$tty" ] || continue
    # \033[2J = clear screen, \033[3J = clear scrollback, \033[H = cursor home
    printf '\033[2J\033[3J\033[H' > "$tty" 2>/dev/null && COUNT=$((COUNT + 1))
done

notify-send -i utilities-terminal "Terminal Cleaned" "Cleared $COUNT terminal session(s)" 2>/dev/null
