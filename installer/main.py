#!/usr/bin/env python3
"""
SuperLite OS — Main Installer
Wizard flow: disk → partition → format → install → bootloader
"""
import sys
import os
import subprocess
import traceback

from disk import (
    detect_boot_mode, get_block_devices, get_disk_size_mb,
    partition_disk_auto, partition_disk_mbr, launch_cfdisk
)
from format import (
    format_efi, format_swap, format_ext4, enable_swap,
    mount_partition, umount_all
)
from bootloader import install_grub_uefi, install_grub_bios
from system import (
    setup_user, generate_fstab, copy_overlay,
    setup_network, setup_bootloader_config
)
from gui import (
    welcome, select_disk, partition_scheme, confirm_erase,
    user_setup, show_error, show_success, confirm_reboot
)


MOUNT_ROOT = "/mnt"


def main():
    """Main installer wizard."""
    try:
        _run_installer()
    except Exception as e:
        show_error(f"Installation failed:\n{e}\n\n{traceback.format_exc()}")
        sys.exit(1)


def _run_installer():
    """Run the installer wizard steps."""

    # Step 1: Welcome
    if not welcome():
        sys.exit(0)

    # Step 2: Detect boot mode
    boot_mode = detect_boot_mode()
    print(f"[installer] Boot mode: {boot_mode}")

    # Step 3: Select disk
    devices = get_block_devices()
    if not devices:
        show_error("No block devices found!")
        sys.exit(1)

    selected = select_disk(devices)
    if not selected:
        sys.exit(0)

    device = selected["path"]
    print(f"[installer] Selected disk: {device}")

    # Step 4: Partition scheme
    scheme = partition_scheme(boot_mode)
    if not scheme:
        sys.exit(0)

    # Step 5: Confirm erase
    if scheme != "manual":
        if not confirm_erase(device):
            sys.exit(0)

    # Step 6: Partition
    print(f"[installer] Partitioning {device} ({scheme})...")
    try:
        if scheme == "auto":
            partitions = partition_disk_auto(device, boot_mode)
        elif scheme == "mbr":
            partitions = partition_disk_mbr(device)
        elif scheme == "manual":
            launch_cfdisk(device)
            # After manual partitioning, user needs to specify partitions
            # TODO: add dialog for manual partition selection
            show_error("Manual partitioning complete.\nPlease reboot and run installer again.")
            sys.exit(0)
        else:
            show_error(f"Unknown scheme: {scheme}")
            sys.exit(1)
    except Exception as e:
        show_error(f"Partitioning failed:\n{e}")
        sys.exit(1)

    print(f"[installer] Partitions: {partitions}")

    # Step 7: Format
    print("[installer] Formatting partitions...")
    try:
        if "efi" in partitions:
            format_efi(partitions["efi"])
        if "swap" in partitions:
            format_swap(partitions["swap"])
            enable_swap(partitions["swap"])
        format_ext4(partitions["root"], label="superlite")
    except Exception as e:
        show_error(f"Formatting failed:\n{e}")
        sys.exit(1)

    # Step 8: Mount
    print("[installer] Mounting partitions...")
    try:
        umount_all(MOUNT_ROOT)
        mount_partition(partitions["root"], MOUNT_ROOT)
        if boot_mode == "uefi" and "efi" in partitions:
            efi_mount = os.path.join(MOUNT_ROOT, "boot", "efi")
            mount_partition(partitions["efi"], efi_mount)
    except Exception as e:
        show_error(f"Mount failed:\n{e}")
        sys.exit(1)

    # Step 9: User setup
    user_info = user_setup()
    if not user_info:
        umount_all(MOUNT_ROOT)
        sys.exit(0)

    # Step 10: Install system
    print("[installer] Installing Alpine base system...")
    try:
        result = subprocess.run(
            ["setup-disk", "-m", "sys", MOUNT_ROOT],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            show_error(f"setup-disk failed:\n{result.stderr}")
            umount_all(MOUNT_ROOT)
            sys.exit(1)
    except Exception as e:
        show_error(f"System install failed:\n{e}")
        umount_all(MOUNT_ROOT)
        sys.exit(1)

    # Step 11: Configure system
    print("[installer] Configuring system...")
    try:
        setup_user(MOUNT_ROOT, user_info["username"], user_info["password"], user_info["hostname"])
        generate_fstab(MOUNT_ROOT, partitions, boot_mode)
        setup_network(MOUNT_ROOT, user_info["hostname"])
        copy_overlay(MOUNT_ROOT)
        setup_bootloader_config(MOUNT_ROOT, boot_mode)
    except Exception as e:
        show_error(f"Configuration failed:\n{e}")
        umount_all(MOUNT_ROOT)
        sys.exit(1)

    # Step 12: Install bootloader
    print("[installer] Installing bootloader...")
    try:
        if boot_mode == "uefi":
            install_grub_uefi(MOUNT_ROOT, partitions.get("efi"), device)
        else:
            install_grub_bios(MOUNT_ROOT, device)
    except Exception as e:
        show_error(f"Bootloader install failed:\n{e}")
        # Continue anyway - user can fix manually

    # Step 13: Done
    umount_all(MOUNT_ROOT)

    if show_success("You can now reboot into SuperLite OS."):
        if confirm_reboot():
            subprocess.run(["reboot"])


if __name__ == "__main__":
    main()
