#!/bin/sh
# ============================================================================
# SuperLite OS — Modloop Extras Injector
# Injects heavy binaries into modloop squashfs after mkimage.sh builds ISO.
# Uses xorriso in-place replacement — preserves original boot records.
#
# Usage: inject-modloop.sh <output_dir> [repo_dir]
# ============================================================================
set -e

OUTPUT_DIR="$1"
REPO_DIR="${2:-$(cd "$(dirname "$0")" && pwd)}"

if [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <output_dir> [repo_dir]"
    exit 1
fi

log() { echo "[inject] $*"; }

# Find ISO
ISO_FILE=$(find "$OUTPUT_DIR" -name "*.iso" -type f | head -1)
if [ -z "$ISO_FILE" ]; then
    log "ERROR: No ISO found in $OUTPUT_DIR"
    exit 1
fi
log "Processing: $ISO_FILE ($(du -sh "$ISO_FILE" | cut -f1))"

# Temp workspace
TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Extract ONLY modloop from ISO (not entire ISO)
log "Extracting modloop from ISO..."
xorriso -indev "$ISO_FILE" -osirrox on \
    -extract /boot/modloop-lts "$TMPDIR/modloop-lts" >/dev/null 2>&1

if [ ! -f "$TMPDIR/modloop-lts" ]; then
    log "ERROR: modloop-lts not found in ISO"
    exit 1
fi

OLD_SIZE=$(du -sh "$TMPDIR/modloop-lts" | cut -f1)

# Unsquashfs into temp
SQFS="$TMPDIR/squashfs-root"
log "Unsquashing modloop ($OLD_SIZE)..."
unsquashfs -q -d "$SQFS" "$TMPDIR/modloop-lts"
rm "$TMPDIR/modloop-lts"

# ── Build zapt (Go static binary) ──────────────────────────────────────────
ZAPT_DIR=""
for d in "$REPO_DIR/zapt" "./zapt"; do
    [ -d "$d" ] && [ -f "$d/main.go" ] && ZAPT_DIR="$d" && break
done

if [ -n "$ZAPT_DIR" ] && command -v go >/dev/null 2>&1; then
    log "Building zapt..."
    (cd "$ZAPT_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -buildvcs=false -trimpath -ldflags="-s -w" -o "$SQFS/usr/local/bin/zapt" .) || {
        log "WARNING: zapt build failed"
    }
    mkdir -p "$SQFS/etc/zapt"
    [ -f "$ZAPT_DIR/etc/sources.conf" ] && \
        cp "$ZAPT_DIR/etc/sources.conf" "$SQFS/etc/zapt/sources.conf"
else
    log "WARNING: zapt not built (Go or source not available)"
fi

# ── curl-impersonate (glibc binary, needs gcompat) ─────────────────────────
CURL_VER="0.6.1"
CURL_URL="https://github.com/lwthiker/curl-impersonate/releases/download/v${CURL_VER}/curl-impersonate-v${CURL_VER}.x86_64-linux-gnu.tar.gz"
log "Installing curl-impersonate..."
wget -q -O /tmp/curl-imp.tar.gz "$CURL_URL" 2>/dev/null || true
if [ -f /tmp/curl-imp.tar.gz ]; then
    mkdir -p "$SQFS/usr/local/lib/curl-impersonate"
    tar -xzf /tmp/curl-imp.tar.gz -C "$SQFS/usr/local/lib/curl-impersonate" 2>/dev/null || true
    if [ -f "$SQFS/usr/local/lib/curl-impersonate/curl-impersonate-chrome" ]; then
        chmod +x "$SQFS/usr/local/lib/curl-impersonate/curl-impersonate-chrome"
        mkdir -p "$SQFS/usr/local/bin"
        # Wrapper scripts for curl-impersonate (glibc binary needs ld-linux loader)
        for w in "$SQFS"/usr/local/lib/curl-impersonate/curl_*; do
            [ -f "$w" ] || continue
            _wname=$(basename "$w")
            cat > "$SQFS/usr/local/bin/$_wname" << CW
#!/bin/sh
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/local/lib/curl-impersonate:/usr/lib/glibc $w "\$@"
CW
            chmod +x "$SQFS/usr/local/bin/$_wname"
        done
        # curl -> curl-impersonate-chrome wrapper
        cat > "$SQFS/usr/local/bin/curl" << 'CW'
#!/bin/sh
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/local/lib/curl-impersonate:/usr/lib/glibc /usr/local/lib/curl-impersonate/curl-impersonate-chrome "$@"
CW
        chmod +x "$SQFS/usr/local/bin/curl"
        log "  curl-impersonate installed"
    fi
    rm -f /tmp/curl-imp.tar.gz
fi

# ── Google Chrome .deb + glibc deps ────────────────────────────────────────
log "Installing Chrome..."
CHROME_DEB="/tmp/google-chrome-stable.deb"
wget -q -O "$CHROME_DEB" \
    "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" 2>&1 || true
if [ -f "$CHROME_DEB" ] && [ -x "$SQFS/usr/local/bin/zapt" ]; then
    "$SQFS/usr/local/bin/zapt" install --root "$SQFS" "$CHROME_DEB" 2>&1 || {
        log "WARNING: Chrome install failed"
    }
    chmod 4755 "$SQFS/opt/google/chrome/chrome-sandbox" 2>/dev/null || true
    mkdir -p "$SQFS/usr/bin"
    ln -sf /opt/google/chrome/chrome "$SQFS/usr/bin/google-chrome-stable"
    ln -sf /opt/google/chrome/chrome "$SQFS/usr/bin/google-chrome"
    rm -f "$CHROME_DEB"
fi

# Fix glibc symlinks: Debian glibc .deb puts real .so files in
# /lib/x86_64-linux-gnu/ and /usr/lib/glibc/ has symlinks pointing there.
# These absolute symlinks break when squashfs is mounted elsewhere.
# Fix: copy real files into /usr/lib/glibc/ and remove broken symlinks.
if [ -d "$SQFS/usr/lib/glibc" ]; then
    log "Fixing glibc symlinks..."
    # Resolve broken symlinks in /usr/lib/glibc/
    # zapt redirects ALL .so files to /usr/lib/glibc/ (not /lib/x86_64-linux-gnu/)
    for link in "$SQFS"/usr/lib/glibc/*; do
        [ -L "$link" ] || continue
        [ -f "$link" ] && continue  # symlink target exists, OK
        # Symlink target is broken — find the real file
        target=$(readlink "$link")
        fname=$(basename "$link")
        real_file=""
        # Search in /usr/lib/glibc/ itself (zapt redirects all .so here)
        for dir in "$SQFS/usr/lib/glibc" "$SQFS/lib/x86_64-linux-gnu" "$SQFS/lib"; do
            [ -f "$dir/$fname" ] && { real_file="$dir/$fname"; break; }
            [ -L "$dir/$fname" ] && [ -f "$dir/$fname" ] && { real_file="$dir/$fname"; break; }
            # Also check if symlink target exists in this dir
            [ -f "$dir/$target" ] && { real_file="$dir/$target"; break; }
            [ -L "$dir/$target" ] && [ -f "$dir/$target" ] && { real_file="$dir/$target"; break; }
            # Try to find ld-*.so (versioned name)
            for f in "$dir"/ld-*.so.* "$dir"/ld-linux*.so.*; do
                [ -f "$f" ] && { real_file="$f"; break 2; }
            done
        done
        if [ -n "$real_file" ]; then
            rm "$link"
            cp "$real_file" "$link"
            log "  Fixed: $fname (was -> $target)"
        else
            log "  WARNING: $fname broken symlink, no real file found"
        fi
    done
    # Ensure ld-linux ELF loader symlink resolves
    if [ -f "$SQFS/usr/lib/glibc/ld-linux-x86-64.so.2" ]; then
        mkdir -p "$SQFS/lib64"
        ln -sf /usr/lib/glibc/ld-linux-x86-64.so.2 "$SQFS/lib64/ld-linux-x86-64.so.2"
    fi
    # Also copy libc.so.6 and libm.so.6 for glibc wrapper scripts
    for so in libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1; do
        if [ -L "$SQFS/usr/lib/glibc/$so" ] && [ ! -f "$SQFS/usr/lib/glibc/$so" ]; then
            target=$(readlink "$SQFS/usr/lib/glibc/$so")
            for dir in "$SQFS/lib/x86_64-linux-gnu" "$SQFS/lib"; do
                if [ -f "$dir/$so" ]; then
                    rm "$SQFS/usr/lib/glibc/$so"
                    cp "$dir/$so" "$SQFS/usr/lib/glibc/$so"
                    log "  Fixed: $so"
                    break
                fi
            done
        fi
    done
    log "  glibc symlinks fixed"
fi

# ── Download missing Debian deps that zapt can't find ──────────────────────
# These are transitive deps not resolved by zapt from local .deb files.
# libsystemd0 → liblzma5, liblz4-1; also libhwy1 (Debian ver, not Alpine's GCC13)
# libxcb-image0, libxcb-keysyms1, libxcb-render-util0, libxcb-cursor0 → Qt xcb plugin
log "Downloading missing Debian deps..."
PACKAGES_GZ="/tmp/superlite-packages.gz"
wget -q -O "$PACKAGES_GZ" \
    "https://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages.gz" 2>/dev/null || true

_download_deb_pkg() {
    _pkg="$1"
    if [ ! -f "$PACKAGES_GZ" ]; then
        log "  WARNING: Packages.gz not available, skipping $_pkg"
        return 1
    fi
    _pkgfile=$(zcat "$PACKAGES_GZ" 2>/dev/null | grep -A1 "^Package: ${_pkg}$" \
        | grep "^Filename:" | head -1 | sed 's/Filename: //')
    if [ -n "$_pkgfile" ]; then
        log "  Downloading $_pkg from $_pkgfile"
        wget -q -O "/tmp/${_pkg}.deb" "https://deb.debian.org/debian/${_pkgfile}" 2>&1 || true
        if [ -f "/tmp/${_pkg}.deb" ] && [ -x "$SQFS/usr/local/bin/zapt" ]; then
            "$SQFS/usr/local/bin/zapt" install --root "$SQFS" "/tmp/${_pkg}.deb" 2>&1 || true
            rm -f "/tmp/${_pkg}.deb"
        fi
    else
        log "  WARNING: $_pkg not found in Debian bookworm"
        return 1
    fi
}

for _pkg in libsystemd0 liblzma5 liblz4-1 libhwy1 \
    libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-cursor0; do
    _download_deb_pkg "$_pkg"
done
rm -f "$PACKAGES_GZ"

# ── Terax AI terminal (direct .deb via zapt) ───────────────────────────────
TERAX_DEB="/tmp/terax.deb"
log "Installing Terax AI terminal..."
wget -q -O "$TERAX_DEB" \
    "https://github.com/crynta/terax-ai/releases/download/v0.7.3/Terax_0.7.3_amd64.deb" 2>&1 || true
if [ -f "$TERAX_DEB" ] && [ -x "$SQFS/usr/local/bin/zapt" ]; then
    "$SQFS/usr/local/bin/zapt" install --root "$SQFS" "$TERAX_DEB" 2>&1 || {
        log "WARNING: Terax install failed"
    }
    rm -f "$TERAX_DEB"
fi

# ── Double Commander (Debian pool via zapt) ────────────────────────────────
if [ -x "$SQFS/usr/local/bin/zapt" ]; then
    log "Installing Double Commander..."
    "$SQFS/usr/local/bin/zapt" install --root "$SQFS" doublecmd-qt 2>&1 || {
        log "WARNING: Double Commander install failed"
    }
fi

# ── Create glibc wrappers for terax and doublecmd ──────────────────────────
# These are glibc ELF binaries that need the glibc ELF loader (ld-linux-x86-64.so.2)
# to run on musl Alpine. zapt's createGlibcWrapper handles Chrome, but terax and
# doublecmd are installed from .deb files where the wrapper might not be created.
if [ -d "$SQFS/usr/lib/glibc" ]; then
    _glibc_ld="$SQFS/usr/lib/glibc/ld-linux-x86-64.so.2"
    if [ -f "$_glibc_ld" ]; then
        # Terax wrapper
        _terax_bin="$SQFS/usr/lib/glibc/bin/terax"
        if [ -f "$_terax_bin" ] && [ ! -f "$SQFS/usr/bin/terax" ]; then
            mkdir -p "$SQFS/usr/bin"
            cat > "$SQFS/usr/bin/terax" << 'TW'
#!/bin/sh
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/lib/glibc /usr/lib/glibc/bin/terax "$@"
TW
            chmod +x "$SQFS/usr/bin/terax"
            log "  Created terax wrapper"
        fi
        # Doublecmd wrapper
        _dc_bin="$SQFS/lib/doublecmd/doublecmd"
        if [ -f "$_dc_bin" ] && [ ! -f "$SQFS/usr/bin/doublecmd" ]; then
            mkdir -p "$SQFS/usr/bin"
            cat > "$SQFS/usr/bin/doublecmd" << 'DW'
#!/bin/sh
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/lib/glibc /lib/doublecmd/doublecmd "$@"
DW
            chmod +x "$SQFS/usr/bin/doublecmd"
            log "  Created doublecmd wrapper"
        fi
        # Create /lib64/ld-linux-x86-64.so.2 symlink for glibc binaries
        # that have hardcoded ELF interpreter path
        mkdir -p "$SQFS/lib64"
        ln -sf /usr/lib/glibc/ld-linux-x86-64.so.2 "$SQFS/lib64/ld-linux-x86-64.so.2"
    fi
fi

# ── Strip binaries ─────────────────────────────────────────────────────────
log "Stripping binaries..."
_command_strip() {
    command -v strip >/dev/null 2>&1 || return 0
    find "$SQFS/usr/lib" "$SQFS/usr/lib64" "$SQFS/lib" "$SQFS/lib64" \
        -name "*.so*" -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
    find "$SQFS/usr/bin" "$SQFS/usr/sbin" "$SQFS/opt" \
        -type f -exec sh -c 'file "$1" 2>/dev/null | grep -q "ELF" && strip --strip-unneeded "$1" 2>/dev/null' _ {} \; || true
}
_command_strip

# ── Chrome cleanup ─────────────────────────────────────────────────────────
log "Cleaning up Chrome..."
if [ -d "$SQFS/opt/google/chrome" ]; then
    # Remove all locales except en-US (~30MB)
    find "$SQFS/opt/google/chrome/locales" -name "*.pak" ! -name "en-US.pak" -delete 2>/dev/null || true
    # Remove crashpad, updater, docs
    rm -rf "$SQFS/opt/google/chrome/crashpad" 2>/dev/null || true
    rm -rf "$SQFS/opt/google/chrome/debug" 2>/dev/null || true
    rm -rf "$SQFS/usr/share/doc/google-chrome-stable" 2>/dev/null || true
    # Remove debug symbols
    find "$SQFS/opt/google/chrome" -name "*.debug" -delete 2>/dev/null || true
    find "$SQFS/opt/google/chrome" -name "*.dbg" -delete 2>/dev/null || true
fi

# ── Remove docs/man/locale ─────────────────────────────────────────────────
log "Removing docs/man/locale..."
rm -rf "$SQFS/usr/share/doc" "$SQFS/usr/share/man" 2>/dev/null || true
find "$SQFS/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name "en" ! -name "en_US" -exec rm -rf {} \; 2>/dev/null || true

# ── UPX compress static binaries ───────────────────────────────────────────
if command -v upx >/dev/null 2>&1; then
    log "Compressing binaries with UPX..."
    for _bin in "$SQFS/usr/local/bin/zapt"; do
        [ -f "$_bin" ] && file "$_bin" 2>/dev/null | grep -q "ELF" && {
            upx --best "$_bin" 2>/dev/null || true
        }
    done
fi

# ── Repack squashfs with x86 BCJ filter ────────────────────────────────────
log "Repacking modloop (xz + x86 BCJ filter)..."
mksquashfs "$SQFS" "$TMPDIR/modloop-lts" -comp xz -b 1M -Xbcj x86 -noappend >/dev/null 2>&1
NEW_SIZE=$(du -sh "$TMPDIR/modloop-lts" | cut -f1)
rm -rf "$SQFS"

# ── Replace modloop in ISO (preserves boot records) ────────────────────────
NEW_ISO="${ISO_FILE%.iso}.new.iso"
log "Replacing modloop in ISO (in-place, preserving boot records)..."

xorriso -indev "$ISO_FILE" \
    -boot_image any keep \
    -boot_image isolinux patch \
    -map "$TMPDIR/modloop-lts" /boot/modloop-lts \
    -outdev "$NEW_ISO" >/dev/null 2>&1

mv "$NEW_ISO" "$ISO_FILE"
log "Done: $ISO_FILE ($(du -sh "$ISO_FILE" | cut -f1))"
log "Modloop: $OLD_SIZE -> $NEW_SIZE"
