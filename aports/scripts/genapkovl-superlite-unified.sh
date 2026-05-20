#!/bin/sh -e
# ============================================================================
# SuperLite OS — Unified ISO Overlay
# Single ISO, 3 modes via boot menu:
#   superlite.desktop  → Live desktop
#   superlite.install  → Installer mode
#   superlite.parted   → Partition manager
#
# Boot mode is set via kernel cmdline: superlite.mode=desktop|install|parted
# ============================================================================

HOSTNAME="$1"
if [ -z "$HOSTNAME" ]; then
    echo "usage: $0 hostname"
    exit 1
fi

cleanup() { rm -rf "$tmp"; }

makefile() {
    OWNER="$1"; PERMS="$2"; FILENAME="$3"
    cat > "$FILENAME"
    chown "$OWNER" "$FILENAME"
    chmod "$PERMS" "$FILENAME"
}

rc_add() {
    mkdir -p "$tmp"/etc/runlevels/"$2"
    ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

# ── Hostname ──────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

# ── Network ───────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/network
makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF

# ── Repositories ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIGS_DIR=""
for _candidate in \
    "$SCRIPT_DIR/alpine/configs" \
    "$SCRIPT_DIR/../../alpine/configs" \
    "/build/alpine/configs" \
    "./alpine/configs"; do
    if [ -d "$_candidate" ] && [ -f "$_candidate/repositories" ]; then
        CONFIGS_DIR="$_candidate"
        break
    fi
done
if [ -z "$CONFIGS_DIR" ]; then
    echo "ERROR: alpine/configs directory not found" >&2
    exit 1
fi

mkdir -p "$tmp"/etc/apk
{
    echo "/media/cdrom/apks"
    cat "$CONFIGS_DIR/repositories"
} | makefile root:root 0644 "$tmp"/etc/apk/repositories

# ── Package world (merged from all lists, deduplicated) ──────────────────────
{
    for f in "$CONFIGS_DIR/packages.list" "$CONFIGS_DIR/packages-install.list" "$CONFIGS_DIR/packages-parted.list"; do
        [ -f "$f" ] && sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$f"
    done | sort -u
} | makefile root:root 0644 "$tmp"/etc/apk/world

# ── OpenRC services ───────────────────────────────────────────────────────────
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add networking boot
rc_add urandom boot
rc_add keymaps boot
rc_add udev-trigger boot
rc_add udev-settle boot
rc_add udev-postmount boot

rc_add seatd default
rc_add elogind default
rc_add dbus default
rc_add polkitd default
rc_add networkmanager default
rc_add chronyd default
rc_add sshd default

# SSH server: allow root login for live debugging (password required)
mkdir -p "$tmp"/etc/ssh
makefile root:root 0600 "$tmp"/etc/ssh/sshd_config <<'SSHEOF'
Port 22
PermitRootLogin yes
PermitEmptyPasswords no
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
SSHEOF

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# ── agetty ────────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/runlevels/default

# ── Auto-login ────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/usr/sbin
makefile root:root 0755 "$tmp"/usr/sbin/autologin <<'EOF'
#!/bin/sh
exec login -f root
EOF

makefile root:root 0644 "$tmp"/etc/securetty <<'EOF'
tty1
ttyS0
EOF

mkdir -p "$tmp"/etc/conf.d
makefile root:root 0644 "$tmp"/etc/conf.d/agetty.tty1 <<EOF
GETTY_ARGS="--autologin root --noclear 115200 tty1"
EOF

makefile root:root 0644 "$tmp"/etc/conf.d/agetty.ttyS0 <<EOF
GETTY_ARGS="--autologin root --noclear 115200 ttyS0"
EOF

# ── inittab ───────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/inittab <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/sbin/agetty -a root -L 115200 tty1 linux
ttyS0::respawn:/sbin/agetty -a root -L 115200 ttyS0 vt100

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

# ── sudoers ───────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/sudoers.d
makefile root:root 0440 "$tmp"/etc/sudoers.d/live <<EOF
live ALL=(ALL) NOPASSWD: ALL
EOF

# ── Groups ────────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/group <<'EOF'
root:x:0:root
bin:x:1:root,bin,daemon
daemon:x:2:root,bin,daemon
sys:x:3:root,bin,adm
adm:x:4:root,adm,daemon
tty:x:5:
disk:x:6:root,adm
lp:x:7:daemon
mem:x:9:
kmem:x:10:
wheel:x:11:root
floppy:x:11:root
mail:x:12:postfix
news:x:13:
uucp:x:14:
audio:x:15:root
cdrom:x:16:root
dialout:x:18:root
ftp:x:21:
sshd:x:22:
input:x:23:root
kvm:x:34:root
video:x:36:root
games:x:35:
usb:x:43:
seat:x:480:root
seatd:x:481:root
messagebus:x:482:
polkitd:x:483:
netdev:x:1000:
tape:x:1001:
EOF

# ── Copy dotfiles ─────────────────────────────────────────────────────────────
# Try multiple paths (original repo, aports tree symlink, Docker build)
DOTFILES_DIR=""
for dir in \
    "$SCRIPT_DIR/../../dotfiles" \
    "$SCRIPT_DIR/../dotfiles" \
    "/build/dotfiles" \
    "./dotfiles"; do
    if [ -d "$dir" ] && [ -f "$dir/.profile" ]; then
        DOTFILES_DIR="$dir"
        break
    fi
done

if [ -d "$DOTFILES_DIR" ]; then
    mkdir -p "$tmp"/etc/skel
    for item in "$DOTFILES_DIR"/.*; do
        name="$(basename "$item")"
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        [ "$name" = "usr" ] && continue
        cp -a "$item" "$tmp"/etc/skel/
    done
    mkdir -p "$tmp"/root
    for item in "$DOTFILES_DIR"/.*; do
        name="$(basename "$item")"
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        [ "$name" = "usr" ] && continue
        cp -a "$item" "$tmp"/root/
    done
    if [ -d "$DOTFILES_DIR/usr/share" ]; then
        mkdir -p "$tmp"/usr/share
        cp -a "$DOTFILES_DIR"/usr/share/* "$tmp"/usr/share/
    fi

    # Copy Pictures (wallpapers) to skel and root
    if [ -d "$DOTFILES_DIR/Pictures" ]; then
        cp -a "$DOTFILES_DIR/Pictures" "$tmp"/etc/skel/
        cp -a "$DOTFILES_DIR/Pictures" "$tmp"/root/
    fi
fi

# ── Recolor and convert SVG icons to PNG ─────────────────────────────────────
# The icon theme SVGs use placeholder colors; recolor to match UI accent (#22AA99)
# and convert to PNG for reliable rendering in Thunar and other GTK apps.
_ACCENT="#22AA99"
_DARK="#0F766E"
_LIGHT="#5EEAD4"
_ICON_SVG_DIR="$tmp/root/.icons/superlite/scalable"
_ICON_PNG_DIR="$tmp/root/.icons/superlite/48x48"

if [ -d "$_ICON_SVG_DIR" ] && command -v rsvg-convert >/dev/null 2>&1; then
    echo "Recoloring and converting SVG icons to PNG..."
    for subdir in places actions devices mimetypes; do
        [ -d "$_ICON_SVG_DIR/$subdir" ] || continue
        mkdir -p "$_ICON_PNG_DIR/$subdir"
        for svg in "$_ICON_SVG_DIR/$subdir"/*.svg; do
            [ -f "$svg" ] || continue
            # Recolor SVG in-place (accent color substitution)
            sed -i \
                -e "s/fill=\"#8B5CF6\"/fill=\"$_ACCENT\"/g" \
                -e "s/fill=\"#7C3AED\"/fill=\"$_DARK\"/g" \
                -e "s/fill=\"#A78BFA\"/fill=\"$_LIGHT\"/g" \
                -e "s/fill=\"#34D399\"/fill=\"$_ACCENT\"/g" \
                -e "s/fill=\"#10B981\"/fill=\"$_DARK\"/g" \
                -e "s/fill=\"#60A5FA\"/fill=\"$_ACCENT\"/g" \
                -e "s/fill=\"#3B82F6\"/fill=\"$_DARK\"/g" \
                -e "s/fill=\"#F87171\"/fill=\"$_ACCENT\"/g" \
                -e "s/fill=\"#EF4444\"/fill=\"$_DARK\"/g" \
                -e "s/fill=\"#F472B6\"/fill=\"$_ACCENT\"/g" \
                -e "s/fill=\"#EC4899\"/fill=\"$_DARK\"/g" \
                -e "s/fill=\"#FBBF24\"/fill=\"$_ACCENT\"/g" \
                -e "s/fill=\"#F59E0B\"/fill=\"$_DARK\"/g" \
                -e "s/fill=\"#D1FAE5\"/fill=\"#CCFBF1\"/g" \
                -e "s/fill=\"#A7F3D0\"/fill=\"#99F6E4\"/g" \
                -e "s/fill=\"#DDD6FE\"/fill=\"#CCFBF1\"/g" \
                -e "s/fill=\"#C4B5FD\"/fill=\"#99F6E4\"/g" \
                -e "s/fill=\"#FDE68A\"/fill=\"#CCFBF1\"/g" \
                -e "s/fill=\"#FCD34D\"/fill=\"#99F6E4\"/g" \
                -e "s/fill=\"#E2E8F0\"/fill=\"#F0FDFA\"/g" \
                -e "s/fill=\"#CBD5E1\"/fill=\"#CCFBF1\"/g" \
                -e "s/fill=\"#FECACA\"/fill=\"#CCFBF1\"/g" \
                -e "s/fill=\"#FCA5A5\"/fill=\"#99F6E4\"/g" \
                "$svg"
            # Convert to PNG
            name=$(basename "$svg" .svg)
            rsvg-convert -w 48 -h 48 "$svg" -o "$_ICON_PNG_DIR/$subdir/$name.png" 2>/dev/null || true
        done
    done
    echo "Icon conversion complete."
fi

# Also generate PNGs for skel (copy from root's processed icons)
if [ -d "$_ICON_PNG_DIR" ]; then
    mkdir -p "$tmp"/etc/skel/.icons/superlite/48x48
    cp -a "$_ICON_PNG_DIR"/* "$tmp"/etc/skel/.icons/superlite/48x48/ 2>/dev/null || true
fi

# ── Build and install zapt ────────────────────────────────────────────────────
# zapt is a Go-based multi-source package manager
ZAPT_DIR=""
for dir in \
    "$SCRIPT_DIR/../../zapt" \
    "$SCRIPT_DIR/../zapt" \
    "/build/zapt" \
    "./zapt"; do
    if [ -d "$dir" ] && [ -f "$dir/main.go" ]; then
        ZAPT_DIR="$dir"
        break
    fi
done

if [ -n "$ZAPT_DIR" ] && command -v go >/dev/null 2>&1; then
    echo "Building zapt..."
    (cd "$ZAPT_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o "$tmp"/usr/local/bin/zapt .) 2>&1 || {
        echo "Warning: zapt build failed (see output above)"
    }

    # Install zapt config
    mkdir -p "$tmp"/etc/zapt
    if [ -f "$ZAPT_DIR/etc/sources.conf" ]; then
        cp "$ZAPT_DIR/etc/sources.conf" "$tmp"/etc/zapt/sources.conf
    fi
fi

# ── Install curl-impersonate (TLS fingerprint bypass) ────────────────────────
# NOTE: curl-impersonate binary is glibc-linked; needs gcompat in the ISO to run.
# During build, we only install files to the overlay — we do NOT exec the binary
# because the build Docker container may not have gcompat.
CURL_IMP_VERSION="0.6.1"
CURL_IMP_URL="https://github.com/lwthiker/curl-impersonate/releases/download/v${CURL_IMP_VERSION}/curl-impersonate-v${CURL_IMP_VERSION}.x86_64-linux-gnu.tar.gz"

echo "Installing curl-impersonate..."
wget -q -O /tmp/curl-impersonate.tar.gz "$CURL_IMP_URL" 2>/dev/null || true
if [ -f /tmp/curl-impersonate.tar.gz ]; then
    mkdir -p "$tmp/usr/local/lib/curl-impersonate"
    tar -xzf /tmp/curl-impersonate.tar.gz -C "$tmp/usr/local/lib/curl-impersonate" 2>/dev/null || true
    if [ -f "$tmp/usr/local/lib/curl-impersonate/curl-impersonate-chrome" ]; then
        chmod +x "$tmp/usr/local/lib/curl-impersonate/curl-impersonate-chrome"
        # Symlink binary directly (gcompat handles glibc in the ISO)
        mkdir -p "$tmp/usr/local/bin"
        ln -sf /usr/local/lib/curl-impersonate/curl-impersonate-chrome "$tmp/usr/local/bin/curl-impersonate-chrome"
        ln -sf /usr/local/bin/curl-impersonate-chrome "$tmp/usr/local/bin/curl"
        # Symlink wrapper scripts to PATH
        for w in "$tmp"/usr/local/lib/curl-impersonate/curl_*; do
            [ -f "$w" ] || continue
            ln -sf "/usr/local/lib/curl-impersonate/$(basename "$w")" "$tmp/usr/local/bin/$(basename "$w")"
        done
        echo "  curl-impersonate installed (curl → curl-impersonate-chrome)"
    else
        echo "  Warning: curl-impersonate binary not found in tarball"
    fi
    rm -f /tmp/curl-impersonate.tar.gz
fi

# ── Install Google Chrome + glibc compat ──────────────────────────────────────
CHROME_DEB="/tmp/google-chrome-stable.deb"
echo "Downloading Google Chrome..."
wget -q -O "$CHROME_DEB" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" 2>&1 || {
    echo "Warning: Chrome download failed"
}

if [ -f "$CHROME_DEB" ]; then
    echo "Installing Chrome via zapt..."
    "$tmp/usr/local/bin/zapt" install --root "$tmp" "$CHROME_DEB" 2>&1 || {
        echo "Warning: Chrome install failed (see output above)"
    }
    chmod 4755 "$tmp/opt/google/chrome/chrome-sandbox" 2>/dev/null || true
    mkdir -p "$tmp/usr/bin"
    # Symlinks point to glibc wrapper (set LD_LIBRARY_PATH for glibc libs)
    ln -sf /opt/google/chrome/chrome-glibc-wrapper "$tmp/usr/bin/google-chrome-stable"
    ln -sf /opt/google/chrome/chrome-glibc-wrapper "$tmp/usr/bin/google-chrome"
    rm -f "$CHROME_DEB"
fi

# ── Install glibc for Chrome (real glibc for glibc-linked binary) ─────────────
echo "Downloading glibc for Chrome..."
LIBC6_DEB="/tmp/libc6.deb"
LIBC6_URL="https://deb.debian.org/debian/pool/main/g/glibc/libc6_2.36-9+deb12u14_amd64.deb"
wget -q -O "$LIBC6_DEB" "$LIBC6_URL" 2>&1 || {
    echo "Warning: libc6 download failed"
}

if [ -f "$LIBC6_DEB" ]; then
    echo "Installing glibc via zapt..."
    GLIBC_ROOT="/tmp/glibc-root"
    mkdir -p "$GLIBC_ROOT"
    "$tmp/usr/local/bin/zapt" install --root "$GLIBC_ROOT" "$LIBC6_DEB" 2>&1 || {
        echo "Warning: glibc install failed"
    }

    # Copy glibc libs to ISO overlay
    GLIBC_DIR="$tmp/usr/lib/glibc"
    mkdir -p "$GLIBC_DIR"
    for lib in libc.so.6 ld-linux-x86-64.so.2 libm.so.6 libpthread.so.0 libdl.so.2 libresolv.so.2; do
        found="$(find "$GLIBC_ROOT" -name "$lib" 2>/dev/null | head -1)"
        [ -n "$found" ] && cp "$found" "$GLIBC_DIR/" 2>/dev/null
    done
    find "$GLIBC_ROOT" -name "libnss_*" -exec cp {} "$GLIBC_DIR/" \; 2>/dev/null

    if [ -f "$GLIBC_DIR/libc.so.6" ]; then
        # Create ld-linux symlink in /lib64 for Chrome ELF interpreter
        mkdir -p "$tmp/lib64"
        ln -sf /usr/lib/glibc/ld-linux-x86-64.so.2 "$tmp/lib64/ld-linux-x86-64.so.2"
        # Chrome wrapper that sets LD_LIBRARY_PATH for glibc
        cat > "$tmp/opt/google/chrome/chrome-glibc-wrapper" <<'GLIBC_WRAPPER'
#!/bin/sh
export LD_LIBRARY_PATH="/usr/lib/glibc:${LD_LIBRARY_PATH:-}"
exec /opt/google/chrome/chrome "$@"
GLIBC_WRAPPER
        chmod +x "$tmp/opt/google/chrome/chrome-glibc-wrapper"
        echo "  glibc libraries installed to /usr/lib/glibc/"
    else
        echo "  Warning: glibc extraction failed, Chrome may not work"
    fi
    rm -f "$LIBC6_DEB"
    rm -rf "$GLIBC_ROOT"
fi

# Clone and install Chrome extensions
EXTENSIONS_DIR="$tmp/usr/share/chrome/extensions"
mkdir -p "$EXTENSIONS_DIR"

# BR Download Manager extension
echo "Installing BR Download Manager extension..."
BRDM_EXT="$EXTENSIONS_DIR/br-download-manager"
if command -v git >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/kelvinzer0/br-download-manager.git /tmp/br-download-manager 2>&1 || true
    if [ -d "/tmp/br-download-manager/extension" ]; then
        cp -a /tmp/br-download-manager/extension "$BRDM_EXT"
    fi
    rm -rf /tmp/br-download-manager
fi

# Remote Browser Control extension
echo "Installing Remote Browser Control extension..."
RBC_EXT="$EXTENSIONS_DIR/remote-browser-control"
if command -v git >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/kelvinzer0/remote-browser-control.git /tmp/remote-browser-control 2>&1 || true
    if [ -d "/tmp/remote-browser-control/extension" ]; then
        cp -a /tmp/remote-browser-control/extension "$RBC_EXT"
    fi
    rm -rf /tmp/remote-browser-control
fi

# Build native hosts for extensions (if Rust is available)
if command -v cargo >/dev/null 2>&1; then
    # BR Download Manager native host
    if [ -d "/tmp/br-download-manager/src" ]; then
        echo "Building br-download-manager native host..."
        (cd /tmp/br-download-manager && cargo build --release 2>/dev/null && \
            cp target/release/br "$tmp/usr/local/bin/brdm-host") 2>&1 || true
    fi

    # Remote Browser Control native host
    if [ -d "/tmp/remote-browser-control/host" ]; then
        echo "Building remote-browser-control native host..."
        (cd /tmp/remote-browser-control/host && cargo build --release 2>/dev/null && \
            cp target/release/rbc-host "$tmp/usr/local/bin/rbc-host") 2>&1 || true
    fi
fi

# Set up Chrome managed policies
CHROME_POLICY_DIR="$tmp/etc/opt/chrome/policies/managed"
mkdir -p "$CHROME_POLICY_DIR"

cat > "$CHROME_POLICY_DIR/managed.json" << 'CHROME_POLICY'
{
  "BrowserSignin": 0,
  "DefaultBrowserSettingEnabled": false,
  "PromptForDownloadLocation": false,
  "DownloadDirectory": "/root/Downloads",
  "AutoOpenAllowedForURLs": ["*"],
  "ExtensionSettings": {
    "obbofbgglodjehllcnfggbmjhpcphlbl": {
      "installation_mode": "force_installed",
      "update_url": "file:///usr/share/chrome/extensions/br-download-manager"
    }
  }
}
CHROME_POLICY

# Create desktop entry for Chrome with extension loading
CHROME_DESKTOP_DIR="$tmp/usr/share/applications"
mkdir -p "$CHROME_DESKTOP_DIR"

# Build extension list for --load-extension flag
CHROME_EXT_FLAGS=""
if [ -d "$BRDM_EXT" ]; then
    CHROME_EXT_FLAGS="--load-extension=$BRDM_EXT"
fi
if [ -d "$RBC_EXT" ]; then
    CHROME_EXT_FLAGS="${CHROME_EXT_FLAGS:+$CHROME_EXT_FLAGS,}$RBC_EXT"
fi

cat > "$CHROME_DESKTOP_DIR/google-chrome.desktop" << DESKTOP_ENTRY
[Desktop Entry]
Version=1.0
Name=Google Chrome
Comment=Web Browser
Exec=google-chrome-stable --no-first-run --no-default-browser-check --disable-features=WaylandWindowDecorations --ozone-platform=wayland --enable-wayland-ime $CHROME_EXT_FLAGS %U
Icon=google-chrome
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=google-chrome
DESKTOP_ENTRY

# Register native messaging hosts for Chrome
NATIVE_HOST_DIR="$tmp/etc/opt/chrome/native-messaging-hosts"
mkdir -p "$NATIVE_HOST_DIR"

# BR Download Manager native messaging manifest
if [ -f "$tmp/usr/local/bin/brdm-host" ]; then
    cat > "$NATIVE_HOST_DIR/com.kelvin.brdm.json" << 'NATIVE_MANIFEST'
{
  "name": "com.kelvin.brdm",
  "description": "BR Download Manager Native Host",
  "path": "/usr/local/bin/brdm-host",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://obbofbgglodjehllcnfggbmjhpcphlbl/"
  ]
}
NATIVE_MANIFEST
fi

# Remote Browser Control native messaging manifest
if [ -f "$tmp/usr/local/bin/rbc-host" ]; then
    cat > "$NATIVE_HOST_DIR/com.kelvin.rbc.json" << 'NATIVE_MANIFEST'
{
  "name": "com.kelvin.rbc",
  "description": "Remote Browser Control Native Host",
  "path": "/usr/local/bin/rbc-host",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://*/*"
  ]
}
NATIVE_MANIFEST
fi

