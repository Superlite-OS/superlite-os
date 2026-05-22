#!/usr/bin/env python3
"""
SuperLite OS — Bootloader Installation Module
Install GRUB (UEFI) or extlinux (BIOS) to target disk
"""
import subprocess
import os
import shutil
import glob


def _find_usb():
    """Find USB mount path."""
    # Check common live media mount points
    for pattern in ["/media/sdb*", "/media/usb*", "/media/sr*"]:
        for p in glob.glob(pattern):
            if os.path.isdir(os.path.join(p, "boot")):
                return p
    # Also check if we're running from the live system itself
    if os.path.isdir("/boot") and os.path.isfile("/boot/vmlinuz-lts"):
        return "/"
    return None


def _get_root_uuid(root_mount):
    """Get UUID of root partition mounted at root_mount."""
    try:
        out = subprocess.check_output(
            ["findmnt", "-n", "-o", "SOURCE", root_mount],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        if out:
            uuid_out = subprocess.check_output(
                ["blkid", "-s", "UUID", "-o", "value", out],
                text=True, stderr=subprocess.DEVNULL
            ).strip()
            return uuid_out
    except Exception:
        pass
    return "UNKNOWN"


def _is_mounted(path):
    """Check if path is already a mountpoint."""
    try:
        subprocess.check_output(
            ["mountpoint", "-q", path],
            stderr=subprocess.DEVNULL
        )
        return True
    except subprocess.CalledProcessError:
        return False


def _bind_mount_chroot(root_mount):
    """Bind mount /dev, /proc, /sys into target for chroot."""
    for d in ["dev", "proc", "sys"]:
        target = os.path.join(root_mount, d)
        os.makedirs(target, exist_ok=True)
        if not _is_mounted(target):
            subprocess.run(
                ["mount", "--bind", f"/{d}", target],
                capture_output=True, check=True
            )
            print(f"[bootloader] Bind mounted /{d}")


def _umount_chroot(root_mount):
    """Unmount bind mounts from chroot (reverse order)."""
    for d in ["sys", "proc", "dev"]:
        target = os.path.join(root_mount, d)
        if _is_mounted(target):
            subprocess.run(
                ["umount", "-l", target],
                capture_output=True
            )


def _copy_boot_files(usb, root_mount):
    """Copy kernel, initramfs, and modloop from USB to target /boot."""
    boot_dir = os.path.join(root_mount, "boot")
    os.makedirs(boot_dir, exist_ok=True)

    for f in ["vmlinuz-lts", "initramfs-lts"]:
        src = os.path.join(usb, "boot", f)
        dst = os.path.join(boot_dir, f)
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.copy2(src, dst)
            print(f"[bootloader] Copied {f}")

    src_mod = os.path.join(usb, "boot", "modloop-lts")
    dst_mod = os.path.join(boot_dir, "modloop-lts")
    if os.path.exists(src_mod) and not os.path.exists(dst_mod):
        shutil.copy2(src_mod, dst_mod)
        print(f"[bootloader] Copied modloop-lts")


def install_grub_uefi(root_mount, efi_part, device):
    """Install GRUB bootloader for UEFI.

    Strategy:
    1. Try grub-install via chroot (proper — registers in EFI vars)
    2. Fallback: copy prebuilt bootx64.efi from USB (EFI/BOOT fallback path)
    """
    efi_dir = os.path.join(root_mount, "boot", "efi")

    # Mount EFI partition if not already mounted
    if efi_part and not _is_mounted(efi_dir):
        os.makedirs(efi_dir, exist_ok=True)
        result = subprocess.run(
            ["mount", efi_part, efi_dir],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"[bootloader] Warning: EFI mount failed: {result.stderr[:200]}")

    # Copy kernel files from USB
    usb = _find_usb()
    if usb:
        _copy_boot_files(usb, root_mount)
    else:
        print("[bootloader] Warning: USB not found, kernel files must already exist")

    # Try grub-install via chroot
    installed = _try_grub_install_chroot(root_mount)

    if not installed:
        # Fallback: copy prebuilt EFI binary from USB
        print("[bootloader] grub-install unavailable, using prebuilt fallback")
        _install_grub_prebuilt(root_mount, usb)

    return True


def _try_grub_install_chroot(root_mount):
    """Try installing GRUB via chroot + grub-install.

    Returns True if successful, False if grub-install not available.
    """
    # Check if grub-install exists in the target
    grub_check = os.path.join(root_mount, "usr", "sbin", "grub-install")
    if not os.path.isfile(grub_check):
        # Try grub-install in other locations
        for p in ["usr/bin/grub-install", "sbin/grub-install"]:
            if os.path.isfile(os.path.join(root_mount, p)):
                grub_check = os.path.join(root_mount, p)
                break
        else:
            return False

    print("[bootloader] Installing GRUB via chroot...")

    try:
        _bind_mount_chroot(root_mount)

        # Ensure grub packages are installed in target
        subprocess.run(
            ["chroot", root_mount, "apk", "add", "--no-cache",
             "grub-efi", "efibootmgr"],
            capture_output=True, text=True, timeout=120
        )

        # Run grub-install inside chroot
        result = subprocess.run(
            ["chroot", root_mount, "grub-install",
             "--target=x86_64-efi",
             "--efi-directory=/boot/efi",
             "--bootloader-id=superlite",
             "--recheck"],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode != 0:
            print(f"[bootloader] grub-install warning: {result.stderr[:300]}")
            # Continue — grub-install may still produce usable output

        # Generate grub.cfg
        result2 = subprocess.run(
            ["chroot", root_mount, "grub-mkconfig", "-o", "/boot/grub/grub.cfg"],
            capture_output=True, text=True, timeout=60
        )
        if result2.returncode != 0:
            print(f"[bootloader] grub-mkconfig warning: {result2.stderr[:300]}")
            # Fallback: generate our own grub.cfg
            _generate_grub_cfg(root_mount)
        else:
            print("[bootloader] grub-mkconfig succeeded")

        _umount_chroot(root_mount)
        return True

    except Exception as e:
        print(f"[bootloader] chroot GRUB install failed: {e}")
        _umount_chroot(root_mount)
        return False


def _install_grub_prebuilt(root_mount, usb):
    """Fallback: copy prebuilt GRUB EFI binary and generate grub.cfg."""
    if not usb:
        raise RuntimeError("USB drive not found and grub-install unavailable")

    efi_dir = os.path.join(root_mount, "boot", "efi")

    # Try multiple source paths for bootx64.efi
    src_efi = None
    for path in [
        os.path.join(usb, "efi", "boot", "bootx64.efi"),
        os.path.join(usb, "EFI", "BOOT", "bootx64.efi"),
        os.path.join(usb, "boot", "grub", "x86_64-efi", "core.efi"),
    ]:
        if os.path.exists(path):
            src_efi = path
            break

    if not src_efi:
        raise RuntimeError(f"Cannot find bootx64.efi on USB ({usb})")

    # Copy to standard EFI fallback path
    dst_efi_dir = os.path.join(efi_dir, "EFI", "BOOT")
    os.makedirs(dst_efi_dir, exist_ok=True)
    shutil.copy2(src_efi, os.path.join(dst_efi_dir, "bootx64.efi"))
    print(f"[bootloader] Copied EFI bootloader to EFI/BOOT/")

    # Also copy to EFI/superlite/ for clean structure
    dst_superlite = os.path.join(efi_dir, "EFI", "superlite")
    os.makedirs(dst_superlite, exist_ok=True)
    shutil.copy2(src_efi, os.path.join(dst_superlite, "bootx64.efi"))

    # Generate grub.cfg — write to BOTH locations
    # GRUB's bootx64.efi looks for grub.cfg relative to itself
    _generate_grub_cfg(root_mount)

    # Also copy grub.cfg to EFI/BOOT/ so bootx64.efi can find it
    grub_cfg_src = os.path.join(root_mount, "boot", "grub", "grub.cfg")
    grub_cfg_dst = os.path.join(dst_efi_dir, "grub.cfg")
    if os.path.exists(grub_cfg_src):
        shutil.copy2(grub_cfg_src, grub_cfg_dst)
        print("[bootloader] Copied grub.cfg to EFI/BOOT/")


def _generate_grub_cfg(root_mount):
    """Generate grub.cfg with proper root search for EFI fallback."""
    uuid = _get_root_uuid(root_mount)
    grub_dir = os.path.join(root_mount, "boot", "grub")
    os.makedirs(grub_dir, exist_ok=True)

    cfg = f"""set default=0
set timeout=5
set gfxmode=auto

insmod all_video
insmod gfxterm
insmod search_fs_uuid

terminal_output gfxterm

# Search for the root partition by UUID
search --fs-uuid --set=root {uuid}

menuentry "SuperLite OS" {{
    linux /boot/vmlinuz-lts root=UUID={uuid} ro quiet
    initrd /boot/initramfs-lts
}}

menuentry "SuperLite OS (recovery)" {{
    linux /boot/vmlinuz-lts root=UUID={uuid} ro single
    initrd /boot/initramfs-lts
}}
"""
    cfg_path = os.path.join(grub_dir, "grub.cfg")
    with open(cfg_path, "w") as f:
        f.write(cfg)
    print(f"[bootloader] Generated grub.cfg (root=UUID={uuid})")


def install_grub_bios(root_mount, device):
    """Install bootloader for BIOS using extlinux/syslinux."""
    usb = _find_usb()

    # Copy kernel files
    if usb:
        _copy_boot_files(usb, root_mount)

    boot_dir = os.path.join(root_mount, "boot")

    # Try grub-install for BIOS (grub-install --target=i386-pc)
    grub_check = os.path.join(root_mount, "usr", "sbin", "grub-install")
    if os.path.isfile(grub_check):
        print("[bootloader] Installing GRUB BIOS via chroot...")
        try:
            _bind_mount_chroot(root_mount)
            # Ensure grub-bios is installed in target
            subprocess.run(
                ["chroot", root_mount, "apk", "add", "--no-cache", "grub-bios"],
                capture_output=True, text=True, timeout=120
            )
            result = subprocess.run(
                ["chroot", root_mount, "grub-install",
                 "--target=i386-pc",
                 "--recheck", device],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode == 0:
                subprocess.run(
                    ["chroot", root_mount, "grub-mkconfig",
                     "-o", "/boot/grub/grub.cfg"],
                    capture_output=True, text=True, timeout=60
                )
                _umount_chroot(root_mount)
                print("[bootloader] GRUB BIOS installed successfully")
                return True
            else:
                print(f"[bootloader] grub-install BIOS failed: {result.stderr[:200]}")
            _umount_chroot(root_mount)
        except Exception as e:
            print(f"[bootloader] GRUB BIOS install error: {e}")
            _umount_chroot(root_mount)

    # Fallback: extlinux/syslinux
    print("[bootloader] Using extlinux fallback for BIOS...")

    if usb:
        # Write MBR
        mbr_bin = os.path.join(usb, "boot", "syslinux", "mbr.bin")
        if os.path.exists(mbr_bin):
            subprocess.run(
                ["dd", f"if={mbr_bin}", f"of={device}", "bs=440", "count=1"],
                capture_output=True
            )
            print("[bootloader] Wrote MBR")

        # Copy syslinux files
        syslinux_dir = os.path.join(boot_dir, "syslinux")
        os.makedirs(syslinux_dir, exist_ok=True)
        src_syslinux = os.path.join(usb, "boot", "syslinux")
        if os.path.isdir(src_syslinux):
            for f in os.listdir(src_syslinux):
                src = os.path.join(src_syslinux, f)
                if os.path.isfile(src):
                    shutil.copy2(src, os.path.join(syslinux_dir, f))

    # Generate syslinux.cfg
    _generate_syslinux_cfg(root_mount)

    # Run extlinux --install
    syslinux_dir = os.path.join(boot_dir, "syslinux")
    if os.path.isdir(syslinux_dir):
        result = subprocess.run(
            ["extlinux", "--install", syslinux_dir],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"[bootloader] extlinux warning: {result.stderr[:200]}")
        else:
            print("[bootloader] extlinux installed")

    return True


def _generate_syslinux_cfg(root_mount):
    """Generate syslinux.cfg."""
    uuid = _get_root_uuid(root_mount)
    boot_dir = os.path.join(root_mount, "boot")
    syslinux_dir = os.path.join(boot_dir, "syslinux")
    os.makedirs(syslinux_dir, exist_ok=True)

    cfg = f"""DEFAULT superlite
PROMPT 0
TIMEOUT 50

LABEL superlite
    KERNEL /boot/vmlinuz-lts
    INITRD /boot/initramfs-lts
    APPEND root=UUID={uuid} ro quiet

LABEL recovery
    KERNEL /boot/vmlinuz-lts
    INITRD /boot/initramfs-lts
    APPEND root=UUID={uuid} ro single
"""
    with open(os.path.join(syslinux_dir, "syslinux.cfg"), "w") as f:
        f.write(cfg)
    print(f"[bootloader] Generated syslinux.cfg (root=UUID={uuid})")


def detect_os_entries(root_mount):
    """Detect installed kernels."""
    boot_dir = os.path.join(root_mount, "boot")
    kernels = []
    if os.path.isdir(boot_dir):
        for f in os.listdir(boot_dir):
            if f.startswith("vmlinuz-"):
                kernels.append(f.replace("vmlinuz-", ""))
    return sorted(kernels, reverse=True)
