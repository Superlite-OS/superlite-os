#!/bin/bash
# ============================================================================
# SuperLite OS — Build Script (Alpine Native)
# ============================================================================
# Replaces Yocto entirely. Uses Alpine's mkimage.sh — simple, fast, reliable.
#
# Usage:
#   ./build.sh                    # Build ISO (requires root or Docker)
#   ./build.sh --setup-only       # Just set up the build environment
#   ./build.sh --docker           # Build inside Docker container
#   ./build.sh --output /path     # Custom output path
#
# Requirements: Alpine Linux (or Docker)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APORTS_DIR="${SCRIPT_DIR}/aports"
OUTPUT=""
SETUP_ONLY=false
USE_DOCKER=false
TAG="superlite"
VARIANT="superlite"  # superlite | superlite-install | superlite-parted

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-only) SETUP_ONLY=true; shift ;;
        --docker)     USE_DOCKER=true; shift ;;
        --output)     OUTPUT="$2"; shift 2 ;;
        --tag)        TAG="$2"; shift 2 ;;
        --variant)    VARIANT="$2"; shift 2 ;;
        --all)        VARIANT="all"; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --variant NAME   Build variant: superlite (default), superlite-install, superlite-parted"
            echo "  --all            Build all three variants"
            echo "  --setup-only     Just set up the build environment"
            echo "  --docker         Build inside Docker container"
            echo "  --output PATH    Custom output path"
            echo "  --tag NAME       Build tag"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

log() { echo "[build] $*"; }

# ── Build function (reused for all variants) ──────────────────────────────────
build_variant() {
    local variant="$1"
    local tag="$2"
    local output_dir="$3"

    log "Building variant: ${variant} (tag: ${tag})"

    if [[ "$USE_DOCKER" == true ]]; then
        _docker_build "$variant" "$tag" "$output_dir"
    else
        _native_build "$variant" "$tag" "$output_dir"
    fi
}

_docker_build() {
    local variant="$1"
    local tag="$2"
    local output_dir="$3"

    log "Building ${variant} inside Docker..."
    mkdir -p "$output_dir"

    docker run --rm \
        --cap-add SYS_ADMIN \
        -e VARIANT="$variant" \
        -e TAG="$tag" \
        -v "${SCRIPT_DIR}:/build" \
        -w /build \
        alpine:3.23 \
        sh -c '
            set -e
            apk add --no-cache alpine-sdk build-base apk-tools alpine-conf \
                busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools upx \
                grub-efi grub-bios git go librsvg \
                --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
                    qt5-qtbase-dev qt5-qtx11extras-dev

            adduser -D build
            addgroup build abuild 2>/dev/null || true
            passwd -d build
            echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

            su build -c "abuild-keygen -a -n"
            git clone --depth=1 https://git.alpinelinux.org/aports /home/build/aports

            cp /build/aports/scripts/mkimg.${VARIANT}.sh /home/build/aports/scripts/
            cp /build/aports/scripts/genapkovl-${VARIANT}.sh /home/build/aports/scripts/
            chmod +x /home/build/aports/scripts/genapkovl-${VARIANT}.sh
            ln -sf /build/dotfiles /home/build/aports/scripts/dotfiles
            ln -sf /build/alpine /home/build/aports/scripts/alpine
            chown -R build:build /home/build/aports

            mkdir -p /build/output/${VARIANT}
            chown build:build /build/output/${VARIANT}

            PUBKEY=$(find /home/build/.abuild -name "build-*.rsa.pub" -type f 2>/dev/null | head -1)
            PRIVKEY=$(find /home/build/.abuild -name "build-*.rsa" -type f 2>/dev/null | head -1)
            if [ -z "$PUBKEY" ] || [ -z "$PRIVKEY" ]; then
                echo "ERROR: No signing keys found"; exit 1
            fi
            cp "$PUBKEY" /etc/apk/keys/

            su build -c "
                PACKAGER_PRIVKEY=$PRIVKEY \\
                PACKAGER_PUBKEY=$PUBKEY \\
                cd /home/build/aports/scripts && ./mkimage.sh \\
                    --profile ${VARIANT} \\
                    --arch x86_64 \\
                    --hostkeys \\
                    --repository https://dl-cdn.alpinelinux.org/alpine/v3.23/main \\
                    --repository https://dl-cdn.alpinelinux.org/alpine/v3.23/community \\
                    --outdir /build/output/${VARIANT}/ \\
                    --tag ${TAG}
            "

            # Build Double Commander from source (musl + Qt5)
            if [ -f /build/build-doublecmd.sh ]; then
                echo "[build] Building Double Commander from source..."
                sh /build/build-doublecmd.sh
            fi

            # Inject heavy binaries into modloop (Chrome, glibc, zapt, etc.)
            if [ -f /build/inject-modloop.sh ]; then
                echo "[build] Injecting extras into modloop..."
                sh /build/inject-modloop.sh "/build/output/${VARIANT}" /build
            fi
        '
    log "ISO built at: ${output_dir}/"
}