# ── Append boot mode handling to labwc autostart ──────────────────────────────
# This reads /tmp/.bootmode (written by 00-boot-mode.sh) and launches
# the appropriate GUI app after labwc and desktop services are ready.
_bootmode_handler='

# ── Boot mode handler (unified ISO) ──────────────────────────────────────────
if [ -f /tmp/.bootmode ]; then
    _bootmode=$(cat /tmp/.bootmode)
    rm -f /tmp/.bootmode
    case "$_bootmode" in
        menu)
            sleep 1
            superlite-gui-menu &
            ;;
        install)
            sleep 1
            sudo calamares &
            ;;
    esac
fi'

# Append to root's autostart
mkdir -p "$tmp"/root/.config/labwc
printf '%s\n' "$_bootmode_handler" >> "$tmp"/root/.config/labwc/autostart

# Append to skel's autostart (for new users)
mkdir -p "$tmp"/etc/skel/.config/labwc
printf '%s\n' "$_bootmode_handler" >> "$tmp"/etc/skel/.config/labwc/autostart

# ── Shell profiles ────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/profile.d
makefile root:root 0755 "$tmp"/etc/profile.d/xdg.sh <<'EOF'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11
export WLR_LIBINPUT_NO_DEVICES=1
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER
export XDG_SEAT=seat0
EOF

