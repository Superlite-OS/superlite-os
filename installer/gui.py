#!/usr/bin/env python3
"""
SuperLite OS — GUI Dialog Module (tofi)
All installer UI dialogs using tofi (dmenu-style)
"""
import subprocess
import os

# Tofi config for installer — full-screen, Catppuccin Mocha
TOFI_CONFIG = os.path.join(os.path.dirname(__file__), "tofi-installer.conf")

# Hint texts for input fields — shown as first "option" to guide user
_HINT_USERNAME = "[ Type your username and press Enter ]"
_HINT_PASSWORD = "[ Type password and press Enter ]"
_HINT_CONFIRM  = "[ Retype password and press Enter ]"
_HINT_HOSTNAME = "[ Type hostname and press Enter (default: superlite) ]"


def _tofi(options, prompt="Select", hide_input=False):
    """Run tofi with options and return selected value.

    Args:
        options: list of strings to choose from
        prompt: prompt text (single line, no newlines)
        hide_input: if True, hide typed input (for passwords)
    Returns: selected string or None if cancelled
    """
    cmd = ["tofi", f"--prompt-text={prompt}"]
    if TOFI_CONFIG and os.path.isfile(TOFI_CONFIG):
        cmd += [f"--config={TOFI_CONFIG}"]
    if hide_input:
        cmd += ["--hide-input=true"]

    result = subprocess.run(
        cmd,
        input="\n".join(options),
        capture_output=True, text=True
    )
    choice = result.stdout.strip()
    if not choice or result.returncode != 0:
        return None
    return choice


def _tofi_input(prompt="Enter value", hint="", hide_input=False):
    """Run tofi for free-text input.

    Shows a hint option as the first item. User types to filter/replace.
    When user types and presses Enter, their typed text is returned.

    Args:
        prompt: short label shown before input (e.g. "Username:")
        hint: hint option shown as first item to guide user
        hide_input: if True, hide typed input (for passwords)
    Returns: entered text or None if cancelled
    """
    cmd = ["tofi", f"--prompt-text={prompt}"]
    if TOFI_CONFIG and os.path.isfile(TOFI_CONFIG):
        cmd += [f"--config={TOFI_CONFIG}"]
    if hide_input:
        cmd += ["--hide-input=true"]

    # Show hint as first option — user types to filter, Enter to submit
    options = [hint] if hint else []
    result = subprocess.run(
        cmd,
        input="\n".join(options),
        capture_output=True, text=True
    )
    text = result.stdout.strip()
    if not text or result.returncode != 0:
        return None
    # If user selected the hint text, they didn't type anything
    if text == hint:
        return None
    return text


def welcome():
    """Welcome dialog."""
    choice = _tofi(
        ["Continue", "Cancel"],
        prompt="SuperLite OS Installer"
    )
    return choice == "Continue"


def select_disk(devices):
    """Select target disk from list.

    Args:
        devices: list of dicts with keys: name, path, size, model
    Returns: selected device dict or None
    """
    if not devices:
        _tofi(["OK"], prompt="Error: No disks found!")
        return None

    options = []
    for dev in devices:
        dtype = "SSD" if dev.get("rota") == "0" else "HDD"
        if dev.get("tran"):
            dtype += f" ({dev['tran']})"
        model = dev.get("model", "Unknown") or "Unknown"
        options.append(f"{dev['path']}  {dev['size']}  {model}  [{dtype}]")

    choice = _tofi(options, prompt="Select target disk (ALL DATA WILL BE ERASED)")
    if not choice:
        return None

    selected_path = choice.split()[0]
    for dev in devices:
        if dev["path"] == selected_path:
            return dev
    return None


def partition_scheme(boot_mode):
    """Choose partition scheme.

    Returns: "auto", "manual", "mbr", or None
    """
    boot_info = boot_mode.upper()
    if boot_mode == "uefi":
        auto_desc = "GPT: EFI + swap + root"
    else:
        auto_desc = "GPT: bios_grub + swap + root"

    options = [
        f"Auto (Recommended) - {auto_desc}",
        "Manual (cfdisk) - custom partitioning",
        "MBR (Legacy) - old BIOS",
    ]

    choice = _tofi(options, prompt=f"Partition scheme [{boot_info}]")
    if not choice:
        return None

    if "Auto" in choice:
        return "auto"
    elif "Manual" in choice:
        return "manual"
    elif "MBR" in choice:
        return "mbr"
    return None


def confirm_erase(device):
    """Confirm disk erase dialog."""
    choice = _tofi(
        ["Yes, erase all data", "No, go back"],
        prompt=f"ERASE ALL DATA on {device}?"
    )
    return choice is not None and choice.startswith("Yes")


def user_setup():
    """User configuration dialog.

    Returns: dict with username, password, hostname or None
    """
    username = _tofi_input(prompt="Username:", hint=_HINT_USERNAME)
    if not username:
        return None

    password = _tofi_input(prompt="Password:", hint=_HINT_PASSWORD, hide_input=True)
    if not password:
        return None

    confirm = _tofi_input(prompt="Confirm:", hint=_HINT_CONFIRM, hide_input=True)
    if password != confirm:
        _tofi(["OK"], prompt="Error: Passwords do not match!")
        return None

    hostname = _tofi_input(prompt="Hostname:", hint=_HINT_HOSTNAME)
    if not hostname:
        hostname = "superlite"

    return {
        "username": username,
        "password": password,
        "hostname": hostname,
    }


def show_error(message):
    """Show error dialog."""
    first_line = message.split("\n")[0][:80]
    _tofi(["OK"], prompt=f"Error: {first_line}")


def show_success(message="Installation complete!"):
    """Show success dialog."""
    choice = _tofi(
        ["Reboot", "Close"],
        prompt="SuperLite OS installed successfully!"
    )
    return choice == "Reboot"


def confirm_reboot():
    """Confirm reboot dialog."""
    choice = _tofi(
        ["Reboot now", "Cancel"],
        prompt="Remove installation media and reboot?"
    )
    return choice == "Reboot now"
