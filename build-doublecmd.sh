#!/bin/sh
# build-doublecmd.sh — Build Double Commander from source for musl + GTK2
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/doublecmd-musl/{usr/bin/doublecmd,lib/doublecmd/...}
#
# Requirements: Alpine 3.23 with gtk+2.0-dev installed.
# FPC is installed here from edge/testing. Lazarus built from source.

LAZARUS_MAJOR="4"
LAZARUS_MINOR="0"
LAZARUS_TAG="lazarus_${LAZARUS_MAJOR}_${LAZARUS_MINOR}"
LAZARUS_SRC="/tmp/_lazarus_build"
OUTPUT="/tmp/doublecmd-musl"
BUILDLOG="/tmp/doublecmd-build.log"

log() { echo "[doublecmd-build] $*"; }

# Don't use set -e — we need to handle errors manually for better diagnostics

# ── Stage 1: Install FPC from edge/testing ────────────────────────────────
log "=== Stage 1: Install FPC ==="
apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing fpc || {
    log "ERROR: Failed to install fpc"
    exit 1
}
FPC_VER=$(fpc -iV 2>&1)
log "FPC installed: $FPC_VER"

# ── Stage 2: Install Lazarus build deps ───────────────────────────────────
log "=== Stage 2: Install Lazarus build deps ==="
apk add --no-cache \
    gtk+2.0-dev glib-dev gdk-pixbuf-dev pango-dev cairo-dev \
    xorgproto libx11-dev libxext-dev \
    gcc musl-dev \
    2>&1 | tail -3

# ── Stage 3: Download + Build Lazarus ─────────────────────────────────────
log "=== Stage 3: Build Lazarus ${LAZARUS_MAJOR}.${LAZARUS_MINOR} ==="
rm -rf "$LAZARUS_SRC"
mkdir -p "$LAZARUS_SRC"
cd "$LAZARUS_SRC"

wget -q "https://gitlab.com/freepascal.org/lazarus/lazarus/-/archive/${LAZARUS_TAG}/lazarus-${LAZARUS_TAG}.tar.gz" \
    -O lazarus.tar.gz || {
    log "ERROR: Failed to download Lazarus from GitLab"
    exit 1
}
tar xzf lazarus.tar.gz --strip-components=1
rm -f lazarus.tar.gz
log "Lazarus source extracted"

# Build and install Lazarus (make all builds lazbuild + LCL + Qt5 bindings)
# This matches doublecmd's official CI approach
log "Building Lazarus (make all)..."
make all > "$BUILDLOG" 2>&1
MAKE_RC=$?

if [ $MAKE_RC -ne 0 ]; then
    log "ERROR: Lazarus make all failed (exit=$MAKE_RC)"
    log "=== Last 30 lines of build log ==="
    tail -30 "$BUILDLOG"
    exit 1
fi

log "Installing Lazarus to /usr/local/share/lazarus..."
make install > "$BUILDLOG" 2>&1
MAKE_RC=$?

if [ $MAKE_RC -ne 0 ]; then
    log "ERROR: Lazarus make install failed (exit=$MAKE_RC)"
    log "=== Last 30 lines of build log ==="
    tail -30 "$BUILDLOG"
    exit 1
fi

LAZBUILD="/usr/local/bin/lazbuild"
if [ ! -x "$LAZBUILD" ]; then
    log "FATAL: lazbuild not found at $LAZBUILD after make install"
    exit 1
fi
log "Lazarus installed: lazbuild at $LAZBUILD"

# ── Stage 5: Build Double Commander ───────────────────────────────────────
log "=== Stage 5: Build Double Commander ==="

# Use vendored source if available (pinned version), otherwise clone
if [ -d "/build/vendor/doublecmd" ] && [ -f "/build/vendor/doublecmd/build.sh" ]; then
    log "Using vendored source from /build/vendor/doublecmd"
    DC_SRC="/build/vendor/doublecmd"
else
    log "Cloning doublecmd source..."
    DC_SRC="/tmp/_dc_build"
    mkdir -p "$DC_SRC"
    git clone --depth=1 https://github.com/doublecmd/doublecmd.git "$DC_SRC" 2>&1 | tail -3
