#!/bin/sh
# Launch all 3 waybar instances with proper environment

# Get DBUS from labwc process
DBUS_ADDR=$(cat /proc/$(pgrep -x labwc)/environ 2>/dev/null | tr '\0' '\n' | grep DBUS_SESSION_BUS_ADDRESS | head -1)
export "$DBUS_ADDR"
export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
export WAYLAND_DISPLAY=wayland-0

pkill waybar
sleep 0.5

waybar -c "$HOME/.config/waybar/config_top" -s "$HOME/.config/waybar/style_top.css" &
waybar -c "$HOME/.config/waybar/config_right" -s "$HOME/.config/waybar/style_right.css" &
waybar -c "$HOME/.config/waybar/config" -s "$HOME/.config/waybar/style.css" &
