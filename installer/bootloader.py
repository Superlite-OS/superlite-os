#!/usr/bin/env python3
"""
SuperLite OS — Bootloader Installation Module
GRUB installation for BIOS and UEFI
"""
import subprocess
import os


def install_grub_uefi(root_mount, efi_mount, device):
    """Install GRUB for UEFI boot."""
    # Ensure EFI directory exists
    efi_dir = os.path.join(root_mount, "boot", "efi")
    os.makedirs(efi_dir, exist_ok=True)

    # Mount EFI partition
    result = subprocess.run(
        ["mount", efi_mount, efi_dir],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"Mount EFI failed: {result.stderr}")

    # Install GRUB EFI
    result = subprocess.run([
        "grub-install",
        "--target=x86_64-efi",
        f"--efi-directory={efi_dir}",
        "--bootloader-id=superlite",
        "--recheck"
    ], capture_output=True, text=True, chroot=root_mount)
    if result.returncode != 0:
        # Try without chroot
        result = subprocess.run([
            "grub-install",
            "--target=x86_64-efi",
            f"--efi-directory={efi_dir}",
            "--bootloader-id=superlite",
            "--recheck"
        ], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"grub-install EFI failed: {result.stderr}")

    # Generate grub.cfg
    _generate_grub_cfg(root_mount)

    return True


def install_grub_bios(root_mount, device):
    """Install GRUB for BIOS boot (GPT with bios_grub partition)."""
    # Install GRUB BIOS
    result = subprocess.run([
        "grub-install",
        "--target=i386-pc",
        f"--boot-directory={root_mount}/boot",
        device,
        "--recheck"
    ], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"grub-install BIOS failed: {result.stderr}")

    # Generate grub.cfg
    _generate_grub_cfg(root_mount)

    return True


def _generate_grub_cfg(root_mount):
    """Generate GRUB configuration."""
    grub_dir = os.path.join(root_mount, "boot", "grub")
    os.makedirs(grub_dir, exist_ok=True)

    cfg_path = os.path.join(grub_dir, "grub.cfg")
    with open(cfg_path, "w") as f:
        f.write(_GRUB_CFG_TEMPLATE)


def detect_os_entries(root_mount):
    """Detect installed kernels for GRUB entries."""
    boot_dir = os.path.join(root_mount, "boot")
    kernels = []
    if os.path.isdir(boot_dir):
        for f in os.listdir(boot_dir):
            if f.startswith("vmlinuz-"):
                version = f.replace("vmlinuz-", "")
                kernels.append(version)
    return sorted(kernels, reverse=True)


_GRUB_CFG_TEMPLATE = """\
set default=0
set timeout=5
set gfxmode=auto

insmod all_video
insmod gfxterm

terminal_output gfxterm

menuentry "SuperLite OS" {
    linux /boot/vmlinuz-lts root=UUID=__ROOT_UUID__ ro quiet
    initrd /boot/initramfs-lts
}

menuentry "SuperLite OS (recovery)" {
    linux /boot/vmlinuz-lts root=UUID=__ROOT_UUID__ ro single
    initrd /boot/initramfs-lts
}
"""
