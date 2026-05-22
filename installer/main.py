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
    partition_disk_auto, partition_disk_mbr, read_partitions,
    apply_partition_table, get_free_space_mb,
    GPT_EFI, GPT_SWAP, GPT_LINUX, GPT_BIOS_GRUB,
    MBR_SWAP, MBR_LINUX,
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
    manual_partition_menu, add_partition_dialog,
    user_setup, show_error, show_success, confirm_reboot
)


MOUNT_ROOT = "/mnt"


def _setup_local_repo():
    """Setup local APK repo from USB drive for offline install."""
    import glob

    # Find USB drive with bundled packages
    usb_paths = glob.glob("/media/*/apks/x86_64")
    if not usb_paths:
        print("[installer] No local packages found, using network")
        return

    usb_apks = usb_paths[0]
    count = len(glob.glob(f"{usb_apks}/*.apk"))
    print(f"[installer] Found {count} local packages at {usb_apks}")

    # Symlink /media/cdrom/apks to USB packages
    cdrom_apks = "/media/cdrom/apks"
    if os.path.isdir(cdrom_apks) and not os.path.islink(cdrom_apks):
        os.rmdir(cdrom_apks)
        os.symlink(os.path.dirname(usb_apks), cdrom_apks)
        print(f"[installer] Linked {cdrom_apks} -> {os.path.dirname(usb_apks)}")
    elif not os.path.exists(cdrom_apks):
        os.makedirs(os.path.dirname(cdrom_apks), exist_ok=True)
        os.symlink(os.path.dirname(usb_apks), cdrom_apks)
        print(f"[installer] Created {cdrom_apks} -> {os.path.dirname(usb_apks)}")

    # Disable network repos — use only local packages
    with open("/etc/apk/repositories", "w") as f:
        f.write("/media/cdrom/apks\n")
    print("[installer] Disabled network repos, using local only")


def _do_manual_partition(device, boot_mode):
    """Tofi-based manual partitioning loop.

    Returns partition dict {role: path} or None if cancelled.
    """
    label = "gpt" if boot_mode == "uefi" else "dos"
    part_list = []  # [{size_mb, type_uuid}]

    while True:
        # Show current state
        existing = read_partitions(device)
        free = get_free_space_mb(device)

        action = manual_partition_menu(device, existing)
        if action == "cancel":
            return None

        if action == "apply":
            if not part_list:
                show_error("No partitions defined! Add at least one.")
                continue
            break

        if action == "add":
            dialog = add_partition_dialog(free, boot_mode)
            if not dialog:
                continue
            size_mb = dialog["size_mb"]
            type_name = dialog["type"]

            # Map type name to UUID
            if label == "gpt":
                type_map = {
                    "Linux filesystem": GPT_LINUX,
                    "EFI System Partition": GPT_EFI,
                    "Linux swap": GPT_SWAP,
                    "BIOS boot (1MB)": GPT_BIOS_GRUB,
                }
            else:
                type_map = {
                    "Linux filesystem": MBR_LINUX,
                    "Linux swap": MBR_SWAP,
                }

            type_uuid = type_map.get(type_name, GPT_LINUX if label == "gpt" else MBR_LINUX)
            part_list.append({"size_mb": size_mb, "type_uuid": type_uuid})
            print(f"[installer] Added partition: {size_mb}MB type={type_name}")

        if isinstance(action, dict) and action.get("action") == "remove":
            num = action["num"]
            # Remove from part_list by index (partition numbers are 1-based)
            idx = num - 1
            if 0 <= idx < len(part_list):
                removed = part_list.pop(idx)
                print(f"[installer] Removed partition {num}: {removed['size_mb']}MB")

    # Apply partition table
    try:
        result_map = apply_partition_table(device, label, part_list)
    except Exception as e:
        show_error(f"Failed to apply partitions:\n{e}")
        return None

    # Map partitions to roles based on type
    sep = "p" if any(x in device for x in ["nvme", "mmcblk", "md"]) else ""
    partitions = {}
    for i, part in enumerate(part_list):
        path = f"{device}{sep}{i + 1}"
        ptype = part["type_uuid"]
        if ptype == GPT_EFI:
            partitions["efi"] = path
        elif ptype in (GPT_SWAP, MBR_SWAP):
            partitions["swap"] = path
        elif ptype == GPT_BIOS_GRUB:
            partitions["bios_grub"] = path
        else:
            partitions["root"] = path

    if "root" not in partitions:
        show_error("No root partition defined!\nYou need at least one Linux filesystem partition.")
        return None

    return partitions


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
            partitions = _do_manual_partition(device, boot_mode)
            if not partitions:
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
        # Setup local repo from USB if available (offline install)
        _setup_local_repo()

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
