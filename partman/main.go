package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

func main() {
	for {
		action := YadMainMenu()
		if action == "" {
			os.Exit(0)
		}

		switch action {
		case "List Disks":
			actionListDisks()
		case "List Partitions":
			actionListPartitions()
		case "Create Partition":
			actionCreatePartition()
		case "Delete Partition":
			actionDeletePartition()
		case "Resize Partition":
			actionResizePartition()
		case "Auto Partition":
			actionAutoPartition()
		case "Format":
			actionFormat()
		case "Mount":
			actionMount()
		case "Unmount":
			actionUnmount()
		case "Wipe Disk":
			actionWipeDisk()
		case "Benchmark":
			actionBenchmark()
		case "cfdisk":
			actionCfdisk()
		case "sgdisk":
			actionSgdisk()
		case "Shell":
			actionShell()
		default:
			YadError("Unknown action: " + action)
		}
	}
}

func actionListDisks() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error listing disks: %v", err))
		return
	}

	var rows []string
	for _, d := range disks {
		rows = append(rows, fmt.Sprintf("%s\t%s\t%s", d.Path, d.Size, d.Model))
	}

	if len(rows) == 0 {
		YadInfo("No disks found.")
		return
	}

	_, _ = yadRun(
		"--title="+title+" — Disks",
		"--list", "--column=Device", "--column=Size", "--column=Model",
		"--button=Close:0",
		fmt.Sprintf("--width=%d", width),
		"--height=300",
		"--center",
		joinRows(rows),
	)
}

func actionListPartitions() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	parts, err := ListPartitions(diskPath)
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
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

	if len(rows) == 0 {
		YadInfo("No partitions found on " + diskPath)
		return
	}

	_, _ = yadRun(
		"--title="+title+" — Partitions",
		"--list", "--column=Partition", "--column=Size", "--column=FS", "--column=Mount", "--column=Label",
		"--button=Close:0",
		fmt.Sprintf("--width=%d", width),
		"--height=300",
		"--center",
		joinRows(rows),
	)
}

func actionCreatePartition() {
	disk, start, end, fsType, label := YadCreatePartition()
	if disk == "" {
		return
	}

	dev := "/dev/" + disk

	// Check if block device exists
	if !pathExists(dev) {
		YadError("Device not found: " + dev)
		return
	}

	// Check partition table
	pttype := getPTType(dev)
	if pttype == "unknown" || pttype == "" {
		if !YadConfirm(fmt.Sprintf("No partition table on %s.\nCreate GPT?", dev)) {
			return
		}
		if out, err := exec.Command("parted", "-s", dev, "mklabel", "gpt").CombinedOutput(); err != nil {
			YadError(fmt.Sprintf("Failed to create GPT: %s", string(out)))
			return
		}
	}

	// Create partition
	pnum := PartitionCount(dev) + 1
	if out, err := exec.Command("parted", "-s", dev, "mkpart", "primary", start, end).CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("Failed to create partition: %s", string(out)))
		return
	}

	// Format if requested
	if fsType != "" && fsType != "none" {
		sep := PartitionSeparator(dev)
		pd := dev + sep + fmt.Sprintf("%d", pnum)

		// Wait for device to appear
		if err := waitForDevice(pd); err != nil {
			YadError("Partition created but device not found: " + pd)
			return
		}

		if err := Mkfs(pd, fsType, label); err != nil {
			YadError(fmt.Sprintf("Format failed: %v", err))
			return
		}
	}

	YadInfo(fmt.Sprintf("Partition %d created on %s", pnum, dev))
}