# ── LabWC auto-start for desktop mode ────────────────────────────────────────
mkdir -p "$tmp"/root
cat >> "$tmp"/root/.profile <<'PROFILE_EOF'

# ── Wayland environment ──────────────────────────────────────────────────────
if test -z "${XDG_SESSION_TYPE}"; then
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=wlroots
    export XDG_SEAT=seat0
    export QT_QPA_PLATFORM=wayland
    export MOZ_ENABLE_WAYLAND=1
    export GDK_BACKEND=wayland,x11
fi
[ -z "$WLR_LIBINPUT_NO_DEVICES" ] && export WLR_LIBINPUT_NO_DEVICES=1
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER
PROFILE_EOF

# ── Boot mode detection & launcher ────────────────────────────────────────────
# Reads superlite.mode from kernel cmdline, launches appropriate mode
makefile root:root 0755 "$tmp"/etc/profile.d/00-boot-mode.sh <<'BOOTMODE_EOF'
#!/bin/sh
# SuperLite OS — Boot mode launcher
# Reads superlite.mode= from /proc/cmdline
# Modes: desktop (default), install

case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac

# Only run on tty1
if [ "$(tty)" != "/dev/tty1" ]; then
    return 0 2>/dev/null || exit 0
fi

# Prevent running twice
if [ -f /tmp/.bootmode_done ]; then
    return 0 2>/dev/null || exit 0
