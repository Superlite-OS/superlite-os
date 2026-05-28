#!/bin/sh
# build-superlite-files.sh — Build SuperLite Files from vendored source (musl native)
# Same pattern as build-terax.sh

OUTPUT="/tmp/superlite-files-musl"
BUILDLOG="/tmp/superlite-files-build.log"
SRC="/build/vendor/superlite-files"

export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo

log() { echo "[slf-build] $*"; }

# ── Stage 1: Install Rust via rustup ─────────────────────────────────────
log "=== Stage 1: Install Rust ==="
apk add --no-cache curl gcc musl-dev 2>&1 | tail -3
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 | tail -5
export PATH="$CARGO_HOME/bin:$PATH"
log "Rust: $(rustc --version 2>&1)"

# ── Stage 2: Install Node.js + pnpm ──────────────────────────────────────
log "=== Stage 2: Install Node.js + pnpm ==="
apk add --no-cache nodejs npm 2>&1 | tail -3
npm install -g pnpm@9 2>&1 | tail -3
log "Node: $(node --version 2>&1), pnpm: $(pnpm --version 2>&1)"

# ── Stage 3: Install Tauri system dependencies ──────────────────────────
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

# ── Stage 4: Configure cargo for musl dynamic linking ────────────────────
log "=== Stage 4: Configure cargo ==="

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
    "-C", "link-arg=-Wl,-Bdynamic",
    "-C", "link-arg=-L/usr/lib",
    "-C", "link-arg=-Wl,--enable-new-dtags",
    "-C", "link-arg=-Wl,-rpath,/usr/lib",
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

BIN=""
for candidate in \
    "src-tauri/target/release/superlite-files" \
    "src-tauri/target/x86_64-unknown-linux-musl/release/superlite-files"; do
    if [ -f "$candidate" ]; then
        BIN="$candidate"
        break
    fi
done

if [ -z "$BIN" ]; then
    BIN=$(find src-tauri/target -name "superlite-files" -type f 2>/dev/null | head -1)
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
