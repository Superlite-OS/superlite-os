#!/bin/sh
# build-superlite-files.sh — Build SuperLite Files fully static on Alpine
# All libraries (webkit2gtk, GTK3, etc.) are linked statically into the binary
# Output: single static binary with zero runtime dependencies

OUTPUT="/tmp/superlite-files-static"
BUILDLOG="/tmp/superlite-files-build.log"
SRC="${1:-/build/vendor/superlite-files}"

export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo

log() { echo "[slf-build] $*"; }

# ── Stage 1: Install Rust via rustup ─────────────────────────────────────
log "=== Stage 1: Install Rust ==="
apk add --no-cache curl gcc musl-dev 2>&1 | tail -3
# Add musl target for static builds
rustup toolchain install stable 2>&1 | tail -3
rustup target add x86_64-unknown-linux-musl 2>&1 | tail -3
export PATH="$CARGO_HOME/bin:$PATH"
log "Rust: $(rustc --version 2>&1)"

# ── Stage 2: Install Node.js + pnpm ──────────────────────────────────────
log "=== Stage 2: Install Node.js + pnpm ==="
apk add --no-cache nodejs npm 2>&1 | tail -3
npm install -g pnpm@9 2>&1 | tail -3
log "Node: $(node --version 2>&1), pnpm: $(pnpm --version 2>&1)"

# ── Stage 3: Install Tauri system dependencies (static libs) ─────────────
log "=== Stage 3: Install Tauri deps (static) ==="
# Install -dev packages (include both .so and .a static libs)
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

# Verify static libraries exist
log "Checking static libs..."
ls /usr/lib/libwebkit2gtk*.a 2>/dev/null && log "  webkit2gtk: OK" || log "  WARNING: no webkit2gtk .a files"
ls /usr/lib/libgtk-3.a 2>/dev/null && log "  gtk3: OK" || log "  WARNING: no gtk3 .a files"
ls /usr/lib/libglib-2.0.a 2>/dev/null && log "  glib: OK" || log "  WARNING: no glib .a files"
ls /usr/lib/libcairo.a 2>/dev/null && log "  cairo: OK" || log "  WARNING: no cairo .a files"

# ── Stage 4: Configure cargo for FULLY STATIC linking ─────────────────────
log "=== Stage 4: Configure cargo (static) ==="

if [ ! -d "$SRC" ]; then
    log "ERROR: Source not found at $SRC"
    exit 1
fi

cd "$SRC"

mkdir -p .cargo
cat > .cargo/config.toml <<'CARGO'
[target.x86_64-unknown-linux-musl]
linker = "cc"
rustflags = [
    "-C", "target-feature=-crt-static",
    "-C", "link-arg=-static",
    "-C", "link-arg=-L/usr/lib",
    "-C", "link-arg=-Wl,-Bstatic",
]
CARGO

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

# ── Stage 6: Build Tauri app (static) ───────────────────────────────────
log "=== Stage 6: Build SuperLite Files (static) ==="
export PATH="$CARGO_HOME/bin:$PATH"
export RUSTFLAGS="-C target-feature=-crt-static -C link-arg=-static -C link-arg=-Wl,-Bstatic"

# Make cargo available to all subprocesses
echo "export PATH=\"$CARGO_HOME/bin:\$PATH\"" > /etc/profile.d/cargo.sh
chmod +x /etc/profile.d/cargo.sh

# Verify cargo is available
cargo --version || { log "ERROR: cargo not found"; exit 1; }

# Build frontend first (without cargo)
log "Building frontend..."
pnpm build 2>&1 | tail -5

# Build Rust backend (Tauri) directly with cargo
log "Building Rust backend..."
cd src-tauri
cargo build --release --target x86_64-unknown-linux-musl 2>&1 | tee "../$BUILDLOG"
BUILD_RC=$?
cd ..

if [ $BUILD_RC -ne 0 ]; then
    log "ERROR: cargo build failed (exit=$BUILD_RC)"
    tail -50 "$BUILDLOG"
    exit 1
fi

# ── Stage 7: Package artifacts ───────────────────────────────────────────
log "=== Stage 7: Package ==="

BIN="src-tauri/target/x86_64-unknown-linux-musl/release/superlite-files"
if [ ! -f "$BIN" ]; then
    BIN="src-tauri/target/release/superlite-files"
fi
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

# Check dynamic dependencies
DEPS=$(ldd "$BIN" 2>&1)
if echo "$DEPS" | grep -q "not a dynamic executable\|statically linked"; then
    log "Binary is FULLY STATIC — no runtime dependencies!"
elif echo "$DEPS" | grep -q "linux-vdso\|ld-musl"; then
    log "WARNING: Binary still has dynamic deps:"
    echo "$DEPS" | grep -v "linux-vdso\|ld-musl" | head -10
else
    log "Binary has dynamic deps:"
    echo "$DEPS" | head -10
fi

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin"
cp -v "$BIN" "$OUTPUT/usr/bin/superlite-files"
chmod +x "$OUTPUT/usr/bin/superlite-files"

log "=== Done ==="
ls -la "$OUTPUT/usr/bin/superlite-files"
du -h "$OUTPUT/usr/bin/superlite-files"

# Cleanup
rm -rf src-tauri/target/release/build src-tauri/target/release/deps
rm -rf src-tauri/target/release/examples src-tauri/target/release/incremental

log "SuperLite Files build complete!"