_native_build() {
    local variant="$1"
    local tag="$2"
    local output_dir="$3"

    if [[ ! -f /etc/alpine-release ]]; then
        log "WARNING: Not running on Alpine. Use --docker for containerized build."
    fi

    log "Installing build dependencies..."
    apk add --no-cache \
        alpine-sdk build-base apk-tools alpine-conf \
        busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools \
        grub-efi grub-bios git go librsvg 2>/dev/null || true

    if ! ls ~/.abuild/build-*.rsa >/dev/null 2>&1; then
        log "Generating signing key..."
        abuild-keygen -a -n
    fi

    if [[ ! -d /root/aports ]]; then
        log "Cloning aports..."
        git clone --depth=1 https://git.alpinelinux.org/aports /root/aports
    fi

    log "Installing ${variant} profile..."
    cp "${APORTS_DIR}/scripts/mkimg.${variant}.sh"   /root/aports/scripts/
    cp "${APORTS_DIR}/scripts/genapkovl-${variant}.sh" /root/aports/scripts/
    chmod +x /root/aports/scripts/genapkovl-${variant}.sh

    if [[ -d "${SCRIPT_DIR}/dotfiles" ]]; then
        ln -sf "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles 2>/dev/null || \
            cp -r "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles
    fi

    if [[ -d "${SCRIPT_DIR}/zapt" ]]; then
        ln -sf "${SCRIPT_DIR}/zapt" /root/aports/scripts/zapt 2>/dev/null || \
            cp -r "${SCRIPT_DIR}/zapt" /root/aports/scripts/zapt
    fi


    if [[ "$SETUP_ONLY" == true ]]; then
        log "Setup complete. Build manually with:"
        log "  cd /root/aports/scripts && PACKAGER_PRIVKEY=~/.abuild/build-*.rsa ./mkimage.sh --profile ${variant} --arch x86_64 --hostkeys --outdir ~/iso/ --tag ${tag}"
        return 0
    fi

    log "Building ${variant} ISO..."
    mkdir -p "$output_dir"

    PUBKEY=$(find ~/.abuild -name "build-*.rsa.pub" -type f 2>/dev/null | head -1)
    PRIVKEY=$(find ~/.abuild -name "build-*.rsa" -type f 2>/dev/null | head -1)
    if [ -z "$PUBKEY" ] || [ -z "$PRIVKEY" ]; then
        log "ERROR: No signing keys found"; exit 1
    fi
    cp "$PUBKEY" /etc/apk/keys/
    (
        cd /root/aports/scripts
        PACKAGER_PRIVKEY="$PRIVKEY" \
        PACKAGER_PUBKEY="$PUBKEY" \
        ./mkimage.sh \
            --profile "$variant" \
            --arch x86_64 \
            --hostkeys \
            --repository https://dl-cdn.alpinelinux.org/alpine/v3.23/main \
            --repository https://dl-cdn.alpinelinux.org/alpine/v3.23/community \
            --outdir "$output_dir" \
            --tag "$tag"
    )

    # Inject heavy binaries into modloop (Chrome, glibc, zapt, etc.)
    if [ -f "${SCRIPT_DIR}/inject-modloop.sh" ]; then
        log "Injecting extras into modloop..."
        sh "${SCRIPT_DIR}/inject-modloop.sh" "$output_dir" "$SCRIPT_DIR"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
ISO_OUT="${OUTPUT:-${SCRIPT_DIR}/output}"

if [[ "$VARIANT" == "all" ]]; then
    for v in superlite superlite-install superlite-parted; do
        build_variant "$v" "$TAG" "${ISO_OUT}/${v}"
    done
    log "═══════════════════════════════════════════════"
    log "All ISOs built in: ${ISO_OUT}/"
    log "═══════════════════════════════════════════════"
else
    build_variant "$VARIANT" "$TAG" "${ISO_OUT}/${VARIANT}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
ISO_FILES=$(find "$ISO_OUT" -name "*.iso" -type f 2>/dev/null)
if [[ -n "$ISO_FILES" ]]; then
    log "═══════════════════════════════════════════════"
    while IFS= read -r iso; do
        ISO_SIZE=$(du -sh "$iso" | cut -f1)
        log "  $iso ($ISO_SIZE)"
    done <<< "$ISO_FILES"
    log "Boot: UEFI + Legacy BIOS"
    log "═══════════════════════════════════════════════"
else
    log "ERROR: No ISO found in ${ISO_OUT}/"
    exit 1
fi