fi
touch /tmp/.bootmode_done 2>/dev/null

# Read mode from kernel cmdline
MODE=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
    case "$arg" in
        superlite.mode=*) MODE="${arg#superlite.mode=}" ;;
    esac
done

# Start seatd for all modes
if ! pgrep -x seatd >/dev/null 2>&1; then
    sudo rc-service seatd start 2>/dev/null || true
    sleep 1
fi

case "$MODE" in
    install)
        # ── Installer mode (Calamares) ──────────────────────────────────
        echo "install" > /tmp/.bootmode
        ;;
    desktop)
        # ── Desktop mode (explicit, no menu) ────────────────────────────
        # No flag file — autostart skips menu
        ;;
    *)
        # ── No mode specified — show GUI boot menu ──────────────────────
        echo "menu" > /tmp/.bootmode
        ;;
esac

exec dbus-run-session labwc
BOOTMODE_EOF

# ── Tofi boot menu config ─────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/tofi
makefile root:root 0644 "$tmp"/etc/tofi/config_bootmenu <<'TOFI_EOF'
width = 100%
height = 100%
padding-left = 14%
padding-top = 36%
horizontal = false
result-spacing = 24
num-results = 3
prompt-text = ""
min-input-width = 0
font-size = 20
font = JetBrains Mono Medium
outline-width = 0
border-width = 0
background-color = #1a1a2e
text-color = #e0e0e0
selection-color = #22AA99
selection-background = #16213e
hint-font = false
text-cursor = false
hide-cursor = true
hide-input = true
drun-launch = false
late-keyboard-init = true
TOFI_EOF

