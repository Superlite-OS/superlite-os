#!/bin/bash
# build-superlite-files.sh — Build SuperLite Files on Ubuntu (glibc binary)
# Produces a glibc binary that works with glibc webkit2gtk on Alpine

OUTPUT="/tmp/superlite-files-glibc"
BUILDLOG="/tmp/superlite-files-build.log"
SRC="${1:-${GITHUB_WORKSPACE:-$(pwd)}/vendor/superlite-files}"

export RUSTUP_HOME=${RUSTUP_HOME:-$HOME/.rustup}
export CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}

log() { echo "[slf-build] $*"; }

# ── Stage 1: Install Rust via rustup ─────────────────────────────────────
log "=== Stage 1: Install Rust ==="
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 | tail -5
fi
export PATH="$CARGO_HOME/bin:$PATH"
log "Rust: $(rustc --version 2>&1)"

# ── Stage 2: Install Node.js + pnpm ──────────────────────────────────────
log "=== Stage 2: Install Node.js + pnpm ==="
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | tail -3
    apt-get install -y nodejs 2>&1 | tail -3
fi
npm install -g pnpm@9 2>&1 | tail -3
log "Node: $(node --version 2>&1), pnpm: $(pnpm --version 2>&1)"

# ── Stage 3: Install Tauri system dependencies ──────────────────────────
log "=== Stage 3: Install Tauri deps ==="
apt-get update -qq 2>&1 | tail -3
apt-get install -y \
    libwebkit2gtk-4.1-dev \
    libgtk-3-dev \
    libglib2.0-dev \
    libgdk-pixbuf-2.0-dev \
    libpango1.0-dev \
    libcairo2-dev \
    libharfbuzz-dev \
    libfontconfig-dev \
    libsoup-3.0-dev \
    libxml2-dev \
    libx11-dev \
    libxext-dev \
    libxrandr-dev \
    libxcursor-dev \
    libxi-dev \
    libxcomposite-dev \
    libxdamage-dev \
    libxfixes-dev \
    libatk1.0-dev \
    libatspi2.0-dev \
    libssl-dev \
    build-essential \
    pkg-config \
    file \
    patchelf \
    2>&1 | tail -5

# ── Stage 4: Find source ─────────────────────────────────────────────────
log "=== Stage 4: Find source ==="
if [ ! -d "$SRC" ]; then
    log "ERROR: Source not found at $SRC"
    exit 1
fi
cd "$SRC"

# ── Stage 5: Install frontend dependencies ───────────────────────────────
log "=== Stage 5: pnpm install ==="
cat > pnpm-workspace.yaml <<'WSYAML'
packages:
  - '.'
WSYAML
pnpm install 2>&1 | tail -10 || {
    log "ERROR: pnpm install failed"
    exit 1
}

# ── Stage 6: Build Tauri app ─────────────────────────────────────────────
log "=== Stage 6: Build SuperLite Files (release) ==="
export PATH="$CARGO_HOME/bin:$PATH"

pnpm tauri build 2>&1 | tee "$BUILDLOG"
BUILD_RC=$?

if [ $BUILD_RC -ne 0 ]; then
    log "ERROR: tauri build failed (exit=$BUILD_RC)"
    tail -50 "$BUILDLOG"
    exit 1
fi

# ── Stage 7: Package artifacts ───────────────────────────────────────────
log "=== Stage 7: Package ==="

BIN="src-tauri/target/release/superlite-files"
if [ ! -f "$BIN" ]; then
    BIN=$(find src-tauri/target -name "superlite-files" -type f -executable 2>/dev/null | head -1)
fi

if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
    log "ERROR: binary not found"
    find src-tauri/target -name "superlite*" -type f 2>/dev/null | head -10
    exit 1
fi

log "Found: $BIN"
file "$BIN"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin"
cp -v "$BIN" "$OUTPUT/usr/bin/superlite-files"
chmod +x "$OUTPUT/usr/bin/superlite-files"

log "=== Done ==="
ls -la "$OUTPUT/usr/bin/superlite-files"

# Cleanup
rm -rf src-tauri/target/release/build src-tauri/target/release/deps
rm -rf src-tauri/target/release/examples src-tauri/target/release/incremental

log "SuperLite Files build complete!"
