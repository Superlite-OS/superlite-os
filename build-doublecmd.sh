#!/bin/sh
# build-doublecmd.sh — Build Double Commander from source for musl + Qt5
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/doublecmd-musl/{usr/bin/doublecmd,lib/doublecmd/...}
#
# Requirements: Alpine 3.23 with qt5-qtbase-dev, qt5-qtx11extras-dev installed.
# FPC is installed here from edge/testing. Lazarus and libQt5Pas built from source.

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

# Build lazbuild — Lazarus command-line build tool
# Redirect to log to keep CI output clean (upstream Lazarus has many harmless warnings)
log "Building lazbuild..."
make lazbuild > "$BUILDLOG" 2>&1
MAKE_RC=$?

if [ $MAKE_RC -ne 0 ]; then
    log "ERROR: lazbuild make failed (exit=$MAKE_RC)"
    log "=== Last 30 lines of build log ==="
    tail -30 "$BUILDLOG"
fi

if [ ! -f lazbuild ] || [ ! -x lazbuild ]; then
    log "ERROR: lazbuild binary not found, trying alternative compile..."
    # Try alternative: compile lazbuild directly with FPC
    _LCL_UNITS="lcl/units/$(fpc -iTP)-$(fpc -iTO)"
    _LAZUTILS="components/lazutils/lib/$(fpc -iTP)-$(fpc -iTO)"
    if [ -d "$_LCL_UNITS" ] && [ -d "$_LAZUTILS" ]; then
        fpc -dRELEASE \
            -FiLCL -FiLCL/forms \
            -Fu"$_LCL_UNITS" \
            -Fu"$_LAZUTILS" \
            -Fu"$_LCL_UNITS/$(fpc -iSP)" \
            -FE. \
            tools/lazbuild/lazbuild.lpr > "$BUILDLOG" 2>&1
    fi
fi

LAZBUILD="$(pwd)/lazbuild"
if [ ! -x "$LAZBUILD" ]; then
    log "FATAL: lazbuild could not be built. Full log at $BUILDLOG"
    exit 1
fi
log "lazbuild built: $LAZBUILD"

# ── Stage 4: Build libQt5Pas ──────────────────────────────────────────────
log "=== Stage 4: Build libQt5Pas ==="
cd "$LAZARUS_SRC/lcl/interfaces/qt5/cbindings"
if [ -f build.sh ]; then
    sh build.sh > "$BUILDLOG" 2>&1
fi

if [ -f libQt5Pas.so ]; then
    cp -v libQt5Pas.so /usr/lib/
    ldconfig /usr/lib 2>/dev/null || true
    log "libQt5Pas installed to /usr/lib/"
else
    log "WARNING: libQt5Pas not built from cbindings, trying manual compile..."
    # Find all .c files and compile
    gcc -shared -fPIC -O2 -o /usr/lib/libQt5Pas.so \
        $(find . -name '*.c') \
        -I. -I../../.. \
        $(pkg-config --cflags --libs Qt5Core Qt5Gui Qt5Widgets Qt5X11Extras 2>/dev/null) \
        > "$BUILDLOG" 2>&1
    if [ -f /usr/lib/libQt5Pas.so ]; then
        log "libQt5Pas built manually"
    else
        log "ERROR: libQt5Pas could not be built"
        exit 1
    fi
fi

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

export lcl=qt5
export CPU_TARGET=x86_64
export lazbuild="$LAZBUILD"
# doublecmd's build.sh does `export lazbuild=$(which lazbuild)` which overrides
# our variable. Put lazbuild in PATH so `which` finds it.
export PATH="$(dirname "$LAZBUILD"):$PATH"
# lazbuild needs environmentoptions.xml to find Lazarus directory
mkdir -p "$HOME/.lazarus"
cat > "$HOME/.lazarus/environmentoptions.xml" <<XMLEOF
<?xml version="1.0"?>
<CONFIG>
  <EnvironmentOptions>
    <Version Value="110"/>
    <LazarusDirectory Value="$LAZARUS_SRC"/>
    <CompilerFilename Value="$(which fpc)"/>
    <TestBuildDirectory Value="/tmp/"/>
  </EnvironmentOptions>
</CONFIG>
XMLEOF
log "Created ~/.lazarus/environmentoptions.xml pointing to $LAZARUS_SRC"

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
./build.sh release qt5 > "$BUILDLOG" 2>&1
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

# libQt5Pas.so (doublecmd needs it at runtime)
cp -v /usr/lib/libQt5Pas.so "$OUTPUT/lib/doublecmd/" 2>/dev/null || true

log "=== Artifacts ==="
ls -la "$OUTPUT/usr/bin/doublecmd"
ls -la "$OUTPUT/lib/doublecmd/"

# ── Cleanup ───────────────────────────────────────────────────────────────
log "=== Cleanup ==="
rm -rf "$LAZARUS_SRC"
[ "$DC_SRC" = "/tmp/_dc_build" ] && rm -rf "$DC_SRC"
apk del fpc 2>/dev/null || true

log "Doublecmd build complete!"
