package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const sysBlock = "/sys/block"

// ListDisks returns available disks by reading /sys/block/.
// Skips loop, ram, rom, and sr devices.
func ListDisks() ([]Disk, error) {
	entries, err := os.ReadDir(sysBlock)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", sysBlock, err)
	}

	var disks []Disk
	for _, e := range entries {
		name := e.Name()

		// Skip non-disk devices
		if strings.HasPrefix(name, "loop") ||
			strings.HasPrefix(name, "ram") ||
			strings.HasPrefix(name, "rom") ||
			strings.HasPrefix(name, "sr") {
			continue
		}

		devPath := filepath.Join(sysBlock, name)

		// Must have a removable flag file (real block device)
		removable, _ := readSysfsInt(filepath.Join(devPath, "removable"))
		if removable != 0 {
			continue
		}

		sizeBytes, err := diskSizeBytes(devPath)
		if err != nil || sizeBytes == 0 {
			continue
		}

		model := readModel(devPath)

		disks = append(disks, Disk{
			Name:  name,
			Path:  "/dev/" + name,
			Size:  humanSize(sizeBytes),
			Model: model,
		})
	}
	return disks, nil
}

// DiskSizeMB returns the disk size in megabytes.
func DiskSizeMB(diskPath string) (int, error) {
	name := strings.TrimPrefix(diskPath, "/dev/")
	devPath := filepath.Join(sysBlock, name)
	bytes, err := diskSizeBytes(devPath)
	if err != nil {
		return 0, err
	}
	return int(bytes / 1024 / 1024), nil
}

// DiskInfo returns the size and model of a disk.
func DiskInfo(diskPath string) (size, model string) {
	name := strings.TrimPrefix(diskPath, "/dev/")
	devPath := filepath.Join(sysBlock, name)
	bytes, _ := diskSizeBytes(devPath)
	return humanSize(bytes), readModel(devPath)
}

// diskSizeBytes reads disk size from /sys/block/<dev>/size (in 512-byte sectors).
func diskSizeBytes(devPath string) (int64, error) {
	data, err := os.ReadFile(filepath.Join(devPath, "size"))
	if err != nil {
		return 0, err
	}
	sectors, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return 0, err
	}
	return sectors * 512, nil
}

// readModel reads the device model from sysfs.
func readModel(devPath string) string {
	data, err := os.ReadFile(filepath.Join(devPath, "device", "model"))
	if err != nil {
		return "(unknown)"
	}
	model := strings.TrimSpace(string(data))
	if model == "" {
		return "(unknown)"
	}
	return model
}

// readSysfsInt reads an integer from a sysfs file.
func readSysfsInt(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	val, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return 0, err
	}
	return val, nil
}

// humanSize formats bytes to human-readable string (e.g. "500G", "1T").
func humanSize(bytes int64) string {
	const (
		KB = 1024
		MB = KB * 1024
		GB = MB * 1024
		TB = GB * 1024
	)
	switch {
	case bytes >= TB:
		return fmt.Sprintf("%.0fT", float64(bytes)/float64(TB))
	case bytes >= GB:
		return fmt.Sprintf("%.0fG", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.0fM", float64(bytes)/float64(MB))
	default:
		return fmt.Sprintf("%d", bytes)
	}
}