func actionDeletePartition() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	partPath := YadPartitionSelect(diskPath)
	if partPath == "" {
		return
	}

	// Check if mounted
	if IsMounted(partPath) {
		if !YadConfirm(partPath + " is mounted. Unmount first?") {
			return
		}
		if err := UnmountDevice(partPath); err != nil {
			YadError(fmt.Sprintf("Unmount failed: %v", err))
			return
		}
	}

	parentDisk := GetParentDisk(partPath)
	if parentDisk == "" {
		YadError("Cannot determine parent disk for " + partPath)
		return
	}

	num := GetPartitionNumber(partPath, parentDisk)
	if !YadConfirm(fmt.Sprintf("DELETE partition %s?\n\nThis cannot be undone!", partPath)) {
		return
	}

	if out, err := exec.Command("parted", "-s", parentDisk, "rm", num).CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("Delete failed: %s", string(out)))
		return
	}

	YadInfo("Partition " + partPath + " deleted.")
}

func actionResizePartition() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	partPath := YadPartitionSelect(diskPath)
	if partPath == "" {
		return
	}

	newSize := YadResizeForm(partPath)
	if newSize == "" {
		return
	}

	parentDisk := GetParentDisk(partPath)
	num := GetPartitionNumber(partPath, parentDisk)

	// Unmount if mounted
	if IsMounted(partPath) {
		UnmountDevice(partPath)
	}

	if out, err := exec.Command("parted", "-s", parentDisk, "resizepart", num, newSize).CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("Resize failed: %s", string(out)))
		return
	}

	// Resize filesystem
	fstype := getFSType(partPath)
	if fstype != "" {
		if err := ResizeFilesystem(partPath, fstype); err != nil {
			YadError(fmt.Sprintf("Resize partition OK, but filesystem resize failed: %v", err))
			return
		}
	}

	YadInfo("Partition " + partPath + " resized to " + newSize)
}

func actionAutoPartition() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	if !YadConfirm(fmt.Sprintf("ERASE %s completely?\n\n"+
		"This will create:\n"+
		"- EFI System Partition (512 MB)\n"+
		"- Swap (size/10, max 2 GB)\n"+
		"- Root filesystem (ext4, remaining space)", diskPath)) {
		return
	}

	sizeMB, err := DiskSizeMB(diskPath)
	if err != nil {
		YadError(fmt.Sprintf("Cannot read disk size: %v", err))
		return
	}
	swapMB := sizeMB / 10
	if swapMB > 2048 {
		swapMB = 2048
	}
	swapEnd := 513 + swapMB
	sep := PartitionSeparator(diskPath)

	// Wipe and create GPT
	exec.Command("wipefs", "-a", diskPath).Run()
	if out, err := exec.Command("parted", "-s", diskPath, "mklabel", "gpt").CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("GPT failed: %s", string(out)))
		return
	}

	// EFI
	if out, err := exec.Command("parted", "-s", diskPath, "mkpart", "ESP", "fat32", "1MiB", "513MiB").CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("EFI partition failed: %s", string(out)))
		return
	}
	exec.Command("parted", "-s", diskPath, "set", "1", "esp", "on").Run()

	// Swap
	if out, err := exec.Command("parted", "-s", diskPath, "mkpart", "primary", "linux-swap", "513MiB", fmt.Sprintf("%dMiB", swapEnd)).CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("Swap partition failed: %s", string(out)))
		return
	}

	// Root
	if out, err := exec.Command("parted", "-s", diskPath, "mkpart", "primary", "ext4", fmt.Sprintf("%dMiB", swapEnd), "100%").CombinedOutput(); err != nil {
		YadError(fmt.Sprintf("Root partition failed: %s", string(out)))
		return
	}

	// Format
	if err := Mkfs(diskPath+sep+"1", "fat32", ""); err != nil {
		YadError(fmt.Sprintf("Format EFI failed: %v", err))
		return
	}
	if err := Mkfs(diskPath+sep+"2", "swap", ""); err != nil {
		YadError(fmt.Sprintf("Format swap failed: %v", err))
		return
	}
	if err := Mkfs(diskPath+sep+"3", "ext4", ""); err != nil {
		YadError(fmt.Sprintf("Format root failed: %v", err))
		return
	}

	YadInfo(fmt.Sprintf("Auto-partition complete!\n\nEFI: %s%s1\nSwap: %s%s2 (%d MB)\nRoot: %s%s3",
		diskPath, sep, diskPath, sep, swapMB, diskPath, sep))
}