fi
cd "$DC_SRC"

export lcl=gtk2
export CPU_TARGET=x86_64
export lazbuild="$LAZBUILD"
# doublecmd's build.sh does `export lazbuild=$(which lazbuild)` which overrides
# our variable. Put lazbuild in PATH so `which` finds it.
export PATH="$(dirname "$LAZBUILD"):$PATH"
# lazbuild needs environmentoptions.xml to find Lazarus directory
# Copy from Lazarus install and fix paths (matches doublecmd CI approach)
mkdir -p "$HOME/.lazarus"
cp "$LAZARUS_SRC/tools/install/linux/environmentoptions.xml" "$HOME/.lazarus/"
sed -i "s|__LAZARUSDIR__|/usr/local/share/lazarus|g" "$HOME/.lazarus/environmentoptions.xml"
log "Created ~/.lazarus/environmentoptions.xml pointing to /usr/local/share/lazarus"

# Apply musl compatibility patches
if [ -f "/build/patch-doublecmd-musl.sh" ]; then
    sh /build/patch-doublecmd-musl.sh "$DC_SRC"
fi

log "Building doublecmd with widgetset=$lcl..."
# Ensure calling.inc is findable by DSXLocate plugin
if [ -f "$DC_SRC/sdk/calling.inc" ] && [ ! -f "$DC_SRC/plugins/dsx/DSXLocate/src/calling.inc" ]; then
    cp "$DC_SRC/sdk/calling.inc" "$DC_SRC/plugins/dsx/DSXLocate/src/"
    log "Copied calling.inc to DSXLocate plugin directory"
fi
./build.sh release gtk2 > "$BUILDLOG" 2>&1
DC_RC=$?

if [ $DC_RC -ne 0 ]; then
    log "ERROR: doublecmd build failed (exit=$DC_RC)"
    log "=== Last 30 lines of build log ==="
    tail -30 "$BUILDLOG"
    exit 1
fi

# Find the binary
DC_BIN=""
if [ -f doublecmd ]; then
    DC_BIN="./doublecmd"
else
    DC_BIN=$(find . -maxdepth 3 -name doublecmd -type f ! -name '*.lpi' ! -name '*.lpr' ! -name '*.pas' | head -1)
fi

if [ -z "$DC_BIN" ] || [ ! -f "$DC_BIN" ]; then
    log "ERROR: doublecmd binary not found. Build log at $BUILDLOG"
    exit 1
fi

log "Doublecmd built successfully"
file "$DC_BIN"
ldd "$DC_BIN" 2>&1 | head -10 || true

# ── Stage 6: Package artifacts ────────────────────────────────────────────
log "=== Stage 6: Package artifacts ==="
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin" "$OUTPUT/lib/doublecmd"

# Main binary
cp -v "$DC_BIN" "$OUTPUT/usr/bin/doublecmd"
chmod +x "$OUTPUT/usr/bin/doublecmd"

# Shared libraries
for f in *.so *.so.*; do
    [ -f "$f" ] || continue
    cp -v "$f" "$OUTPUT/lib/doublecmd/"
done

# Plugins directory
[ -d plugins ] && cp -a plugins "$OUTPUT/lib/doublecmd/"

# Translation files and pixmaps
for d in language pixmaps; do
    [ -d "$d" ] && cp -a "$d" "$OUTPUT/lib/doublecmd/"
done

# libQt5Pas.so (not needed for gtk2, but copy if exists for other tools)
cp -v /usr/local/lib/libQt5Pas.so "$OUTPUT/lib/doublecmd/" 2>/dev/null || true

log "=== Artifacts ==="
ls -la "$OUTPUT/usr/bin/doublecmd"
ls -la "$OUTPUT/lib/doublecmd/"

# ── Cleanup ───────────────────────────────────────────────────────────────
log "=== Cleanup ==="
rm -rf "$LAZARUS_SRC"
[ "$DC_SRC" = "/tmp/_dc_build" ] && rm -rf "$DC_SRC"
apk del fpc 2>/dev/null || true

log "Doublecmd build complete!"
