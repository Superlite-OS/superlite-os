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
iface lo inet6 loopback
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

# ── Package world (unified packages.list, deduplicated) ─────────────────────
{
    sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$CONFIGS_DIR/packages.list" | sort -u
} | makefile root:root 0644 "$tmp"/etc/apk/world

# ── superlite-boot: flash disk detection + USB overlay ────────────────────────
# Replaces custom /sbin/init. Alpine's stock init handles overlayfs/modloop.
# This service handles: boot media symlink, USB overlay auto-partition.
mkdir -p "$tmp"/etc/init.d
makefile root:root 0755 "$tmp"/etc/init.d/superlite-boot <<'SVCEOF'
#!/sbin/openrc-run

description="SuperLite boot: flash disk detection + USB overlay"

depend() {
    after modloop mdev
    keyword -docker -lxc -openvz -prefix -vserver
}

_partition_name() {
    _disk="$1" _num="$2"
    case "$_disk" in
        /dev/nvme*|/dev/mmcblk*|/dev/md*) echo "${_disk}p${_num}" ;;
        *)                                 echo "${_disk}${_num}" ;;
    esac
}

_refresh_parts() {
    partprobe "$1" 2>/dev/null || true
    partx -u "$1" 2>/dev/null || true
    mdev -sf 2>/dev/null || true
}

start() {
    ebegin "SuperLite boot setup"

    # Bind mount modloop contents into root filesystem
    # Alpine's modloop service only symlinks /lib/modules from /.modloop/
    # Injected binaries (Chrome, glibc, zapt, terax, curl-imp, doublecmd)
    # live in /.modloop/ but need to be accessible at standard paths
    if [ -d /.modloop ]; then
        # /opt is entirely from modloop (Chrome + dependencies)
        [ -d /.modloop/opt ] && mount --bind /.modloop/opt /opt 2>/dev/null || true
        # /usr/lib/glibc — glibc libs for Chrome/curl-impersonate
        [ -d /.modloop/usr/lib/glibc ] && {
            mkdir -p /usr/lib/glibc
            mount --bind /.modloop/usr/lib/glibc /usr/lib/glibc 2>/dev/null || true
        }
        # /lib/x86_64-linux-gnu — real glibc .so files (ld-linux, libc, etc.)
        # Debian glibc .deb puts files here; symlinks in /usr/lib/glibc/ point here
        [ -d /.modloop/lib/x86_64-linux-gnu ] && {
            mkdir -p /lib/x86_64-linux-gnu
            mount --bind /.modloop/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu 2>/dev/null || true
        }
        # /usr/local/lib/curl-impersonate
        [ -d /.modloop/usr/local/lib/curl-impersonate ] && {
            mkdir -p /usr/local/lib/curl-impersonate
            mount --bind /.modloop/usr/local/lib/curl-impersonate /usr/local/lib/curl-impersonate 2>/dev/null || true
        }
        # /lib/doublecmd — Double Commander libs
        [ -d /.modloop/lib/doublecmd ] && {
            mkdir -p /lib/doublecmd
            mount --bind /.modloop/lib/doublecmd /lib/doublecmd 2>/dev/null || true
        }
        # Symlink individual binaries (dirs mixed with apkovl files)
        for _bin in zapt; do
            [ -f "/.modloop/usr/local/bin/$_bin" ] && [ ! -f "/usr/local/bin/$_bin" ] && \
                ln -sf "/.modloop/usr/local/bin/$_bin" "/usr/local/bin/$_bin"
        done
        for _bin in terax doublecmd google-chrome-stable google-chrome; do
            [ -f "/.modloop/bin/$_bin" ] && [ ! -f "/bin/$_bin" ] && \
                ln -sf "/.modloop/bin/$_bin" "/bin/$_bin"
        done
        # Symlink curl-impersonate wrappers to PATH
        for _bin in curl-impersonate-chrome curl-impersonate-ff; do
            [ -f "/.modloop/usr/local/bin/$_bin" ] && [ ! -f "/usr/local/bin/$_bin" ] && \
                ln -sf "/.modloop/usr/local/bin/$_bin" "/usr/local/bin/$_bin"
        done
        # glibc ELF loader symlink — must point to real glibc loader (not gcompat)
        [ -d /lib64 ] || mkdir -p /lib64
        [ -f /lib64/ld-linux-x86-64.so.2 ] || \
            ln -sf /usr/lib/glibc/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2
    fi

    # Symlink /media/cdrom if not already set by initramfs
    if [ ! -e /media/cdrom ]; then
        for _m in /media/sd* /media/nvme* /media/mmcblk* /media/usb /media/sr*; do
            [ -d "$_m" ] || continue
            if [ -d "$_m/boot" ] || [ -d "$_m/apks" ] || [ -f "$_m/modloop-lts" ]; then
                ln -sf "$_m" /media/cdrom
                break
            fi
        done
    fi

    # Find SUPERLITE-RW partition
    OVERLAY_DEV=""
    for _d in /dev/disk/by-label/SUPERLITE-RW /dev/disk/by-label/superlite-rw; do
        [ -b "$_d" ] && OVERLAY_DEV="$_d" && break
    done

    # Auto-partition if no SUPERLITE-RW found
    if [ -z "$OVERLAY_DEV" ] && [ -L /media/cdrom ]; then
        _media=$(readlink -f /media/cdrom)
        case "$_media" in
            /dev/nvme*|/dev/mmcblk*|/dev/md*)
                _boot_disk=$(echo "$_media" | sed 's/p[0-9]*$//')
                ;;
            /dev/sd*)
                _boot_disk=$(echo "$_media" | sed 's/[0-9]*$//')
                ;;
            *) _boot_disk="" ;;
        esac

        if [ -n "$_boot_disk" ] && [ -b "$_boot_disk" ]; then
            _p2=$(_partition_name "$_boot_disk" 2)
            if [ ! -b "$_p2" ] && command -v sfdisk >/dev/null 2>&1; then
                einfo "Creating overlay partition on $_boot_disk"
                echo ", +" | sfdisk -a -q "$_boot_disk" 2>/dev/null
                _refresh_parts "$_boot_disk"
                if [ -b "$_p2" ] && command -v mkfs.ext4 >/dev/null 2>&1; then
                    mkfs.ext4 -O ^64bit -L SUPERLITE-RW -F "$_p2" >/dev/null 2>&1
                    OVERLAY_DEV="$_p2"
                fi
            fi
        fi
    fi

    eend 0
}
SVCEOF