func actionFormat() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	partPath := YadPartitionSelect(diskPath)
	if partPath == "" {
		return
	}

	out, rc := yadRun(
		"--title="+title,
		"--text=<b>Format: "+partPath+"</b>",
		"--form",
		"--field=Filesystem:CB",
		"--field=Label (optional):E",
		"--button=Format!drive-harddisk:0", "--button=Cancel!cancel:1",
		fmt.Sprintf("--width=%d", width),
		"--center",
		"!ext4!ext3!ext2!fat32!ntfs!btrfs!xfs!f2fs!swap",
		"",
	)
	if rc != 0 || out == "" {
		return
	}

	fields := strings.Split(out, "|")
	if len(fields) < 2 {
		return
	}
	fsType := fields[0]
	label := fields[1]

	if IsMounted(partPath) {
		if !YadConfirm(partPath + " is mounted. Unmount first?") {
			return
		}
		UnmountDevice(partPath)
	}

	if err := Mkfs(partPath, fsType, label); err != nil {
		YadError(fmt.Sprintf("Format failed: %v", err))
		return
	}

	YadInfo(partPath + " formatted as " + fsType)
}

func actionMount() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	partPath := YadPartitionSelect(diskPath)
	if partPath == "" {
		return
	}

	mountpoint := YadMountForm(partPath)
	if mountpoint == "" {
		return
	}

	if err := MountDevice(partPath, mountpoint); err != nil {
		YadError(fmt.Sprintf("Mount failed: %v", err))
		return
	}

	YadInfo(partPath + " mounted at " + mountpoint)
}

func actionUnmount() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	partPath := YadPartitionSelect(diskPath)
	if partPath == "" {
		return
	}

	if err := UnmountDevice(partPath); err != nil {
		YadError(fmt.Sprintf("Unmount failed: %v", err))
		return
	}

	YadInfo(partPath + " unmounted.")
}

func actionWipeDisk() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	if !YadWipeConfirm(diskPath) {
		return
	}

	exec.Command("wipefs", "-a", diskPath).Run()
	exec.Command("dd", "if=/dev/zero", "of="+diskPath, "bs=1M", "count=1").Run()

	YadInfo(diskPath + " wiped.")
}

func actionBenchmark() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	partPath := YadPartitionSelect(diskPath)
	if partPath == "" {
		return
	}

	writeSpeed, readSpeed, err := Benchmark(partPath)
	if err != nil {
		YadError(fmt.Sprintf("Benchmark failed: %v", err))
		return
	}

	YadInfo(fmt.Sprintf("Benchmark: %s\n\nWrite: %s\nRead: %s", partPath, writeSpeed, readSpeed))
}

func actionCfdisk() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	cmd := exec.Command("foot", "-T", "cfdisk — "+diskPath, "-e", "cfdisk", diskPath)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}

func actionSgdisk() {
	disks, err := ListDisks()
	if err != nil {
		YadError(fmt.Sprintf("Error: %v", err))
		return
	}
	diskPath := YadDiskSelect(disks)
	if diskPath == "" {
		return
	}

	cmd := exec.Command("foot", "-T", "sgdisk — "+diskPath, "-e", "sgdisk", "--print", diskPath)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}

func actionShell() {
	cmd := exec.Command("foot", "-T", "Shell")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}

// Helper functions

func joinRows(rows []string) string {
	return strings.Join(rows, "\n")
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func getPTType(device string) string {
	out, err := exec.Command("blkid", "-s", "PTTYPE", "-o", "value", device).Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func getFSType(device string) string {
	out, err := exec.Command("blkid", "-s", "TYPE", "-o", "value", device).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func waitForDevice(path string) error {
	for i := 0; i < 10; i++ {
		if pathExists(path) {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("device %s not found after waiting", path)
}
