#!/bin/sh
# build-doublecmd.sh — Build Double Commander from source for musl + Qt5
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/doublecmd-musl/{usr/bin/doublecmd,lib/doublecmd/...}
#
# Requirements: Alpine 3.23 with qt5-qtbase-dev, qt5-qtx11extras-dev installed.
# FPC is installed here from edge/testing. Lazarus and libQt5Pas built from source.

set -e

LAZARUS_VER="4.2"
LAZARUS_MAJOR="4"
LAZARUS_MINOR="2"
DC_SRC="/tmp/_dc_build"
LAZARUS_SRC="/tmp/_lazarus_build"
OUTPUT="/tmp/doublecmd-musl"

log() { echo "[doublecmd-build] $*"; }

# ── Stage 1: Install FPC from edge/testing ────────────────────────────────
log "Installing FPC compiler..."
apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing fpc || {
    log "ERROR: Failed to install fpc"
    exit 1
}
fpc -iV || { log "ERROR: fpc not working"; exit 1; }
log "FPC installed: $(fpc -iV)"

# ── Stage 2: Download + Build Lazarus ─────────────────────────────────────
log "Building Lazarus ${LAZARUS_VER}..."
mkdir -p "$LAZARUS_SRC"
cd "$LAZARUS_SRC"

# Download from GitLab (official Lazarus source)
LAZARUS_TAG="lazarus_${LAZARUS_MAJOR}_${LAZARUS_MINOR}"
wget -q "https://gitlab.com/freepascal.org/lazarus/lazarus/-/archive/${LAZARUS_TAG}/lazarus-${LAZARUS_TAG}.tar.gz" \
    -O lazarus.tar.gz || {
    log "ERROR: Failed to download Lazarus from GitLab"
    exit 1
}
tar xzf lazarus.tar.gz --strip-components=1
rm -f lazarus.tar.gz
log "Lazarus source extracted"

# Build lazbuild (the Lazarus command-line build tool)
make -j"$(nproc)" lazbuild 2>&1 | tail -5
LAZBUILD="$(pwd)/lazbuild"
if [ ! -x "$LAZBUILD" ]; then
    log "ERROR: lazbuild not built"
    exit 1
fi
log "lazbuild built: $LAZBUILD"

# ── Stage 3: Build libQt5Pas from Lazarus source ──────────────────────────
log "Building libQt5Pas..."
cd "$LAZARUS_SRC/lcl/interfaces/qt5/cbindings"
if [ -f build.sh ]; then
    sh build.sh 2>&1 | tail -5
fi

# Install libQt5Pas system-wide for doublecmd build
if [ -f libQt5Pas.so ]; then
    cp -v libQt5Pas.so /usr/lib/
    ldconfig /usr/lib 2>/dev/null || true
    log "libQt5Pas installed"
else
    log "WARNING: libQt5Pas not built, trying to find it..."
    find . -name 'libQt5Pas*' -type f 2>/dev/null
    # Try building manually
    gcc -shared -fPIC -o /usr/lib/libQt5Pas.so \
        -I/usr/include/qt5 -I/usr/include/qt5/QtCore -I/usr/include/qt5/QtGui \
        -I/usr/include/qt5/QtWidgets -I/usr/include/qt5/QtX11Extras \
        *.c -lQt5Core -lQt5Gui -lQt5Widgets -lQt5X11Extras 2>&1 | tail -5
fi

# ── Stage 4: Build Double Commander ───────────────────────────────────────
log "Building Double Commander..."

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

export lcl=qt5
export CPU_TARGET=x86_64
export lazbuild="$LAZBUILD"

# Build doublecmd
./build.sh release qt5 2>&1 | tail -10

# Verify binary
if [ ! -f doublecmd ]; then
    # Binary may be in a subdirectory
    _dc_bin=$(find . -name doublecmd -type f -executable | head -1)
    if [ -n "$_dc_bin" ]; then
        cp "$_dc_bin" ./doublecmd
    else
        log "ERROR: doublecmd binary not built"
        exit 1
    fi
fi

log "Doublecmd built successfully"
file doublecmd
ldd doublecmd 2>&1 | head -10 || true

# ── Stage 5: Package artifacts ────────────────────────────────────────────
log "Packaging artifacts to $OUTPUT..."
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin" "$OUTPUT/lib/doublecmd"

# Main binary
cp -v doublecmd "$OUTPUT/usr/bin/doublecmd"
chmod +x "$OUTPUT/usr/bin/doublecmd"

# Shared libraries
for f in *.so *.so.*; do
    [ -f "$f" ] || continue
    cp -v "$f" "$OUTPUT/lib/doublecmd/"
done

# Plugins directory
if [ -d plugins ]; then
    cp -a plugins "$OUTPUT/lib/doublecmd/"
fi

# Config files / translation files
for d in language pixmaps; do
    [ -d "$d" ] && cp -a "$d" "$OUTPUT/lib/doublecmd/"
done

# libQt5Pas.so (doublecmd needs it at runtime)
cp -v /usr/lib/libQt5Pas.so "$OUTPUT/lib/doublecmd/" 2>/dev/null || true

log "=== Artifacts ==="
ls -la "$OUTPUT/usr/bin/doublecmd"
ls -la "$OUTPUT/lib/doublecmd/"
echo ""

# ── Cleanup ───────────────────────────────────────────────────────────────
log "Cleaning up build deps..."
rm -rf "$LAZARUS_SRC"
# Only clean DC_SRC if it was a temp clone (not vendored)
[ "$DC_SRC" = "/tmp/_dc_build" ] && rm -rf "$DC_SRC"
apk del fpc 2>/dev/null || true

log "Doublecmd build complete!"
