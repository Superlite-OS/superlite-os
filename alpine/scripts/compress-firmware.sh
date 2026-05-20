#!/bin/sh
# ============================================================================
# SuperLite OS — Firmware Compression & Optimization
# Reduces firmware size using xz compression
# ============================================================================
# Since we use Alpine's modular linux-firmware-* subpackages instead of the
# monolithic linux-firmware, we only have what we need. This script just
# compresses and deduplicates.
# ============================================================================

set -e

FIRMWARE_DIR="${1:-/lib/firmware}"
LIVE_LOG() { echo "[firmware] $*"; }

if [ ! -d "$FIRMWARE_DIR" ]; then
    LIVE_LOG "Firmware directory not found: $FIRMWARE_DIR (will be available after linux-firmware install)"
    exit 0
fi

BEFORE_SIZE=$(du -sm "$FIRMWARE_DIR" | cut -f1)
LIVE_LOG "Firmware size before optimization: ${BEFORE_SIZE}MB"

# ── Step 1: Remove duplicate firmware (keep .xz if both exist) ───────────────
LIVE_LOG "Removing duplicates..."
dup_count=0
while IFS= read -r xzfile; do
    [ -f "$xzfile" ] || continue
    base="${xzfile%.xz}"
    if [ -f "$base" ]; then
        rm -f "$base"
        dup_count=$((dup_count + 1))
    fi
done <<XZLIST
$(find "$FIRMWARE_DIR" -name "*.xz" -type f 2>/dev/null)
XZLIST

# ── Step 2: Compress uncompressed firmware with xz ──────────────────────────
LIVE_LOG "Compressing firmware with xz..."
compress_count=0
while IFS= read -r fwfile; do
    [ -f "$fwfile" ] || continue
    # Skip if too small to matter
    fsize=$(stat -c%s "$fwfile" 2>/dev/null || stat -f%z "$fwfile" 2>/dev/null || echo 0)
    [ "$fsize" -lt 4096 ] && continue
    # Compress with xz (kernel supports xz-compressed firmware since 5.3+)
    if xz -T1 -f "$fwfile" 2>/dev/null; then
        compress_count=$((compress_count + 1))
    fi
done <<FWLIST
$(find "$FIRMWARE_DIR" -type f \( -name "*.bin" -o -name "*.fw" -o -name "*.img" -o -name "*.ucode" \) ! -name "*.xz" ! -name "*.zst" 2>/dev/null)
FWLIST

LIVE_LOG "Compressed $compress_count firmware files"

# ── Step 3: Remove unnecessary files ────────────────────────────────────────
LIVE_LOG "Cleaning up..."
find "$FIRMWARE_DIR" -name "README*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "WHENCE*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "LICENCE*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "LICENSE*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "*.txt" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "*.htm*" -delete 2>/dev/null || true

# Remove empty directories
find "$FIRMWARE_DIR" -type d -empty -delete 2>/dev/null || true

# ── Final report ─────────────────────────────────────────────────────────────
AFTER_SIZE=$(du -sm "$FIRMWARE_DIR" | cut -f1)
SAVED=$((BEFORE_SIZE - AFTER_SIZE))
LIVE_LOG "Firmware size after optimization: ${AFTER_SIZE}MB (saved ${SAVED}MB)"
