package main

import (
	"fmt"
	"os/exec"
	"strings"
)

const (
	title = "SuperLite Partition Manager"
	width = 600
)

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

// YadMainMenu shows the main action menu.
// Returns the action name, or empty string if cancelled.
func YadMainMenu() string {
	out, rc := yadRun(
		"--title="+title,
		"--text=<b><big>SuperLite Partition Manager</big></b>\n\nSelect an action:",
		"--list", "--column=Action", "--column=Description",
		"--print-column=1", "--separator=",
		"--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--height=400",
		"--center",
		"List Disks\tShow available disks",
		"List Partitions\tShow partitions on a disk",
		"Create Partition\tCreate a new partition",
		"Delete Partition\tDelete a partition",
		"Resize Partition\tResize a partition",
		"Auto Partition\tAuto-partition a disk (EFI + swap + root)",
		"Format\tFormat a partition with a filesystem",
		"Mount\tMount a partition",
		"Unmount\tUnmount a partition",
		"Wipe Disk\tErase all data on a disk",
		"Benchmark\tTest read/write speed",
		"cfdisk\tOpen cfdisk TUI",
		"sgdisk\tOpen sgdisk TUI",
		"Shell\tOpen a shell",
	)

	if rc != 0 || out == "" {
		return ""
	}
	return strings.TrimSpace(out)
}

// YadDiskSelect shows a disk selection dialog.
// Returns the selected disk path, or empty if cancelled.
func YadDiskSelect(disks []Disk) string {
	if len(disks) == 0 {
		_, _ = yadRun("--title="+title, "--error", "--text=No disks found!", fmt.Sprintf("--width=%d", width), "--center")
		return ""
	}

	var rows []string
	for _, d := range disks {
		rows = append(rows, fmt.Sprintf("%s\t%s\t%s", d.Path, d.Size, d.Model))
	}

	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Select a disk:</b>",
		"--list", "--column=Device", "--column=Size", "--column=Model",
		"--print-column=1", "--separator=",
		"--button=OK!go-next:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--height=300",
		"--center",
		strings.Join(rows, "\n"),
	)

	if rc != 0 {
		return ""
	}
	return strings.TrimSpace(out)
}

// YadPartitionSelect shows a partition selection dialog.
// Returns the selected partition path, or empty if cancelled.
func YadPartitionSelect(diskPath string) string {
	parts, err := ListPartitions(diskPath)
	if err != nil || len(parts) == 0 {
		_, _ = yadRun("--title="+title, "--error", "--text=No partitions found!", fmt.Sprintf("--width=%d", width), "--center")
		return ""
	}

	var rows []string
	for _, p := range parts {
		mount := p.MountPoint
		if mount == "" {
			mount = "—"
		}
		label := p.Label
		if label == "" {
			label = "—"
		}
		rows = append(rows, fmt.Sprintf("%s\t%s\t%s\t%s\t%s", p.Path, p.Size, p.FSType, mount, label))
	}

	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Select a partition:</b>",
		"--list", "--column=Partition", "--column=Size", "--column=FS", "--column=Mount", "--column=Label",
		"--print-column=1", "--separator=",
		"--button=OK!go-next:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--height=300",
		"--center",
		strings.Join(rows, "\n"),
	)

	if rc != 0 {
		return ""
	}
	return strings.TrimSpace(out)
}

// YadConfirm shows a confirmation dialog.
func YadConfirm(text string) bool {
	_, rc := yadRun(
		"--title="+title,
		"--text="+text,
		"--question",
		"--button=Yes!apply:0", "--button=No!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
	return rc == 0
}

// YadInfo shows an info dialog.
func YadInfo(text string) {
	_, _ = yadRun(
		"--title="+title,
		"--text="+text,
		"--button=OK:0",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
}

// YadError shows an error dialog.
func YadError(text string) {
	_, _ = yadRun(
		"--title="+title,
		"--error",
		"--text="+text,
		"--button=OK:0",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
}

// YadCreatePartition shows a form for creating a new partition.
// Returns disk, start, end, fsType, label — or empty strings if cancelled.
func YadCreatePartition() (disk, start, end, fsType, label string) {
	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Create Partition</b>",
		"--form",
		"--field=Disk (e.g. sda):CB",
		"--field=Start (e.g. 1MiB):E",
		"--field=End (e.g. 100%):E",
		"--field=Filesystem:CB",
		"--field=Label (optional):E",
		"--button=Create!add:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
		"!"+diskListCombo(),
		"1MiB",
		"100%",
		"!ext4!ext3!ext2!fat32!ntfs!btrfs!xfs!f2fs!swap!none",
		"",
	)

	if rc != 0 || out == "" {
		return "", "", "", "", ""
	}

	fields := strings.Split(out, "|")
	if len(fields) >= 5 {
		return fields[0], fields[1], fields[2], fields[3], fields[4]
	}
	return "", "", "", "", ""
}

// YadResizeForm shows a form for resizing a partition.
// Returns new size string, or empty if cancelled.
func YadResizeForm(partPath string) string {
	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Resize Partition: "+partPath+"</b>",
		"--form",
		"--field=New size (e.g. 100G or 100%):E",
		"--button=Resize!edit:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
		"100%",
	)

	if rc != 0 || out == "" {
		return ""
	}
	return strings.TrimSpace(strings.TrimSuffix(out, "|"))
}

// YadWipeConfirm shows a confirmation for disk wipe with YES entry.
// Returns true if user typed YES.
func YadWipeConfirm(diskPath string) bool {
	out, rc := yadRun(
		"--title="+title,
		"--text=<b><span color='red'>WIPE DISK: "+diskPath+"</span></b>\n\nType YES to confirm:",
		"--entry",
		"--button=Wipe!edit-clear:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
	)
	return rc == 0 && strings.TrimSpace(out) == "YES"
}

// YadMountForm shows a form for mounting a partition.
// Returns mountpoint, or empty if cancelled.
func YadMountForm(partPath string) string {
	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Mount: "+partPath+"</b>",
		"--form",
		"--field=Mount at:E",
		"--button=Mount!drive-harddisk:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
		"/mnt",
	)

	if rc != 0 || out == "" {
		return ""
	}
	return strings.TrimSpace(strings.TrimSuffix(out, "|"))
}

// diskListCombo returns a combo-box string of available disks.
func diskListCombo() string {
	disks, err := ListDisks()
	if err != nil {
		return "none"
	}
	var names []string
	for _, d := range disks {
		names = append(names, d.Name)
	}
	return strings.Join(names, "!")
}
