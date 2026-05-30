#!/bin/sh
# build-superlite-files.sh — Build SuperLite Files (egui, static musl)
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/superlite-files-musl/usr/bin/superlite-files

OUTPUT="/tmp/superlite-files-musl"
BUILDLOG="/tmp/superlite-files-build.log"
SRC="/build/vendor/superlite-files"

export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo

log() { echo "[slf-build] $*"; }

# Stage 1: Install Rust
log "=== Stage 1: Install Rust ==="
apk add --no-cache curl gcc musl-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
export PATH="$CARGO_HOME/bin:$PATH"
log "Rust: $(rustc --version 2>&1)"

# Stage 2: Add musl target
log "=== Stage 2: Add musl target ==="
rustup target add x86_64-unknown-linux-musl

# Stage 3: Build
log "=== Stage 3: Build (static musl) ==="
if [ ! -d "$SRC" ]; then
    log "ERROR: Source not found at $SRC"
    exit 1
fi
cd "$SRC"
RUSTFLAGS="-C target-feature=+crt-static" cargo build --target x86_64-unknown-linux-musl --release 2>&1 | tee "$BUILDLOG"
if [ $? -ne 0 ]; then
    log "ERROR: Build failed"
    exit 1
fi

# Stage 4: Package
log "=== Stage 4: Package ==="
BIN="$SRC/target/x86_64-unknown-linux-musl/release/superlite-files"
if [ ! -f "$BIN" ]; then
    log "ERROR: Binary not found at $BIN"
    exit 1
fi

file "$BIN"
ldd "$BIN" 2>&1 || true

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin"
cp -v "$BIN" "$OUTPUT/usr/bin/superlite-files"
chmod +x "$OUTPUT/usr/bin/superlite-files"

log "=== Done ==="
ls -la "$OUTPUT/usr/bin/superlite-files"
log "Build complete!"
