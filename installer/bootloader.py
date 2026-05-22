#!/usr/bin/env python3
"""
SuperLite OS — Bootloader Installation Module
Copy prebuilt bootloader from USB to target disk
"""
import subprocess
import os
import shutil
import glob


def _find_usb():
    """Find USB mount path."""
    paths = glob.glob("/media/sdb*") + glob.glob("/media/usb*")
    for p in paths:
        if os.path.isdir(os.path.join(p, "boot")):
            return p
    return None


def install_grub_uefi(root_mount, efi_part, device):
    """Install bootloader for UEFI — copy prebuilt from USB."""
    usb = _find_usb()
    if not usb:
        raise RuntimeError("USB drive not found")

    # Mount EFI partition
    efi_dir = os.path.join(root_mount, "boot", "efi")
    os.makedirs(efi_dir, exist_ok=True)
    subprocess.run(["mount", efi_part, efi_dir], capture_output=True)

    # Copy EFI bootloader
    src_efi = os.path.join(usb, "efi", "boot", "bootx64.efi")
    dst_efi_dir = os.path.join(efi_dir, "EFI", "boot")
    os.makedirs(dst_efi_dir, exist_ok=True)
    shutil.copy2(src_efi, os.path.join(dst_efi_dir, "bootx64.efi"))
    print(f"[bootloader] Copied EFI bootloader")

    # Copy kernel + initramfs to /boot
    boot_dir = os.path.join(root_mount, "boot")
    os.makedirs(boot_dir, exist_ok=True)
    for f in ["vmlinuz-lts", "initramfs-lts"]:
        src = os.path.join(usb, "boot", f)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(boot_dir, f))
            print(f"[bootloader] Copied {f}")

    # Copy modloop
    src_mod = os.path.join(usb, "boot", "modloop-lts")
    if os.path.exists(src_mod):
        shutil.copy2(src_mod, os.path.join(boot_dir, "modloop-lts"))

    # Generate grub.cfg with correct root UUID
    _generate_grub_cfg(root_mount)

    return True


def install_grub_bios(root_mount, device):
    """Install bootloader for BIOS — copy prebuilt from USB."""
    usb = _find_usb()
    if not usb:
        raise RuntimeError("USB drive not found")

    # Copy kernel + initramfs
    boot_dir = os.path.join(root_mount, "boot")
    os.makedirs(boot_dir, exist_ok=True)
    for f in ["vmlinuz-lts", "initramfs-lts"]:
        src = os.path.join(usb, "boot", f)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(boot_dir, f))
            print(f"[bootloader] Copied {f}")

    # Copy modloop
    src_mod = os.path.join(usb, "boot", "modloop-lts")
    if os.path.exists(src_mod):
        shutil.copy2(src_mod, os.path.join(boot_dir, "modloop-lts"))

    # Install syslinux/extlinux MBR
    mbr_bin = os.path.join(usb, "boot", "syslinux", "mbr.bin")
    if os.path.exists(mbr_bin):
        subprocess.run(["dd", f"if={mbr_bin}", f"of={device}", "bs=440", "count=1"],
                       capture_output=True)
        print(f"[bootloader] Wrote MBR")

    # Install extlinux
    syslinux_dir = os.path.join(boot_dir, "syslinux")
    os.makedirs(syslinux_dir, exist_ok=True)

    # Copy syslinux files from USB
    src_syslinux = os.path.join(usb, "boot", "syslinux")
    if os.path.isdir(src_syslinux):
        for f in os.listdir(src_syslinux):
            src = os.path.join(src_syslinux, f)
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(syslinux_dir, f))

    # Generate syslinux.cfg
    _generate_syslinux_cfg(root_mount)

    # Run extlinux --install
    result = subprocess.run(
        ["extlinux", "--install", syslinux_dir],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"[bootloader] extlinux warning: {result.stderr[:200]}")

    return True


def _get_root_uuid(root_mount):
    """Get UUID of root partition."""
    # Find what's mounted at root_mount
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


def _generate_grub_cfg(root_mount):
    """Generate grub.cfg with correct root UUID."""
    uuid = _get_root_uuid(root_mount)
    grub_dir = os.path.join(root_mount, "boot", "grub")
    os.makedirs(grub_dir, exist_ok=True)

    cfg = f"""set default=0
set timeout=5
set gfxmode=auto

insmod all_video
insmod gfxterm

terminal_output gfxterm

menuentry "SuperLite OS" {{
    linux /boot/vmlinuz-lts root=UUID={uuid} ro quiet
    initrd /boot/initramfs-lts
}}

menuentry "SuperLite OS (recovery)" {{
    linux /boot/vmlinuz-lts root=UUID={uuid} ro single
    initrd /boot/initramfs-lts
}}
"""
    with open(os.path.join(grub_dir, "grub.cfg"), "w") as f:
        f.write(cfg)
    print(f"[bootloader] Generated grub.cfg (root=UUID={uuid})")


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
