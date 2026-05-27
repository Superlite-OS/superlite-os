#!/bin/sh
# build-terax.sh — Build Terax AI terminal from vendored source (musl native)
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/terax-musl/{usr/bin/terax, usr/lib/terax/...}
#
# Requirements: Alpine 3.23 with webkit2gtk-4.1-dev, rust, nodejs, pnpm.

OUTPUT="/tmp/terax-musl"
BUILDLOG="/tmp/terax-build.log"
TERAX_SRC="/build/vendor/terax-ai"

log() { echo "[terax-build] $*"; }

# ── Stage 1: Install Rust toolchain (via rustup, not Alpine rust pkg) ────
log "=== Stage 1: Install Rust ==="
# Alpine's rust package doesn't support proc-macro (dylib) crate types
# Must use rustup for proper proc-macro support (needed by Tauri/async-recursion)
apk add --no-cache curl gcc musl-dev 2>&1 | tail -3
export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 | tail -5
export PATH="$CARGO_HOME/bin:$PATH"
RUST_VER=$(rustc --version 2>&1)
log "Rust installed: $RUST_VER"

# ── Stage 2: Install Node.js + pnpm ──────────────────────────────────────
log "=== Stage 2: Install Node.js + pnpm ==="
apk add --no-cache nodejs npm 2>&1 | tail -3
npm install -g pnpm@9 2>&1 | tail -3
NODE_VER=$(node --version 2>&1)
PNPM_VER=$(pnpm --version 2>&1)
log "Node.js: $NODE_VER, pnpm: $PNPM_VER"

# ── Stage 3: Install Tauri build dependencies ────────────────────────────
log "=== Stage 3: Install Tauri deps ==="
apk add --no-cache \
    webkit2gtk-4.1-dev \
    gtk+3.0-dev \
    glib-dev \
    gdk-pixbuf-dev \
    pango-dev \
    cairo-dev \
    harfbuzz-dev \
    fontconfig-dev \
    libsoup3-dev \
    libxml2-dev \
    xorgproto \
    libx11-dev \
    libxext-dev \
    libxrandr-dev \
    libxcursor-dev \
    libxi-dev \
    libxcomposite-dev \
    libxdamage-dev \
    libxfixes-dev \
    at-spi2-core-dev \
    gcc \
    musl-dev \
    openssl-dev \
    pkgconf \
    file \
    patchelf \
    2>&1 | tail -5

# ── Stage 4: Build Terax frontend + Tauri ────────────────────────────────
log "=== Stage 4: Build Terax ==="

if [ ! -d "$TERAX_SRC" ]; then
    log "ERROR: Terax source not found at $TERAX_SRC"
    exit 1
fi

cd "$TERAX_SRC"

# Install frontend dependencies
log "Installing frontend dependencies..."
# Fix pnpm-workspace.yaml for pnpm 9 (needs packages field)
cat > pnpm-workspace.yaml <<'WSYAML'
packages:
  - '.'
WSYAML
pnpm install 2>&1 | tail -10 || {
    log "ERROR: pnpm install failed"
    exit 1
}

# Build Tauri app (release mode)
log "Building Tauri app (release)..."
# Ensure cargo is in PATH for all subsequent commands
export PATH="$CARGO_HOME/bin:$PATH"

# Tauri links against system GTK/GLib/WebKit dynamically (no static libs on Alpine)
# Tell the linker to use dynamic linking for system libraries
export RUSTFLAGS="-C link-arg=-Wl,-Bdynamic"

# Use tauri CLI via pnpm
pnpm tauri build 2>&1 | tee "$BUILDLOG"
TAURI_RC=$?

if [ $TAURI_RC -ne 0 ]; then
    log "ERROR: tauri build failed (exit=$TAURI_RC)"
    log "=== Last 50 lines of build log ==="
    tail -50 "$BUILDLOG"
    exit 1
fi

# ── Stage 5: Find and package binary ─────────────────────────────────────
log "=== Stage 5: Package artifacts ==="

# Tauri builds to src-tauri/target/release/
TAURI_BIN=""
for candidate in \
    "src-tauri/target/release/terax" \
    "src-tauri/target/x86_64-unknown-linux-musl/release/terax"; do
    if [ -f "$candidate" ]; then
        TAURI_BIN="$candidate"
        break
    fi
done

if [ -z "$TAURI_BIN" ]; then
    # Try to find it
    TAURI_BIN=$(find src-tauri/target -name "terax" -type f -executable 2>/dev/null | head -1)
fi

if [ -z "$TAURI_BIN" ] || [ ! -f "$TAURI_BIN" ]; then
    log "ERROR: terax binary not found after build"
    log "Looking in src-tauri/target/:"
    find src-tauri/target -name "terax*" -type f 2>/dev/null | head -10
    exit 1
fi

log "Found binary: $TAURI_BIN"
file "$TAURI_BIN"
ldd "$TAURI_BIN" 2>&1 | head -10 || true

# Package to output directory
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin"
mkdir -p "$OUTPUT/usr/lib/terax"

cp -v "$TAURI_BIN" "$OUTPUT/usr/bin/terax"
chmod +x "$OUTPUT/usr/bin/terax"

# Copy any shared libraries if needed
for so in src-tauri/target/release/*.so src-tauri/target/release/deps/*.so; do
    [ -f "$so" ] && cp -v "$so" "$OUTPUT/usr/lib/terax/" 2>/dev/null || true
done

log "=== Artifacts ==="
ls -la "$OUTPUT/usr/bin/terax"
file "$OUTPUT/usr/bin/terax"

# ── Cleanup ───────────────────────────────────────────────────────────────
log "=== Cleanup ==="
# Remove build artifacts to save space
rm -rf src-tauri/target/release/build
rm -rf src-tauri/target/release/deps
rm -rf src-tauri/target/release/examples
rm -rf src-tauri/target/release/incremental

log "Terax build complete!"