# ── GUI Boot Menu (tofi-based) ───────────────────────────────────────────────
mkdir -p "$tmp"/usr/local/bin
makefile root:root 0755 "$tmp"/usr/local/bin/superlite-gui-menu <<'MENU_EOF'
#!/bin/sh
# SuperLite OS — GUI Boot Menu (tofi)
# Shown when no superlite.mode= kernel parameter is set

choice=$(printf "SuperLite OS  >  Desktop\nSuperLite OS  >  Install\nSuperLite OS  >  Shell" | tofi -c /etc/tofi/config_bootmenu)

case "$choice" in
    *Desktop*)
        # Desktop is already running (autostart), do nothing
        ;;
    *Install*)
        sudo calamares
        ;;
    *Shell*)
        foot -T "Shell"
        ;;
esac
MENU_EOF

# ── Dynamic MOTD ──────────────────────────────────────────────────────────────
makefile root:root 0755 "$tmp"/etc/profile.d/motd.sh <<'MOTDEOF'
#!/bin/sh
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac

KERNEL="$(uname -r)"
LAST_LOGIN="$(last -1 -F "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}')"
[ -z "$LAST_LOGIN" ] && LAST_LOGIN="$(date '+%Y-%m-%d %H:%M')"
LINE="$(printf '%0.0s─' $(seq 1 67))"

