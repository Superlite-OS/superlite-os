#!/bin/sh
# build-terax.sh — Build Terax AI terminal from vendored source (musl native)
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/terax-musl/{usr/bin/terax, usr/lib/terax/...}
#
# Key challenge: rustup's musl target defaults to static linking, but Alpine
# only ships dynamic .so files for GTK/GLib/WebKit. We use .cargo/config.toml
# to force dynamic linking and proper linker flags.

OUTPUT="/tmp/terax-musl"
BUILDLOG="/tmp/terax-build.log"
TERAX_SRC="/build/vendor/terax-ai"

export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo

log() { echo "[terax-build] $*"; }

# ── Stage 1: Install Rust via rustup ─────────────────────────────────────
log "=== Stage 1: Install Rust ==="
# Alpine's rust pkg lacks proc-macro/dylib support needed by Tauri
apk add --no-cache curl gcc musl-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
export PATH="$CARGO_HOME/bin:$PATH"
log "Rust: $(rustc --version 2>&1)"

# ── Stage 2: Install Node.js + pnpm ──────────────────────────────────────
log "=== Stage 2: Install Node.js + pnpm ==="
apk add --no-cache nodejs npm
npm install -g pnpm@9
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
    patchelf

# ── Stage 4: Configure cargo for musl dynamic linking ────────────────────
log "=== Stage 4: Configure cargo ==="

if [ ! -d "$TERAX_SRC" ]; then
    log "ERROR: Terax source not found at $TERAX_SRC"
    exit 1
fi

cd "$TERAX_SRC"

# Create .cargo/config.toml to force dynamic linking on musl
# rustup's musl target defaults to -static-pie, which overrides -Bdynamic
# -crt-static disables the static PIE mode, enabling dynamic linking
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

log "Created .cargo/config.toml for dynamic musl linking"

# ── Stage 5: Install frontend dependencies ───────────────────────────────
log "=== Stage 5: pnpm install ==="
# Fix pnpm-workspace.yaml for pnpm 9+ (needs packages field)
cat > pnpm-workspace.yaml <<'WSYAML'
packages:
  - '.'
WSYAML
pnpm install 2>&1 | tail -10 || {
    log "ERROR: pnpm install failed"
    exit 1
}

# ── Stage 6: Build Tauri app ─────────────────────────────────────────────
log "=== Stage 6: Build Terax (release) ==="
export PATH="$CARGO_HOME/bin:$PATH"

pnpm tauri build
TAURI_RC=$?

if [ $TAURI_RC -ne 0 ]; then
    log "ERROR: tauri build failed (exit=$TAURI_RC)"
    exit 1
fi

# ── Stage 7: Package artifacts ───────────────────────────────────────────
log "=== Stage 7: Package ==="

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
    TAURI_BIN=$(find src-tauri/target -name "terax" -type f 2>/dev/null | head -1)
fi

if [ -z "$TAURI_BIN" ] || [ ! -f "$TAURI_BIN" ]; then
    log "ERROR: terax binary not found"
    find src-tauri/target -name "terax*" -type f 2>/dev/null
    exit 1
fi

log "Found: $TAURI_BIN"
file "$TAURI_BIN"
ldd "$TAURI_BIN" 2>&1 || true

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin" "$OUTPUT/usr/lib/terax"
cp -v "$TAURI_BIN" "$OUTPUT/usr/bin/terax"
chmod +x "$OUTPUT/usr/bin/terax"

for so in src-tauri/target/release/*.so src-tauri/target/release/deps/*.so; do
    [ -f "$so" ] && cp -v "$so" "$OUTPUT/usr/lib/terax/" 2>/dev/null || true
done

log "=== Done ==="
ls -la "$OUTPUT/usr/bin/terax"
file "$OUTPUT/usr/bin/terax"

# Cleanup build artifacts (keep binary)
rm -rf src-tauri/target/release/build src-tauri/target/release/deps
rm -rf src-tauri/target/release/examples src-tauri/target/release/incremental

log "Terax build complete!"
