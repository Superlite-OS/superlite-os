#!/bin/sh
# build-doublecmd.sh — Build Double Commander from source for musl + Qt5
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/doublecmd-musl/{usr/bin/doublecmd,lib/doublecmd/...}
#
# Requirements: Alpine 3.23 with qt5-qtbase-dev, qt5-qtx11extras-dev installed.
# FPC is installed here from edge/testing. Lazarus and libQt5Pas built from source.

set -e

LAZARUS_VER="4.6"
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
fpc -v || { log "ERROR: fpc not working"; exit 1; }
log "FPC installed: $(fpc -iV)"

# ── Stage 2: Download + Build Lazarus ─────────────────────────────────────
log "Building Lazarus ${LAZARUS_VER}..."
mkdir -p "$LAZARUS_SRC"
cd "$LAZARUS_SRC"

# Download Lazarus source (not the binary — we build from source for musl)
wget -q "https://sourceforge.net/projects/lazarus/files/Lazarus%20Source/lazarus-${LAZARUS_VER}.tar.gz/download" \
    -O lazarus.tar.gz || {
    # Fallback: try GitHub mirror
    wget -q "https://github.com/nickg/lazarus/archive/refs/tags/v${LAZARUS_VER}.tar.gz" \
        -O lazarus.tar.gz 2>/dev/null || {
        log "ERROR: Failed to download Lazarus"
        exit 1
    }
}
tar xzf lazarus.tar.gz --strip-components=1
rm -f lazarus.tar.gz

# Build lazbuild (the Lazarus command-line build tool)
# We only need lazbuild, not the full IDE
make -j"$(nproc)" lazbuild 2>&1 | tail -3
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
    sh build.sh 2>&1 | tail -3
elif [ -f Makefile ]; then
    make -j"$(nproc)" 2>&1 | tail -3
else
    log "WARNING: No build script for Qt5 cbindings, trying manual compile"
    # Manual compile as fallback
    gcc -shared -fPIC -o libQt5Pas.so \
        -I/usr/include/qt5 -I/usr/include/qt5/QtCore -I/usr/include/qt5/QtGui -I/usr/include/qt5/QtWidgets \
        *.c -lQt5Core -lQt5Gui -lQt5Widgets -lQt5X11Extras 2>&1 | tail -5
fi

# Install libQt5Pas system-wide for doublecmd build
if [ -f libQt5Pas.so ]; then
    cp -v libQt5Pas.so /usr/lib/
    ldconfig /usr/lib 2>/dev/null || true
    log "libQt5Pas installed"
else
    log "ERROR: libQt5Pas not built"
    # List what's available for debugging
    ls -la
    exit 1
fi

# ── Stage 4: Build Double Commander ───────────────────────────────────────
log "Building Double Commander..."
mkdir -p "$DC_SRC"
cd "$DC_SRC"
git clone --depth=1 --recurse-submodules --shallow-submodules \
    https://github.com/doublecmd/doublecmd.git . 2>&1 | tail -3

export lcl=qt5
export CPU_TARGET=x86_64
export lazbuild="$LAZBUILD"

# Add -fPIC flag for musl
if [ -f /etc/fpc.cfg ]; then
    cp /etc/fpc.cfg .
    echo "-fPIC" >> fpc.cfg
    export PPC_CONFIG_PATH="$(pwd)"
fi

# Build components + doublecmd
"$LAZBUILD" --version 2>&1 | head -1 || true
./build.sh release qt5 2>&1 | tail -10

# Verify binary
if [ ! -f doublecmd ]; then
    log "ERROR: doublecmd binary not built"
    exit 1
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

# libQt5Pas.so (installed at /usr/lib but doublecmd needs it at its lib dir)
cp -v /usr/lib/libQt5Pas.so "$OUTPUT/lib/doublecmd/" 2>/dev/null || true

log "=== Artifacts ==="
ls -la "$OUTPUT/usr/bin/doublecmd"
ls -la "$OUTPUT/lib/doublecmd/"
echo ""

# ── Cleanup ───────────────────────────────────────────────────────────────
log "Cleaning up build deps..."
rm -rf "$LAZARUS_SRC" "$DC_SRC"
apk del fpc 2>/dev/null || true
# Keep qt5 packages — they're needed by other things

log "Doublecmd build complete!"