# Detect boot mode
MODE=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
    case "$arg" in superlite.mode=*) MODE="${arg#superlite.mode=}";; esac
done

printf '\n'
printf '  Linux %-44s Last login: %s\n' "$KERNEL" "$LAST_LOGIN"
printf '  %s\n' "$LINE"
printf '  "Stay curious. Break things responsibly."\n'
printf '  %s\n' "$LINE"

case "$MODE" in
    install) printf '  Mode: \033[1minstall\033[0m — Run \033[1mCalamares\033[0m\n\n' ;;
    *)       printf '  Mode: \033[1mdesktop\033[0m\n\n' ;;
esac
MOTDEOF

# ── Install Calamares (system installer) ──────────────────────────────────────
echo "Installing Calamares..."
apk add calamares calamares-branding 2>&1 || {
    echo "Warning: calamares package install failed (not in repos)"
}

# ── MOTD ──────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/motd <<'EOF'

        ╲╲╲╲
       ╲╲╲╲╲╲
      ╲╲    ╲╲
     ╲╲      ╲╲          superlite
    ╲╲        ╲╲         ──────────────────────────────────
   ╲╲    ╱╲    ╲╲        Alpine · LabWC · Wayland
  ╲╲    ╱  ╲    ╲╲
 ╲╲    ╱    ╲    ╲╲      desktop · install
