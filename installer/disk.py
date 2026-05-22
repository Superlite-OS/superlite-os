#!/usr/bin/env python3
"""
SuperLite OS — Disk Management Module
Device detection, partitioning via parted/sfdisk
"""
import json
import subprocess
import os
import glob


def detect_boot_mode():
    """Detect if system booted via UEFI or BIOS."""
    if os.path.isdir("/sys/firmware/efi"):
        return "uefi"
    return "bios"


def get_block_devices():
    """List block devices using lsblk JSON output."""
    try:
        out = subprocess.check_output(
            ["lsblk", "-J", "-o", "NAME,SIZE,MODEL,TYPE,ROTA,TRAN,MOUNTPOINT"],
            stderr=subprocess.DEVNULL
        )
        data = json.loads(out)
        devices = []
        for dev in data.get("blockdevices", []):
            if dev.get("type") == "disk":
                devices.append({
                    "name": dev["name"],
                    "path": f"/dev/{dev['name']}",
                    "size": dev.get("size", "?"),
                    "model": dev.get("model", "Unknown"),
                    "rota": dev.get("rota", "1"),
                    "tran": dev.get("tran", ""),
                    "mountpoint": dev.get("mountpoint"),
                    "children": _parse_partitions(dev.get("children", []))
                })
        return devices
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []


def _parse_partitions(children):
    """Parse partition list from lsblk children."""
    parts = []
    for child in children:
        if child.get("type") == "part":
            parts.append({
                "name": child["name"],
                "path": f"/dev/{child['name']}",
                "size": child.get("size", "?"),
                "mountpoint": child.get("mountpoint"),
            })
    return parts


def _unmount_disk(device):
    """Unmount all partitions and disable swap on device."""
    dev_name = os.path.basename(device)
    try:
        out = subprocess.check_output(
            ["lsblk", "-n", "-o", "NAME", device],
            stderr=subprocess.DEVNULL, text=True
        )
        for line in out.strip().splitlines():
            part = line.strip()
            if not part or part == dev_name:
                continue
            part_path = f"/dev/{part}"
            subprocess.run(["swapoff", part_path],
                           capture_output=True, stderr=subprocess.DEVNULL)
            subprocess.run(["umount", "-f", part_path],
                           capture_output=True, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def get_disk_size_mb(device):
    """Get disk size in MB."""
    try:
        out = subprocess.check_output(
            ["blockdev", "--getsize64", device],
            stderr=subprocess.DEVNULL
        )
        return int(out.strip()) // (1024 * 1024)
    except (subprocess.CalledProcessError, ValueError):
        return 0


def partition_disk_auto(device, boot_mode):
    """Auto-partition disk based on boot mode.

    UEFI (GPT): EFI(512MB) + swap(2GB/10%) + root(rest)
    BIOS  (GPT): bios_grub(1MB) + swap(2GB/10%) + root(rest)

    Returns dict with partition info.
    """
    size_mb = get_disk_size_mb(device)
    if size_mb < 4096:
        raise ValueError(f"Disk too small: {size_mb}MB (need at least 4GB)")

    # Unmount all partitions and disable swap before wiping
    _unmount_disk(device)

    # Wipe existing partition table
    subprocess.run(["wipefs", "-a", device], capture_output=True)
    subprocess.run(["sgdisk", "--zap-all", device], capture_output=True)

    if boot_mode == "uefi":
        return _partition_gpt_efi(device, size_mb)
    else:
        return _partition_gpt_bios(device, size_mb)


def _partition_gpt_efi(device, size_mb):
    """GPT partitioning for UEFI: EFI + swap + root."""
    swap_mb = min(size_mb // 10, 2048)
    efi_mb = 512

    # Use sfdisk for GPT partitioning (scripted)
    # Must use full GPT type UUIDs — sfdisk on Alpine doesn't support aliases
    script = (
        f"label: gpt\n"
        f"size={efi_mb}MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n"
        f"size={swap_mb}MiB, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F\n"
        f"type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n"
    )

    result = subprocess.run(
        ["sfdisk", device],
        input=script, text=True, capture_output=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"sfdisk failed: {result.stderr}")

    # Detect partition naming (nvme uses p separator)
    sep = "p" if any(x in device for x in ["nvme", "mmcblk", "md"]) else ""
    parts = {
        "efi": f"{device}{sep}1",
        "swap": f"{device}{sep}2",
        "root": f"{device}{sep}3",
    }

    # Set ESP flag on EFI partition
    subprocess.run(
        ["sfdisk", "--part-attrs", device, "1", "RequiredPartition"],
        capture_output=True
    )

    return parts


def _partition_gpt_bios(device, size_mb):
    """GPT partitioning for BIOS: bios_grub + swap + root."""
    swap_mb = min(size_mb // 10, 2048)
    bios_mb = 1

    # Must use full GPT type UUIDs — sfdisk on Alpine doesn't support aliases
    script = (
        f"label: gpt\n"
        f"size={bios_mb}MiB, type=21686148-6449-6E6F-744E-656564454649\n"
        f"size={swap_mb}MiB, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F\n"
        f"type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n"
    )

    result = subprocess.run(
        ["sfdisk", device],
        input=script, text=True, capture_output=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"sfdisk failed: {result.stderr}")

    sep = "p" if any(x in device for x in ["nvme", "mmcblk", "md"]) else ""
    parts = {
        "bios_grub": f"{device}{sep}1",
        "swap": f"{device}{sep}2",
        "root": f"{device}{sep}3",
    }

    return parts


def partition_disk_mbr(device):
    """MBR partitioning: primary + swap + root."""
    size_mb = get_disk_size_mb(device)
    swap_mb = min(size_mb // 10, 2048)

    _unmount_disk(device)
    subprocess.run(["wipefs", "-a", device], capture_output=True)

    script = (
        f"label: dos\n"
        f"size={swap_mb}MiB, type=82\n"
        f"type=83\n"
    )

    result = subprocess.run(
        ["sfdisk", device],
        input=script, text=True, capture_output=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"sfdisk failed: {result.stderr}")

    sep = "p" if any(x in device for x in ["nvme", "mmcblk", "md"]) else ""
    return {
        "swap": f"{device}{sep}1",
        "root": f"{device}{sep}2",
    }


def launch_cfdisk(device):
    """Launch cfdisk for manual partitioning."""
    subprocess.run(["cfdisk", device])
