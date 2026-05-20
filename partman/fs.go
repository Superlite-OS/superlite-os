package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// FSType represents a supported filesystem type.
type FSType struct {
	Name  string
	Mkfs  string
	Label string // label command format: "e2label", "fatlabel", etc.
}

var filesystems = []FSType{
	{"ext4", "mkfs.ext4 -F", "e2label"},
	{"ext3", "mkfs.ext3 -F", "e2label"},
	{"ext2", "mkfs.ext2 -F", "e2label"},
	{"fat32", "mkfs.fat -F32", "fatlabel"},
	{"ntfs", "mkfs.ntfs -f", ""},
	{"btrfs", "mkfs.btrfs -f", ""},
	{"xfs", "mkfs.xfs -f", ""},
	{"f2fs", "mkfs.f2fs -f", ""},
	{"swap", "mkswap", ""},
}

// Mkfs formats a partition with the given filesystem type and optional label.
func Mkfs(device, fsType, label string) error {
	for _, fs := range filesystems {
		if fs.Name != fsType {
			continue
		}
		args := strings.Fields(fs.Mkfs)
		args = append(args, device)
		if out, err := exec.Command(args[0], args[1:]...).CombinedOutput(); err != nil {
			return fmt.Errorf("mkfs %s: %s: %w", fsType, string(out), err)
		}
		// Set label if supported
		if label != "" && fs.Label != "" {
			exec.Command(fs.Label, device, label).Run()
		}
		return nil
	}
	return fmt.Errorf("unsupported filesystem: %s", fsType)
}

// MountDevice mounts a device at a given mountpoint.
func MountDevice(device, mountpoint string) error {
	os.MkdirAll(mountpoint, 0755)
	if err := syscall.Mount(device, mountpoint, "", 0, ""); err != nil {
		return fmt.Errorf("mount %s: %w", device, err)
	}
	return nil
}

// UnmountDevice unmounts a device or mountpoint.
func UnmountDevice(target string) error {
	if err := syscall.Unmount(target, 0); err != nil {
		return fmt.Errorf("umount %s: %w", target, err)
	}
	return nil
}

// IsMounted checks if a device is currently mounted by parsing /proc/mounts.
func IsMounted(device string) bool {
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return false
	}
	defer f.Close()

	realDev, _ := filepath.EvalSymlinks(device)
	if realDev == "" {
		realDev = device
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) >= 1 {
			mountedDev, _ := filepath.EvalSymlinks(fields[0])
			if mountedDev == realDev || fields[0] == device {
				return true
			}
		}
	}
	return false
}

// Benchmark runs a read/write benchmark on a partition.
func Benchmark(device string) (writeSpeed, readSpeed string, err error) {
	// Create temp mount
	tmpDir := "/tmp/partman_bench"
	os.MkdirAll(tmpDir, 0755)
	if err := MountDevice(device, tmpDir); err != nil {
		return "", "", fmt.Errorf("mount for benchmark: %w", err)
	}
	defer UnmountDevice(tmpDir)

	// Write test
	out, err := exec.Command("dd", "if=/dev/zero", "of="+tmpDir+"/.bench", "bs=1M", "count=128", "conv=fdatasync").CombinedOutput()
	if err != nil {
		return "", "", fmt.Errorf("dd write: %w", err)
	}
	writeSpeed = extractDDSpeed(string(out))

	// Read test
	out, err = exec.Command("dd", "if="+tmpDir+"/.bench", "of=/dev/null", "bs=1M").CombinedOutput()
	if err != nil {
		return writeSpeed, "", fmt.Errorf("dd read: %w", err)
	}
	readSpeed = extractDDSpeed(string(out))

	// Cleanup
	os.Remove(tmpDir + "/.bench")

	return writeSpeed, readSpeed, nil
}

// extractDDSpeed extracts the transfer speed from dd output.
func extractDDSpeed(output string) string {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if strings.Contains(line, "bytes") || strings.Contains(line, "copied") {
			parts := strings.Fields(line)
			for i, p := range parts {
				if (p == "MB/s" || p == "GB/s" || p == "kB/s" || p == "bytes/s") && i > 0 {
					return parts[i-1] + " " + p
				}
			}
			return strings.TrimSpace(line)
		}
	}
	return "unknown"
}

// ResizeFilesystem resizes a filesystem to fill the partition.
func ResizeFilesystem(device, fsType string) error {
	switch fsType {
	case "ext4", "ext3", "ext2":
		return exec.Command("resize2fs", device).Run()
	case "btrfs":
		return exec.Command("btrfs", "filesystem", "resize", "max", device).Run()
	case "xfs":
		return exec.Command("xfs_growfs", device).Run()
	case "f2fs":
		return exec.Command("resize.f2fs", device).Run()
	default:
		return fmt.Errorf("resize not supported for %s", fsType)
	}
}
