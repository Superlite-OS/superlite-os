#!/usr/bin/env python3
"""
SuperLite OS — System Configuration Module
User setup, locale, network, overlay copy
"""
import subprocess
import os
import shutil


def setup_user(root_mount, username, password, hostname):
    """Create user and set hostname."""
    # Set hostname
    with open(os.path.join(root_mount, "etc", "hostname"), "w") as f:
        f.write(hostname + "\n")

    # Create user
    subprocess.run([
        "chroot", root_mount, "adduser", "-D", "-G", "wheel", username
    ], capture_output=True)

    # Set password
    proc = subprocess.Popen(
        ["chroot", root_mount, "chpasswd"],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    proc.communicate(input=f"{username}:{password}\n".encode())

    # Set root password
    proc = subprocess.Popen(
        ["chroot", root_mount, "chpasswd"],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    proc.communicate(input=f"root:{password}\n".encode())

    # Add user to sudoers
    sudoers_line = f"{username} ALL=(ALL) NOPASSWD: ALL\\n"
    subprocess.run([
        "chroot", root_mount, "sh", "-c",
        f'echo "{sudoers_line}" >> /etc/sudoers'
    ], capture_output=True)

    return True


def generate_fstab(root_mount, partitions, boot_mode):
    """Generate /etc/fstab."""
    fstab_lines = [
        "# /etc/fstab - SuperLite OS",
        "proc  /proc  proc  defaults  0 0",
        "sysfs /sys   sysfs defaults  0 0",
        "tmpfs /tmp   tmpfs defaults,noatime  0 0",
    ]

    # Root partition
    root_uuid = _get_uuid(partitions["root"])
    fstab_lines.append(f"UUID={root_uuid}  /  ext4  defaults,relatime  0 1")

    # EFI partition (UEFI only)
    if boot_mode == "uefi" and "efi" in partitions:
        efi_uuid = _get_uuid(partitions["efi"])
        fstab_lines.append(f"UUID={efi_uuid}  /boot/efi  vfat  defaults,noatime  0 2")

    # Swap
    if "swap" in partitions:
        swap_uuid = _get_uuid(partitions["swap"])
        fstab_lines.append(f"UUID={swap_uuid}  none  swap  sw  0 0")

    fstab_path = os.path.join(root_mount, "etc", "fstab")
    with open(fstab_path, "w") as f:
        f.write("\n".join(fstab_lines) + "\n")

    return True


def copy_overlay(root_mount, source_dirs=None):
    """Copy live system overlay to installed system."""
    if source_dirs is None:
        source_dirs = ["/etc/skel", "/root"]

    for src in source_dirs:
        if os.path.isdir(src):
            for item in os.listdir(src):
                if item in (".", ".."):
                    continue
                src_path = os.path.join(src, item)
                dst_path = os.path.join(root_mount, "root", item)
                if os.path.isdir(src_path):
                    shutil.copytree(src_path, dst_path, dirs_exist_ok=True)
                else:
                    shutil.copy2(src_path, dst_path)

    # Copy MOTD
    motd_src = "/etc/motd"
    if os.path.isfile(motd_src):
        shutil.copy2(motd_src, os.path.join(root_mount, "etc", "motd"))

    return True


def setup_network(root_mount, hostname):
    """Configure basic networking."""
    hosts_content = f"""127.0.0.1  localhost {hostname}
::1        localhost ip6-localhost ip6-loopback
"""
    with open(os.path.join(root_mount, "etc", "hosts"), "w") as f:
        f.write(hosts_content)

    # Enable NetworkManager
    subprocess.run([
        "chroot", root_mount, "rc-update", "add", "NetworkManager", "default"
    ], capture_output=True)

    return True


def setup_bootloader_config(root_mount, boot_mode):
    """Configure bootloader-related settings."""
    if boot_mode == "uefi":
        # Ensure EFI mount point exists
        os.makedirs(os.path.join(root_mount, "boot", "efi"), exist_ok=True)


def _get_uuid(device):
    """Get UUID of a block device."""
    try:
        out = subprocess.check_output(
            ["blkid", "-s", "UUID", "-o", "value", device],
            stderr=subprocess.DEVNULL
        )
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return "unknown"
