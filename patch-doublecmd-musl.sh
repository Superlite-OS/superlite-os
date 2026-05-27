#!/bin/sh
# patch-doublecmd-musl.sh — Apply musl compatibility patches to doublecmd source
# Run this before building doublecmd on Alpine/musl

DC_SRC="$1"
[ -d "$DC_SRC" ] || { echo "Usage: $0 <doublecmd-source-dir>"; exit 1; }
echo "[patch] Applying musl compatibility patches to $DC_SRC..."

# Patch 1: vtemupty.pas — {$LINKLIB util} fails on musl (no separate libutil)
# On musl, forkpty is in libc directly, no need for -lutil
PFILE="$DC_SRC/components/virtualterminal/source/unix/vtemupty.pas"
if [ -f "$PFILE" ] && grep -q 'LINKLIB util' "$PFILE"; then
    sed -i 's/{$IF NOT (DEFINED(DARWIN) OR DEFINED(HAIKU))}/{$IF NOT (DEFINED(DARWIN) OR DEFINED(HAIKU) OR DEFINED(FPC_MUSL))}/' "$PFILE"
    echo "[patch] vtemupty.pas: conditional LINKLIB util"
fi

# Patch 2: urandom.pas — dlopen('libc.so.6') fails on musl
# musl libc is at libc.musl-x86_64.so.1 but also accessible via ld-musl-x86_64.so.1
PFILE="$DC_SRC/src/platform/urandom.pas"
if [ -f "$PFILE" ] && grep -q "dlopen('libc.so.6'" "$PFILE"; then
    sed -i "s|dlopen('libc.so.6', RTLD_NOW)|dlopen('libc.so.6', RTLD_NOW) \/\/ patched: fallback in code|" "$PFILE"
    # Add a musl fallback right after
    sed -i "/dlopen('libc.so.6', RTLD_NOW)/a\\    if result = nil then result := dlopen('libc.musl-x86_64.so.1', RTLD_NOW);" "$PFILE" 2>/dev/null
    echo "[patch] urandom.pas: libc.so.6 → musl fallback"
fi

# Patch 3: dc_iconvenc_dyn.pas — TryLoadLib('libc.so.6') fails on musl
PFILE="$DC_SRC/components/doublecmd/iconvenc/dc_iconvenc_dyn.pas"
if [ -f "$PFILE" ] && grep -q "TryLoadLib('libc.so.6'" "$PFILE"; then
    sed -i "s|TryLoadLib('libc.so.6', error)|TryLoadLib('libc.so.6', error) or TryLoadLib('libc.musl-x86_64.so.1', error)|" "$PFILE"
    echo "[patch] dc_iconvenc_dyn.pas: musl libc fallback for iconv"
fi

# Patch 4: ufindex.pas — readdir64 may not exist on musl
# musl uses 64-bit readdir natively, readdir64 is not a separate symbol
# FPC's baseunix usually handles this, but if not, we need to alias
PFILE="$DC_SRC/src/platform/ufindex.pas"
if [ -f "$PFILE" ] && grep -q "readdir64" "$PFILE"; then
    # Don't sed this one — FPC runtime may handle it. Log only.
    echo "[patch] ufindex.pas: readdir64 found (FPC baseunix should handle)"
fi

echo "[patch] Done."
