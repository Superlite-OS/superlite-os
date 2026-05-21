#!/usr/bin/env python3
"""
SuperLite OS — GUI Dialog Module (yad)
All installer UI dialogs using yad
"""
import subprocess
import os


def _yad(*args, **kwargs):
    """Run yad and return result."""
    cmd = ["yad"] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    return result.stdout.strip(), result.returncode


def welcome():
    """Welcome dialog with language/timezone selection."""
    out, code = _yad(
        "--title=SuperLite OS Installer",
        "--text=<b>Welcome to SuperLite OS</b>\n\nThis installer will guide you through installing SuperLite OS.",
        "--width=500", "--height=300",
        "--button=Next:0", "--button=Cancel:1",
        "--center"
    )
    return code == 0


def select_disk(devices):
    """Select target disk from list.

    Args:
        devices: list of dicts with keys: name, path, size, model
    Returns: selected device dict or None
    """
    if not devices:
        _yad("--error", "--text=No disks found!", "--center")
        return None

    # Build yad list
    cmd = [
        "yad", "--list",
        "--title=Select Disk",
        "--text=<b>Select target disk for installation:</b>\n<i>WARNING: All data will be erased!</i>",
        "--column=Device", "--column=Size", "--column=Model", "--column=Type",
        "--width=600", "--height=400",
        "--center",
        "--button=Select:0", "--button=Cancel:1",
    ]
    for dev in devices:
        dtype = "SSD" if dev.get("rota") == "0" else "HDD"
        if dev.get("tran"):
            dtype += f" ({dev['tran']})"
        cmd += [dev["path"], dev["size"], dev["model"], dtype]

    out, code = _yad(*cmd[1:])  # Skip 'yad' since _yad adds it
    if code != 0:
        return None

    selected_path = out.split("|")[0]
    for dev in devices:
        if dev["path"] == selected_path:
            return dev
    return None


def partition_scheme(boot_mode):
    """Choose partition scheme.

    Returns: "auto", "manual", or None
    """
    out, code = _yad(
        "--title=Partition Scheme",
        "--text=<b>Choose partition scheme:</b>\n\n"
               f"Boot mode detected: <b>{boot_mode.upper()}</b>",
        "--radiolist",
        "--column=Select", "--column=Scheme", "--column=Description",
        "TRUE", "Auto (Recommended)",
        f"GPT: {'EFI + swap + root' if boot_mode == 'uefi' else 'bios_grub + swap + root'}",
        "FALSE", "Manual (cfdisk)",
        "Launch cfdisk for custom partitioning",
        "FALSE", "MBR (Legacy)",
        "MBR partition table for old BIOS",
        "--width=500", "--height=300",
        "--center",
        "--button=Next:0", "--button=Back:1",
    )
    if code != 0:
        return None

    if "Auto" in out:
        return "auto"
    elif "Manual" in out:
        return "manual"
    elif "MBR" in out:
        return "mbr"
    return None


def confirm_erase(device):
    """Confirm disk erase dialog."""
    out, code = _yad(
        "--title=Confirm",
        "--text=<b>WARNING: This will ERASE ALL DATA on:</b>\n\n"
               f"<span color='red'><b>{device}</b></span>\n\n"
               "This action cannot be undone!",
        "--question",
        "--width=450", "--height=250",
        "--center",
        "--button=Yes, erase:0", "--button=No, go back:1",
    )
    return code == 0


def user_setup():
    """User configuration dialog.

    Returns: dict with username, password, hostname or None
    """
    out, code = _yad(
        "--title=User Setup",
        "--form",
        "--text=<b>Create your user account:</b>",
        "--field=Username",
        "--field=Password:H",
        "--field=Confirm Password:H",
        "--field=Hostname",
        "--width=450", "--height=300",
        "--center",
        "--button=Next:0", "--button=Back:1",
    )
    if code != 0:
        return None

    parts = out.split("|")
    if len(parts) < 4:
        return None

    username = parts[0].strip()
    password = parts[1].strip()
    confirm = parts[2].strip()
    hostname = parts[3].strip() or "superlite"

    if not username:
        _yad("--error", "--text=Username cannot be empty!", "--center")
        return None

    if password != confirm:
        _yad("--error", "--text=Passwords do not match!", "--center")
        return None

    if not password:
        _yad("--error", "--text=Password cannot be empty!", "--center")
        return None

    return {
        "username": username,
        "password": password,
        "hostname": hostname,
    }


def install_progress():
    """Show installation progress dialog.

    Returns a context manager or callback for progress updates.
    """
    # This is a placeholder - actual progress will be shown via
    # yad --progress piped from the installer
    pass


def show_error(message):
    """Show error dialog."""
    _yad("--error", f"--text={message}", "--center", "--width=400")


def show_success(message="Installation complete!"):
    """Show success dialog."""
    out, code = _yad(
        "--title=Installation Complete",
        "--text=<b>SuperLite OS installed successfully!</b>\n\n" + message,
        "--info",
        "--width=400", "--height=200",
        "--center",
        "--button=Reboot:0", "--button=Close:1",
    )
    return code == 0


def confirm_reboot():
    """Confirm reboot dialog."""
    out, code = _yad(
        "--title=Reboot",
        "--text=Remove installation media and reboot?",
        "--question",
        "--center",
        "--button=Reboot:0", "--button=Cancel:1",
    )
    return code == 0
