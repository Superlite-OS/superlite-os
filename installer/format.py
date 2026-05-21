#!/usr/bin/env python3
"""
SuperLite OS — Filesystem Formatting Module
"""
import subprocess


def format_efi(partition):
    """Format partition as FAT32 for EFI system partition."""
    result = subprocess.run(
        ["mkfs.fat", "-F32", partition],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"mkfs.fat failed: {result.stderr}")


def format_swap(partition):
    """Format partition as swap."""
    result = subprocess.run(
        ["mkswap", partition],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"mkswap failed: {result.stderr}")


def format_ext4(partition, label=""):
    """Format partition as ext4."""
    cmd = ["mkfs.ext4", "-F"]
    if label:
        cmd += ["-L", label]
    cmd.append(partition)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"mkfs.ext4 failed: {result.stderr}")


def format_btrfs(partition, label=""):
    """Format partition as btrfs."""
    cmd = ["mkfs.btrfs", "-f"]
    if label:
        cmd += ["-L", label]
    cmd.append(partition)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"mkfs.btrfs failed: {result.stderr}")


def format_xfs(partition, label=""):
    """Format partition as XFS."""
    cmd = ["mkfs.xfs", "-f"]
    if label:
        cmd += ["-L", label]
    cmd.append(partition)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"mkfs.xfs failed: {result.stderr}")


def enable_swap(partition):
    """Enable swap on partition."""
    result = subprocess.run(
        ["swapon", partition],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"swapon failed: {result.stderr}")


def mount_partition(partition, mountpoint, options=""):
    """Mount partition to mountpoint."""
    subprocess.run(["mkdir", "-p", mountpoint], check=True)
    cmd = ["mount"]
    if options:
        cmd += ["-o", options]
    cmd += [partition, mountpoint]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"mount failed: {result.stderr}")


def umount_all(mountpoint):
    """Unmount all filesystems under mountpoint."""
    subprocess.run(["umount", "-R", mountpoint], capture_output=True)


FORMATTERS = {
    "ext4": format_ext4,
    "btrfs": format_btrfs,
    "xfs": format_xfs,
    "fat32": format_efi,
    "swap": format_swap,
}
