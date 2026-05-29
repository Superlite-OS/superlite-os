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
[ -z "\$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=wayland-0
[ -z "\$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/local/lib/curl-impersonate:/usr/lib/glibc $w "\$@"
CW
            chmod +x "$SQFS/usr/local/bin/$_wname"
        done
        # curl -> curl-impersonate-chrome wrapper
        cat > "$SQFS/usr/local/bin/curl" << 'CW'
#!/bin/sh
[ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=wayland-0
[ -z "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/local/lib/curl-impersonate:/usr/lib/glibc /usr/local/lib/curl-impersonate/curl-impersonate-chrome "$@"
CW
        chmod +x "$SQFS/usr/local/bin/curl"
        log "  curl-impersonate installed"
    fi
    rm -f /tmp/curl-imp.tar.gz
fi

# ── Download glibc deps FIRST (before Chrome/Terax/Doublecmd) ──────────────
# zapt resolves dependencies from the Debian pool during install.
# These deps must be available BEFORE the apps that need them.
log "Downloading glibc deps (must be before app installs)..."
PACKAGES_GZ="/tmp/superlite-packages.gz"
wget -q -O "$PACKAGES_GZ" \
    "https://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages.gz" 2>/dev/null || true

_download_deb_pkg() {
    _pkg="$1"
    if [ ! -f "$PACKAGES_GZ" ]; then
        log "  WARNING: Packages.gz not available, skipping $_pkg"
        return 1
    fi
    _pkgfile=$(zcat "$PACKAGES_GZ" 2>/dev/null | grep -A20 "^Package: ${_pkg}$" \
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

# Core glibc deps — installed BEFORE Chrome/Terax/Doublecmd
for _pkg in libsystemd0 liblzma5 liblz4-1 libhwy1 libstdc++6 libgcc-s1 \
    libaom3 libdav1d6 libgav1-1 libsvtav1enc1 \
    libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-cursor0 \
    libxslt1.1; do
    _download_deb_pkg "$_pkg"
done

# Download webkit2gtk + full transitive glibc deps using helper script
# This resolves the entire dependency tree and extracts only .so files
_download_glibc_deps_py="$REPO_DIR/download-glibc-deps.py"
if [ -f "$_download_glibc_deps_py" ] && command -v python3 >/dev/null 2>&1; then
    log "Downloading webkit2gtk glibc deps (full dependency tree)..."
    python3 "$_download_glibc_deps_py" "$SQFS/usr/lib/glibc" "$PACKAGES_GZ" 2>&1 || {
        log "WARNING: webkit2gtk deps download failed"
    }
fi
rm -f "$PACKAGES_GZ"

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
    # Chrome wrapper — glibc binary with GSETTINGS_BACKEND=memory to prevent
    # GLib fatal assertion crash (glibc GLib tries DBUS for GSettings, fails
    # on musl dbus-daemon address format)
    cat > "$SQFS/usr/bin/google-chrome-stable" << 'CW'
#!/bin/sh
[ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=wayland-0
[ -z "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
export CHROME_VERSION_EXTRA=stable
export LD_LIBRARY_PATH=/usr/lib/glibc
export GSETTINGS_BACKEND=memory
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/lib/glibc /usr/lib/glibc/bin/chrome --no-sandbox --disable-gpu "$@"
CW
    chmod +x "$SQFS/usr/bin/google-chrome-stable"
    ln -sf google-chrome-stable "$SQFS/usr/bin/google-chrome"
    rm -f "$CHROME_DEB"
fi

# ── Chrome data file symlinks for glibc ELF binary ─────────────────────────
# Chrome ELF binary lives at /usr/lib/glibc/bin/chrome. It resolves data files
# (icudtl.dat, resources.pak, etc.) relative to /proc/self/exe → that directory.
# The actual data is at /opt/google/chrome/ so we symlink DATA files only into
# /usr/lib/glibc/bin/. CRITICAL: do NOT symlink shell wrappers (chrome,
# chrome_crashpad_handler are shell scripts in /opt/ that would overwrite the
# real ELF binaries already in /usr/lib/glibc/bin/).
if [ -d "$SQFS/opt/google/chrome" ] && [ -d "$SQFS/usr/lib/glibc/bin" ]; then
    log "Symlinking Chrome data files into glibc/bin..."
    _chrome_count=0
    # Only symlink known data files and directories — NOT binaries
    for _f in "$SQFS"/opt/google/chrome/*; do
        _bn=$(basename "$_f")
        # Skip files that are already ELF binaries in glibc/bin
        [ -e "$SQFS/usr/lib/glibc/bin/$_bn" ] && continue
        # Skip shell wrappers (they would overwrite ELF binaries)
        if [ -f "$_f" ] && head -c 2 "$_f" 2>/dev/null | grep -q '^#!'; then
            continue
        fi
        ln -sf "/opt/google/chrome/$_bn" "$SQFS/usr/lib/glibc/bin/$_bn"
        _chrome_count=$((_chrome_count + 1))
    done
    # V8 snapshot: Chrome looks for v8_context_snapshot.x86_64.bin but package
    # only has v8_context_snapshot.bin — create platform-specific symlink
    if [ -e "$SQFS/opt/google/chrome/v8_context_snapshot.bin" ] && \
       [ ! -e "$SQFS/usr/lib/glibc/bin/v8_context_snapshot.x86_64.bin" ]; then
        ln -sf "/opt/google/chrome/v8_context_snapshot.bin" \
            "$SQFS/usr/lib/glibc/bin/v8_context_snapshot.x86_64.bin"
        _chrome_count=$((_chrome_count + 1))
    fi
    # ANGLE GL libraries: Chrome needs libGLESv2.so, libEGL.so from its own dir
    for _f in "$SQFS"/opt/google/chrome/lib*.so*; do
        [ -f "$_f" ] || continue
        _bn=$(basename "$_f")
        [ -e "$SQFS/usr/lib/glibc/bin/$_bn" ] || {
            ln -sf "/opt/google/chrome/$_bn" "$SQFS/usr/lib/glibc/bin/$_bn"
            _chrome_count=$((_chrome_count + 1))
        }
    done
    log "  Chrome data symlinks: $_chrome_count"

    # Symlink Mesa DRI drivers into glibc path so Chrome's glibc mesa can find them
    if [ -d "$SQFS/usr/lib/dri" ]; then
        mkdir -p "$SQFS/usr/lib/glibc/dri"
        _dri_count=0
        for _dri in "$SQFS"/usr/lib/dri/*.so; do
            [ -f "$_dri" ] || continue
            _bn=$(basename "$_dri")
            [ -e "$SQFS/usr/lib/glibc/dri/$_bn" ] || {
                ln -sf "/usr/lib/dri/$_bn" "$SQFS/usr/lib/glibc/dri/$_bn"
                _dri_count=$((_dri_count + 1))
            }
        done
        log "  DRI driver symlinks: $_dri_count"
    fi

    # Create libdl.so.2 linker script (merged into libc in glibc 2.34+,
    # but Chrome crashpad handler was compiled against older glibc)
    if [ ! -e "$SQFS/usr/lib/glibc/libdl.so.2" ]; then
        cat > "$SQFS/usr/lib/glibc/libdl.so.2" << 'LIBDLSCRIPT'
/* GNU ld script — libdl merged into libc in glibc 2.34+ */
OUTPUT_FORMAT(elf64-x86-64)
GROUP ( /usr/lib/glibc/libc.so.6 )
LIBDLSCRIPT
        log "  Created libdl.so.2 linker script"
    fi
fi

# ── Fix glibc symlinks (robust version-mismatch handling) ──────────────────
# Debian glibc .deb puts real .so files in /lib/x86_64-linux-gnu/ and
# /usr/lib/glibc/ has symlinks pointing there. These absolute symlinks
# break when squashfs is mounted elsewhere.
# Fix: resolve ALL broken symlinks using basename matching.
if [ -d "$SQFS/usr/lib/glibc" ]; then
    log "Fixing glibc symlinks..."
    _fix_count=0

    # Phase 1: Build lookup table of real .so files using a temp file
    # (eval fails on filenames with dots like ANSI_X3.110.so)
    _lookup=$(mktemp)
    for f in "$SQFS"/usr/lib/glibc/*.so* "$SQFS"/lib/x86_64-linux-gnu/*.so* "$SQFS"/lib/*.so*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        echo "$(basename "$f")	$f" >> "$_lookup"
    done

    # Phase 2: Fix broken symlinks in /usr/lib/glibc/
    for link in "$SQFS"/usr/lib/glibc/*; do
        [ -L "$link" ] || continue
        [ -f "$link" ] && continue  # symlink target exists, OK

        fname=$(basename "$link")
        target=$(readlink "$link")
        real_file=""

        # Strategy 1: exact basename match
        real_file=$(awk -F'\t' -v name="$fname" '$1==name{print $2; exit}' "$_lookup")

        # Strategy 2: target basename match (for libfoo.so -> libfoo.so.1 cases)
        if [ -z "$real_file" ]; then
            _target_base=$(basename "$target")
            real_file=$(awk -F'\t' -v name="$_target_base" '$1==name{print $2; exit}' "$_lookup")
        fi

        # Strategy 3: prefix match (libfoo.so.1 -> find libfoo.so.1.*)
        if [ -z "$real_file" ]; then
            real_file=$(awk -F'\t' -v name="$fname" '$1~"^"name"\\."{print $2; exit}' "$_lookup")
        fi

        # Strategy 4: for ld-linux/ld.so variants
        if [ -z "$real_file" ]; then
            case "$fname" in
                ld-*.so*|ld-linux*.so*)
                    real_file=$(awk -F'\t' '$1~/^ld-.*\.so/{print $2; exit}' "$_lookup")
                    ;;
            esac
        fi

        if [ -n "$real_file" ] && [ -f "$real_file" ]; then
            rm "$link"
            cp "$real_file" "$link"
            _fix_count=$((_fix_count + 1))
            log "  Fixed: $fname (was -> $target)"
        else
            log "  WARNING: $fname broken symlink, no real file found"
        fi
    done

    # Phase 3: Ensure critical symlinks exist
    if [ -f "$SQFS/usr/lib/glibc/ld-linux-x86-64.so.2" ]; then
        mkdir -p "$SQFS/lib64"
        ln -sf /usr/lib/glibc/ld-linux-x86-64.so.2 "$SQFS/lib64/ld-linux-x86-64.so.2"
    fi

    # Phase 4: Create missing version symlinks
    # If libfoo.so.1.2.3 exists as real file, ensure libfoo.so.1 and libfoo.so exist
    for f in "$SQFS"/usr/lib/glibc/*.so.*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        _bname=$(basename "$f")
        # Count dots after .so to determine if it's versioned (at least one .N)
        case "$_bname" in
            *.so.*.*) ;; # has version — continue
            *) continue ;; # no version — skip
        esac
        _base=$(echo "$_bname" | sed 's/\.so\..*//')
        _ver=$(echo "$_bname" | sed 's/.*\.so\.//')
        _major=$(echo "$_ver" | cut -d. -f1)
        # Create major version symlink
        _major_link="$SQFS/usr/lib/glibc/${_base}.so.${_major}"
        if [ ! -e "$_major_link" ]; then
            ln -sf "$_bname" "$_major_link"
            _fix_count=$((_fix_count + 1))
        fi
        # Create base symlink
        _base_link="$SQFS/usr/lib/glibc/${_base}.so"
        if [ ! -e "$_base_link" ]; then
            ln -sf "$_bname" "$_base_link"
            _fix_count=$((_fix_count + 1))
        fi
    done

    rm -f "$_lookup"
    log "  glibc symlinks fixed ($_fix_count fixes)"
fi
# ── Fix Qt5 platform plugin directory structure ─────────────────────────────
# zapt flattens all .so files into /usr/lib/glibc/ but Qt5 needs plugins in
# a specific directory tree: qt5/plugins/platforms/, qt5/plugins/wayland/, etc.
# Detect Qt5 plugin .so files and create the expected directory structure.
if [ -d "$SQFS/usr/lib/glibc" ]; then
    log "Fixing Qt5 platform plugin directory structure..."
    _qt5_fix=0
    for _plugin in libqxcb libqwayland libqwayland-generic libqwayland-egl; do
        _so_file=$(find "$SQFS/usr/lib/glibc" -maxdepth 1 -name "${_plugin}*.so*" -type f | head -1)
        [ -z "$_so_file" ] && continue
        _so_name=$(basename "$_so_file")
        case "$_plugin" in
            libqxcb)     _dir="platforms" ;;
            libqwayland*) _dir="wayland" ;;
        esac
        _plugin_dir="$SQFS/usr/lib/glibc/qt5/plugins/$_dir"
        mkdir -p "$_plugin_dir"
        if [ ! -e "$_plugin_dir/$_so_name" ]; then
            ln -sf "/usr/lib/glibc/$_so_name" "$_plugin_dir/$_so_name"
            _qt5_fix=$((_qt5_fix + 1))
        fi
    done
    # Also link libqeglfs-integration if present
    for _f in "$SQFS"/usr/lib/glibc/libqeglfs*.so*; do
        [ -f "$_f" ] || continue
        _plugin_dir="$SQFS/usr/lib/glibc/qt5/plugins/egldeviceintegrations"
        mkdir -p "$_plugin_dir"
        _so_name=$(basename "$_f")
        if [ ! -e "$_plugin_dir/$_so_name" ]; then
            ln -sf "/usr/lib/glibc/$_so_name" "$_plugin_dir/$_so_name"
            _qt5_fix=$((_qt5_fix + 1))
        fi
    done
    log "  Qt5 plugin fixes: $_qt5_fix"
fi

log "Installing Terax AI terminal..."
# Priority: prebuilt/ (CI) > /tmp/terax-musl (local) > prebuilt .deb
TERAX_INSTALLED=0
if [ -f "$REPO_DIR/prebuilt/terax/usr/bin/terax" ]; then
    log "  Using prebuilt binary from prebuilt/terax/"
    cp -a "$REPO_DIR/prebuilt/terax/usr/bin/terax" "$SQFS/usr/bin/terax" 2>/dev/null || true
    chmod +x "$SQFS/usr/bin/terax" 2>/dev/null || true
    if [ -d "$REPO_DIR/prebuilt/terax/usr/lib/terax" ]; then
        mkdir -p "$SQFS/usr/lib/terax"
        cp -a "$REPO_DIR/prebuilt/terax/usr/lib/terax/"* "$SQFS/usr/lib/terax/" 2>/dev/null || true
    fi
    TERAX_INSTALLED=1
    log "  Installed terax from prebuilt"
elif [ -d "/tmp/terax-musl" ] && [ -f "/tmp/terax-musl/usr/bin/terax" ]; then
    log "  Using vendored build from /tmp/terax-musl"
    cp -a /tmp/terax-musl/usr/bin/terax "$SQFS/usr/bin/terax" 2>/dev/null || true
    chmod +x "$SQFS/usr/bin/terax" 2>/dev/null || true
    if [ -d "/tmp/terax-musl/usr/lib/terax" ]; then
        mkdir -p "$SQFS/usr/lib/terax"
        cp -a /tmp/terax-musl/usr/lib/terax/* "$SQFS/usr/lib/terax/" 2>/dev/null || true
    fi
    TERAX_INSTALLED=1
    log "  Installed terax from vendored build"
fi
if [ "$TERAX_INSTALLED" = "0" ]; then
    log "  No prebuilt terax found, falling back to prebuilt .deb"
    TERAX_DEB="/tmp/terax.deb"
    wget -q -O "$TERAX_DEB" \
        "https://github.com/crynta/terax-ai/releases/download/v0.7.3/Terax_0.7.3_amd64.deb" 2>&1 || true
    if [ -f "$TERAX_DEB" ] && [ -x "$SQFS/usr/local/bin/zapt" ]; then
        "$SQFS/usr/local/bin/zapt" install --root "$SQFS" "$TERAX_DEB" 2>&1 || {
            log "WARNING: Terax install failed"
        }
        rm -f "$TERAX_DEB"
    fi
fi

# ── SuperLite Files (Tauri file manager, musl binary) ────────────────────
if [ -f "$REPO_DIR/prebuilt/superlite-files/usr/bin/superlite-files" ]; then
    log "Installing SuperLite Files..."
    cp -v "$REPO_DIR/prebuilt/superlite-files/usr/bin/superlite-files" "$SQFS/usr/bin/superlite-files"
    chmod +x "$SQFS/usr/bin/superlite-files"
    log "  Installed SuperLite Files"
else
    log "WARNING: SuperLite Files prebuilt not found"
fi

# ── Create glibc wrapper for terax ────────────────────────────────────────
# Terax is a glibc binary that needs the glibc ELF loader (ld-linux-x86-64.so.2)
# to run on musl Alpine. zapt's createGlibcWrapper handles Chrome.
if [ -d "$SQFS/usr/lib/glibc" ]; then
    _glibc_ld="$SQFS/usr/lib/glibc/ld-linux-x86-64.so.2"
    if [ -f "$_glibc_ld" ]; then
        # Terax wrapper — glibc binary that needs glibc libxslt/libexslt
        # LD_PRELOAD forces glibc libxslt to load instead of Alpine musl libxslt
        _terax_bin="$SQFS/usr/lib/glibc/bin/terax"
        if [ -f "$_terax_bin" ] && [ ! -f "$SQFS/usr/bin/terax" ]; then
            mkdir -p "$SQFS/usr/bin"
            cat > "$SQFS/usr/bin/terax" << 'TW'
#!/bin/sh
[ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=wayland-0
[ -z "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
# Preload glibc libxslt/libexslt to prevent Alpine musl versions from loading
export LD_PRELOAD="/usr/lib/glibc/libxslt.so.1 /usr/lib/glibc/libexslt.so.0"
exec /usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/lib/glibc /usr/lib/glibc/bin/terax "$@"
TW
            chmod +x "$SQFS/usr/bin/terax"
            log "  Created terax wrapper"
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
