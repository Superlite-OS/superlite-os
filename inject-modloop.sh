#!/bin/sh
# ============================================================================
# SuperLite OS — Modloop Extras Injector
# Injects heavy binaries into modloop squashfs after mkimage.sh builds ISO.
# Called by build.sh. Runs inside Docker container or on native Alpine host.
#
# Usage: inject-modloop.sh <output_dir> [repo_dir]
# ============================================================================
set -e

OUTPUT_DIR="$1"
REPO_DIR="${2:-$(cd "$(dirname "$0")" && pwd)}"

if [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <output_dir> [repo_dir]"
    exit 1
fi

log() { echo "[inject] $*"; }

# Find ISO
ISO_FILE=$(find "$OUTPUT_DIR" -name "*.iso" -type f | head -1)
if [ -z "$ISO_FILE" ]; then
    log "ERROR: No ISO found in $OUTPUT_DIR"
    exit 1
fi
log "Processing: $ISO_FILE ($(du -sh "$ISO_FILE" | cut -f1))"

# Temp workspace
TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Extract ISO contents via xorriso
log "Extracting ISO..."
xorriso -indev "$ISO_FILE" -osirrox on -extract / "$TMPDIR" >/dev/null 2>&1

MODLOOP="$TMPDIR/boot/modloop-lts"
if [ ! -f "$MODLOOP" ]; then
    log "ERROR: modloop-lts not found in ISO"
    exit 1
fi

# Unsquashfs into temp
SQFS="$TMPDIR/squashfs-root"
OLD_SIZE=$(du -sh "$MODLOOP" | cut -f1)
log "Unsquashing modloop ($OLD_SIZE)..."
unsquashfs -q -d "$SQFS" "$MODLOOP"
rm "$MODLOOP"

# ── Build zapt (Go static binary) ──────────────────────────────────────────
ZAPT_DIR=""
for d in "$REPO_DIR/zapt" "./zapt"; do
    [ -d "$d" ] && [ -f "$d/main.go" ] && ZAPT_DIR="$d" && break
done

if [ -n "$ZAPT_DIR" ] && command -v go >/dev/null 2>&1; then
    log "Building zapt..."
    (cd "$ZAPT_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -buildvcs=false -ldflags="-s -w" -o "$SQFS/usr/local/bin/zapt" .) || {
        log "WARNING: zapt build failed"
    }
    mkdir -p "$SQFS/etc/zapt"
    [ -f "$ZAPT_DIR/etc/sources.conf" ] && \
        cp "$ZAPT_DIR/etc/sources.conf" "$SQFS/etc/zapt/sources.conf"
else
    log "WARNING: zapt not built (Go or source not available)"
fi

# ── curl-impersonate (glibc binary, needs gcompat) ─────────────────────────
CURL_VER="0.6.1"
CURL_URL="https://github.com/lwthiker/curl-impersonate/releases/download/v${CURL_VER}/curl-impersonate-v${CURL_VER}.x86_64-linux-gnu.tar.gz"
log "Installing curl-impersonate..."
wget -q -O /tmp/curl-imp.tar.gz "$CURL_URL" 2>/dev/null || true
if [ -f /tmp/curl-imp.tar.gz ]; then
    mkdir -p "$SQFS/usr/local/lib/curl-impersonate"
    tar -xzf /tmp/curl-imp.tar.gz -C "$SQFS/usr/local/lib/curl-impersonate" 2>/dev/null || true
    if [ -f "$SQFS/usr/local/lib/curl-impersonate/curl-impersonate-chrome" ]; then
        chmod +x "$SQFS/usr/local/lib/curl-impersonate/curl-impersonate-chrome"
        mkdir -p "$SQFS/usr/local/bin"
        ln -sf /usr/local/lib/curl-impersonate/curl-impersonate-chrome \
            "$SQFS/usr/local/bin/curl-impersonate-chrome"
        ln -sf /usr/local/bin/curl-impersonate-chrome "$SQFS/usr/local/bin/curl"
        for w in "$SQFS"/usr/local/lib/curl-impersonate/curl_*; do
            [ -f "$w" ] || continue
            ln -sf "/usr/local/lib/curl-impersonate/$(basename "$w")" \
                "$SQFS/usr/local/bin/$(basename "$w")"
        done
        log "  curl-impersonate installed"
    fi
    rm -f /tmp/curl-imp.tar.gz
fi

# ── Google Chrome .deb + glibc deps ────────────────────────────────────────
log "Installing Chrome..."
CHROME_DEB="/tmp/google-chrome-stable.deb"
wget -q -O "$CHROME_DEB" \
    "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" 2>&1 || true
if [ -f "$CHROME_DEB" ] && [ -x "$SQFS/usr/local/bin/zapt" ]; then
    "$SQFS/usr/local/bin/zapt" install --root "$SQFS" "$CHROME_DEB" 2>&1 || {
        log "WARNING: Chrome install failed"
    }
    chmod 4755 "$SQFS/opt/google/chrome/chrome-sandbox" 2>/dev/null || true
    mkdir -p "$SQFS/usr/bin"
    ln -sf /opt/google/chrome/chrome "$SQFS/usr/bin/google-chrome-stable"
    ln -sf /opt/google/chrome/chrome "$SQFS/usr/bin/google-chrome"
    rm -f "$CHROME_DEB"
fi

# glibc ELF loader symlinks
if [ -f "$SQFS/usr/lib/glibc/ld-linux-x86-64.so.2" ]; then
    mkdir -p "$SQFS/lib64" "$SQFS/lib"
    ln -sf /usr/lib/glibc/ld-linux-x86-64.so.2 "$SQFS/lib64/ld-linux-x86-64.so.2"
    ln -sf /usr/lib/glibc/libc.so.6 "$SQFS/lib/libc.so.6"
    log "  glibc symlinks created"
fi

# ── Double Commander (Debian pool via zapt) ────────────────────────────────
if [ -x "$SQFS/usr/local/bin/zapt" ]; then
    log "Installing Double Commander..."
    "$SQFS/usr/local/bin/zapt" install --root "$SQFS" doublecmd-qt 2>&1 || {
        log "WARNING: Double Commander install failed"
    }
fi

# ── Repack squashfs ────────────────────────────────────────────────────────
log "Repacking modloop..."
mksquashfs "$SQFS" "$MODLOOP" -comp xz -b 1M -noappend >/dev/null 2>&1
NEW_SIZE=$(du -sh "$MODLOOP" | cut -f1)
rm -rf "$SQFS"

# ── Rebuild ISO (preserving boot) ──────────────────────────────────────────
NEW_ISO="${ISO_FILE%.iso}.new.iso"
log "Rebuilding ISO..."

# Find MBR for hybrid boot
MBR=""
for f in "$TMPDIR/boot/syslinux/isohdpfx.bin" \
         /usr/lib/syslinux/mbr/isohdpfx.bin \
         /usr/share/syslinux/isohdpfx.bin; do
    [ -f "$f" ] && MBR="$f" && break
done

_XORRISO_ARGS=""
if [ -n "$MBR" ]; then
    _XORRISO_ARGS="-isohybrid-mbr $MBR"
fi

xorriso -as mkisofs \
    -r -J \
    $_XORRISO_ARGS \
    -c boot/syslinux/boot.cat \
    -b boot/syslinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$NEW_ISO" \
    "$TMPDIR" >/dev/null 2>&1

mv "$NEW_ISO" "$ISO_FILE"
log "Done: $ISO_FILE ($(du -sh "$ISO_FILE" | cut -f1))"
log "Modloop: $OLD_SIZE -> $NEW_SIZE"
