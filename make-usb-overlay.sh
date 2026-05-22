#!/bin/sh
# ============================================================================
# SuperLite OS — USB Overlay Partition Creator
# Add a writable ext4 partition to a flashed USB drive
#
# Usage: ./make-usb-overlay.sh /dev/sdX
#
# This creates a second partition using 100% of remaining space,
# formatted as ext4 with label SUPERLITE-RW.
# The live system's /sbin/init will auto-detect this partition
# and use it as the writable overlay instead of tmpfs.
# ============================================================================
set -e

usage() {
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Add a writable overlay partition to a SuperLite USB drive."
    echo "Run this AFTER flashing the ISO with dd/Rufus/Etcher."
    echo ""
    echo "Example: $0 /dev/sdb"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

DEVICE="$1"

# Validate device
if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

# Safety check — refuse if device looks like a system disk
for part in "${DEVICE}"*; do
    if mount | grep -q "$part "; then
        echo "Error: $DEVICE has mounted partitions. Unmount first."
        exit 1
    fi
done

# Check if partition 2 already exists
if [ -b "${DEVICE}2" ] || [ -b "${DEVICE}p2" ]; then
    echo "Partition 2 already exists on $DEVICE"
    echo "Format it as SUPERLITE-RW? [y/N]"
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 0
    fi
    # Determine correct partition name
    case "$DEVICE" in
        *nvme*|*mmcblk*) PART="${DEVICE}p2" ;;
        *)                PART="${DEVICE}2" ;;
    esac
    mkfs.ext4 -L SUPERLITE-RW -F "$PART"
    echo "Done. Partition $PART formatted as SUPERLITE-RW"
    exit 0
fi

echo "=== SuperLite USB Overlay Creator ==="
echo "Device: $DEVICE"
echo ""

# Show current partition table
echo "Current partition table:"
sfdisk -l "$DEVICE" 2>/dev/null || fdisk -l "$DEVICE"
echo ""

# Add partition 2 using all remaining space
echo "Adding partition 2 (writable overlay)..."
echo ", +" | sfdisk -a -N 2 "$DEVICE" 2>/dev/null || {
    # Fallback: use sfdisk append mode
    sfdisk --append "$DEVICE" <<EOF
;
EOF
}

# Determine correct partition name (nvme/mmcblk use p2 suffix)
case "$DEVICE" in
    *nvme*|*mmcblk*) PART="${DEVICE}p2" ;;
    *)                PART="${DEVICE}2" ;;
esac

# Wait for kernel to recognize new partition
sleep 1
partprobe "$DEVICE" 2>/dev/null || true
sleep 1

# Format as ext4
echo "Formatting $PART as ext4 (label: SUPERLITE-RW)..."
mkfs.ext4 -L SUPERLITE-RW -F "$PART"

echo ""
echo "=== Done ==="
echo "Partition $PART created and formatted."
echo "Boot SuperLite OS — the live system will auto-detect it."
