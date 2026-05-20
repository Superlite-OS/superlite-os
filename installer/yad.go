package main

import (
	"fmt"
	"os/exec"
	"strings"
)

const (
	title = "SuperLite OS Installer"
	width = 480
)

// yadButton represents a yad button definition.
type yadButton struct {
	label string
	icon  string
	code  int
}

func (b yadButton) String() string {
	return fmt.Sprintf("%s!%s:%d", b.label, b.icon, b.code)
}

// yadRun runs a yad command and returns stdout and exit code.
func yadRun(args ...string) (string, int) {
	cmd := exec.Command("yad", args...)
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return string(out), exitErr.ExitCode()
		}
		return string(out), -1
	}
	return strings.TrimSpace(string(out)), 0
}

// YadWelcome shows the welcome dialog.
// Returns true to proceed, false to cancel.
func YadWelcome() bool {
	_, rc := yadRun(
		"--title="+title,
		"--text=<b><big>Welcome to SuperLite OS</big></b>\n\n"+
			"This wizard will install SuperLite OS to your computer.\n\n"+
			"<b>Warning:</b> All data on the selected disk will be erased!\n\n"+
			"<tt>Alpine Linux + LabWC Wayland</tt>",
		"--image=drive-harddisk",
		"--button=Next!go-next:0",
		"--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
	return rc == 0
}

// YadSelectDisk shows the disk selection dialog.
// Returns the selected disk path, or empty string if cancelled/back.
// Returns ("back", nil) if user clicks Previous.
func YadSelectDisk(disks []Disk) (string, error) {
	if len(disks) == 0 {
		_, _ = yadRun(
			"--title="+title,
			"--error",
			"--text=No disks found!",
			fmt.Sprintf("--width=%d", width),
			"--center",
		)
		return "", fmt.Errorf("no disks available")
	}

	// Build list data: FALSE /dev/sda 500G Samsung SSD
	var rows []string
	for _, d := range disks {
		rows = append(rows, fmt.Sprintf("FALSE %s %s %s", d.Path, d.Size, d.Model))
	}

	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Select the target disk:</b>\n<i>Click the radio button to select, then click Next.</i>",
		"--list", "--radiolist",
		"--column=", "--column=Device", "--column=Size", "--column=Model",
		"--print-column=2", "--separator=|",
		"--button=Previous!go-previous:2",
		"--button=Next!go-next:0",
		"--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--height=300",
		"--center",
		strings.Join(rows, " "),
	)

	switch rc {
	case 1, 252: // Cancel or window close
		return "cancel", nil
	case 2: // Previous
		return "back", nil
	}

	// Parse selected device path
	disk := strings.TrimSpace(out)
	if disk == "" {
		return "", nil
	}

	// Validate it's a known disk path
	for _, d := range disks {
		if d.Path == disk {
			return disk, nil
		}
	}

	return "", nil
}

// YadNoDiskSelected shows a warning when no disk is selected.
func YadNoDiskSelected() {
	_, _ = yadRun(
		"--title="+title,
		"--warning",
		"--text=<b>No disk selected!</b>\n\n"+
			"Please click the radio button next to a disk,\n"+
			"then click <b>Next</b> to continue.",
		"--button=OK:0",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
}

// YadConfirm shows the installation confirmation dialog.
// Returns true to install, false to cancel/back.
// Returns ("back", true) if user clicks Previous.
func YadConfirm(disk Disk) (proceed bool, goBack bool) {
	size, model := DiskInfo(disk.Path)
	swapMB := 0
	if sizeMB, err := DiskSizeMB(disk.Path); err == nil {
		swapMB = sizeMB / 10
		if swapMB > 2048 {
			swapMB = 2048
		}
	}

	_, rc := yadRun(
		"--title="+title,
		"--text="+fmt.Sprintf(
			"<b><big>Confirm Installation</big></b>\n\n"+
				"<b>Target:</b> %s (%s)\n"+
				"<b>Model:</b> %s\n\n"+
				"<b><span color='red'>ALL DATA ON THIS DISK WILL BE ERASED!</span></b>\n\n"+
				"The disk will be partitioned automatically:\n"+
				"- EFI System Partition (512 MB)\n"+
				"- Swap (%d MB)\n"+
				"- Root filesystem (ext4, remaining space)",
			disk.Path, size, model, swapMB),
		"--image=dialog-warning",
		"--question",
		"--button=Previous!go-previous:2",
		"--button=Install!apply:0",
		"--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)

	switch rc {
	case 1, 252: // Cancel or window close
		return false, false
	case 2: // Previous
		return false, true
	default: // Install
		return true, false
	}
}

// YadProgress shows the installation progress dialog.
// It reads Progress updates from the channel and writes to yad's stdin.
// Returns the exit code: 0=success, 1=cancelled.
func YadProgress(disk Disk, ch <-chan Progress) int {
	args := []string{
		"--title=" + title,
		fmt.Sprintf("--text=<b>Installing SuperLite OS to %s</b>\n\nPlease wait...", disk.Path),
		"--percentage=0", "--auto-close", "--auto-kill",
		"--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
	}

	cmd := exec.Command("yad", args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return -1
	}

	if err := cmd.Start(); err != nil {
		return -1
	}

	// Feed progress from channel to yad stdin
	go func() {
		defer stdin.Close()
		for p := range ch {
			fmt.Fprintf(stdin, "%d\n", p.Percent)
			fmt.Fprintf(stdin, "# %s\n", p.Text)
		}
	}()

	if err := cmd.Wait(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return exitErr.ExitCode()
		}
		return -1
	}
	return 0
}

// YadInstallFailed shows the installation failure dialog with log content.
func YadInstallFailed(logPath string) {
	_, _ = yadRun(
		"--title="+title,
		"--text=<b><span color='red'>Installation failed!</span></b>\n\nCheck the log for details:",
		"--text-info", "--filename="+logPath,
		"--button=Close:0",
		"--width=600", "--height=400",
		"--center",
	)
}

// YadDone shows the installation complete dialog.
// Returns true if user clicks Reboot, false otherwise.
func YadDone(disk Disk) bool {
	_, rc := yadRun(
		"--title="+title,
		"--text="+fmt.Sprintf(
			"<b><big>Installation Complete!</big></b>\n\n"+
				"SuperLite OS has been installed successfully to %s.\n\n"+
				"You can now reboot into your new system.", disk.Path),
		"--image=object-select",
		"--button=Reboot!system-reboot:0",
		"--button=Close!window-close:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
	return rc == 0
}
