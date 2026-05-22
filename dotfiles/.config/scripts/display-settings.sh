#!/bin/sh
# SuperLite OS — Display Settings (tofi full-screen)
# Scale and resolution control

# Set environment if not already set (needed when launched from labwc menu)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/0-runtime-dir}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

OUTPUT=$(wlr-randr | head -1 | awk '{print $1}')
CURRENT_SCALE=$(wlr-randr | grep "Scale:" | awk '{print $2}')
CURRENT_MODE=$(wlr-randr | grep -oP '\d+x\d+ px.*current' | grep -oP '\d+x\d+')
MODES=$(wlr-randr | grep -oP '\d+x\d+ px' | grep -oP '\d+x\d+' | sort -u)

MENU="Zoom In (+0.25)
Zoom Out (-0.25)
Scale 1.0x (Native)
Scale 1.25x
Scale 1.5x
Scale 1.75x
Scale 2.0x"

for m in $MODES; do
    MENU="$MENU
Resolution ${m}"
done

MENU="$MENU
Current: ${CURRENT_MODE} @ ${CURRENT_SCALE}x"

CHOICE=$(printf "%s\n" "$MENU" | tofi -c "$HOME/.config/tofi/config_display" "$@")

case "$CHOICE" in
    "Zoom In"*)
        NEW=$(echo "$CURRENT_SCALE + 0.25" | bc)
        wlr-randr --output "$OUTPUT" --scale "$NEW"
        ;;
    "Zoom Out"*)
        NEW=$(echo "$CURRENT_SCALE - 0.25" | bc)
        [ "$(echo "$NEW < 0.5" | bc)" -eq 1 ] && NEW=0.5
        wlr-randr --output "$OUTPUT" --scale "$NEW"
        ;;
    "Scale 1.0x"*)
        wlr-randr --output "$OUTPUT" --scale 1
        ;;
    "Scale 1.25x"*)
        wlr-randr --output "$OUTPUT" --scale 1.25
        ;;
    "Scale 1.5x"*)
        wlr-randr --output "$OUTPUT" --scale 1.5
        ;;
    "Scale 1.75x"*)
        wlr-randr --output "$OUTPUT" --scale 1.75
        ;;
    "Scale 2.0x"*)
        wlr-randr --output "$OUTPUT" --scale 2
        ;;
    "Resolution "*)
        MODE=$(echo "$CHOICE" | sed 's/Resolution //')
        wlr-randr --output "$OUTPUT" --mode "${MODE}@60"
        ;;
esac