╱╱╱   ╱      ╲   ╲╲╲
      ╱        ╲

EOF

# ── Hosts ─────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/hosts <<EOF
127.0.0.1 localhost $HOSTNAME
::1       localhost ip6-localhost ip6-loopback
EOF

# ── fstab ─────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/fstab <<EOF
proc            /proc    proc     defaults              0 0
sysfs           /sys     sysfs    defaults              0 0
devtmpfs        /dev     devtmpfs defaults              0 0
tmpfs           /tmp     tmpfs    defaults,noatime      0 0
tmpfs           /run     tmpfs    defaults,noatime      0 0
EOF

# ── /sbin/init ────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/sbin
makefile root:root 0755 "$tmp"/sbin/init <<'INITEOF'
#!/bin/sh
mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys  || mount -t sysfs sysfs /sys
mountpoint -q /dev  || mount -t devtmpfs devtmpfs /dev
for mod in loop squashfs overlay; do modprobe "$mod" 2>/dev/null; done
exec /sbin/openrc sysinit
INITEOF

# ── NetworkManager ────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/NetworkManager
makefile root:root 0644 "$tmp"/etc/NetworkManager/NetworkManager.conf <<EOF
[main]
plugins=ifupdown,keyfile
dhcp=internal
[ifupdown]
managed=false
[device]
wifi.backend=wpa_supplicant
EOF

# ── Generate apkovl ───────────────────────────────────────────────────────────
tar -c -C "$tmp" etc root usr | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
echo "[overlay] Generated: $HOSTNAME.apkovl.tar.gz"