# ── OpenRC services ───────────────────────────────────────────────────────────
rc_add superlite-boot boot
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
    # Safety net: ensure all scripts are executable
    find "$tmp"/etc/skel/.config/scripts -name "*.sh" -exec chmod +x {} + 2>/dev/null
    find "$tmp"/root/.config/scripts -name "*.sh" -exec chmod +x {} + 2>/dev/null

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

# NOTE: Heavy binaries (Chrome, glibc, zapt, curl-impersonate, Double Commander)
# are injected into the modloop squashfs by inject-modloop.sh after ISO build.
# This keeps the apkovl small (< 10MB config-only) for low-RAM boot.

# ── Install zapt config only (binary injected by inject-modloop.sh) ────────
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
if [ -n "$ZAPT_DIR" ]; then
    mkdir -p "$tmp"/etc/zapt
    if [ -f "$ZAPT_DIR/etc/sources.conf" ]; then
        cp "$ZAPT_DIR/etc/sources.conf" "$tmp"/etc/zapt/sources.conf
    fi
fi

# Clone and install Chrome extensions + build native hosts
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
    # Build native host BEFORE cleanup
    if command -v cargo >/dev/null 2>&1 && [ -d "/tmp/br-download-manager/src" ]; then
        echo "Building br-download-manager native host..."
        (cd /tmp/br-download-manager && cargo build --release 2>/dev/null && \
            cp target/release/br "$tmp/usr/local/bin/brdm-host") 2>&1 || true
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
    # Build native host BEFORE cleanup
    if command -v cargo >/dev/null 2>&1 && [ -d "/tmp/remote-browser-control/host" ]; then
        echo "Building remote-browser-control native host..."
        (cd /tmp/remote-browser-control/host && cargo build --release 2>/dev/null && \
            cp target/release/rbc-host "$tmp/usr/local/bin/rbc-host") 2>&1 || true
    fi
    rm -rf /tmp/remote-browser-control
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
            sudo superlite-installer &
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
export XDG_CURRENT_DESKTOP=labwc:wlroots
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11
export WLR_LIBINPUT_NO_DEVICES=1
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER
export XDG_SEAT=seat0
export LIBSEAT_BACKEND=seatd
EOF

# ── LabWC auto-start for desktop mode ────────────────────────────────────────
mkdir -p "$tmp"/root
cat >> "$tmp"/root/.profile <<'PROFILE_EOF'

# ── Wayland environment ──────────────────────────────────────────────────────
if test -z "${XDG_SESSION_TYPE}"; then
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=labwc:wlroots
    export XDG_SEAT=seat0
    export LIBSEAT_BACKEND=seatd
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
# Modes: desktop (default), install, shell

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

# Auto-detect QEMU/VirtualBox — skip labwc in VM without display
# Only set shell mode if no VGA console AND running in a VM
if [ -z "$MODE" ] && grep -q "console=ttyS0" /proc/cmdline 2>/dev/null; then
    # Check if we're in a VM (QEMU/VirtualBox/KVM) without real display
    if grep -qE "(qemu|virtualbox|kvm|hyperv)" /proc/cpuinfo 2>/dev/null || \
       [ ! -d /sys/class/drm/card0 ] 2>/dev/null; then
        MODE="shell"
    fi
fi

# Start seatd + elogind for all modes (labwc needs libseat session)
if ! pgrep -x seatd >/dev/null 2>&1; then
    /sbin/rc-service seatd start 2>/dev/null || true
fi
if ! pgrep -x elogind >/dev/null 2>&1; then
    /sbin/rc-service elogind start 2>/dev/null || true
fi
sleep 1

case "$MODE" in
    install)
        # ── Installer mode (Python) ──────────────────────────────────────
        echo "install" > /tmp/.bootmode
        ;;
    shell)
        # ── Shell mode (no GUI, for QEMU/headless) ──────────────────────
        echo "Shell mode — no desktop"
        return 0 2>/dev/null || exit 0
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

# Ensure XDG_RUNTIME_DIR exists (labwc/elogind needs it)
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null

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
        sudo superlite-installer
        ;;
    *Shell*)
        terax
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
    install) printf '  Mode: \033[1minstall\033[0m — Run \033[1msuperlite-installer\033[0m\n\n' ;;
    *)       printf '  Mode: \033[1mdesktop\033[0m\n\n' ;;
esac
MOTDEOF

# ── Install SuperLite Python Installer ───────────────────────────────────────
echo "Installing SuperLite Installer..."
INSTALLER_DIR="$tmp/usr/lib/superlite-installer"
mkdir -p "$INSTALLER_DIR"
if [ -d "$SCRIPT_DIR/../../installer" ]; then
    cp -a "$SCRIPT_DIR/../../installer"/*.py "$INSTALLER_DIR/" 2>/dev/null || true
    cp -a "$SCRIPT_DIR/../../installer"/*.conf "$INSTALLER_DIR/" 2>/dev/null || true
fi
# Create wrapper script
makefile root:root 0755 "$tmp"/usr/local/bin/superlite-installer <<'INSTALLER_WRAPPER'
#!/bin/sh
cd /usr/lib/superlite-installer
exec python3 main.py "$@"
INSTALLER_WRAPPER

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

# ── /sbin/init: use Alpine stock init (no override) ──────────────────────────
# Alpine's initramfs handles: overlayfs, apkovl extraction, modloop mount,
# switch_root → openrc sysinit. Custom /sbin/init caused boot hang by
# fighting with stock init. Flash disk detection is now an OpenRC service.

# ── Sysctl (IPv6 & Network) ─────────────────────────────────────────────────
mkdir -p "$tmp"/etc/sysctl.d
makefile root:root 0644 "$tmp"/etc/sysctl.d/99-ipv6.conf <<EOF
# Enable IPv6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# Accept Router Advertisements (for SLAAC)
net.ipv6.conf.all.accept_ra = 1
net.ipv6.conf.default.accept_ra = 1

# Disable IPv6 forwarding (workstation, not router)
net.ipv6.conf.all.forwarding = 0

# Privacy extensions (temporary addresses)
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
EOF

# ── TCP BBR Congestion Control ──────────────────────────────────────────────
mkdir -p "$tmp"/etc/modules-load.d
makefile root:root 0644 "$tmp"/etc/modules-load.d/bbr.conf <<EOF
tcp_bbr
EOF

makefile root:root 0644 "$tmp"/etc/sysctl.d/99-bbr.conf <<EOF
# TCP BBR congestion control (IPv4 & IPv6)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.tcp_congestion_control = bbr
EOF

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

[connection]
ipv6.method=auto
ipv6.addr-gen-mode=stable-privacy
ipv6.ip6-privacy=2
EOF

# ── Generate apkovl ───────────────────────────────────────────────────────────
# Only include dirs that exist (heavy binaries moved to modloop via inject-modloop.sh)
_TAR_DIRS=""
for _d in sbin etc root usr opt lib lib64; do
    [ -d "$tmp/$_d" ] && _TAR_DIRS="$_TAR_DIRS $_d"
done
tar -c -C "$tmp" $_TAR_DIRS | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
echo "[overlay] Generated: $HOSTNAME.apkovl.tar.gz"
