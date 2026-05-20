package main

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

// Disk represents a block device detected by lsblk.
type Disk struct {
	Name  string // e.g. "sda", "nvme0n1"
	Path  string // e.g. "/dev/sda"
	Size  string // e.g. "500G"
	Model string // e.g. "Samsung SSD 870"
}

// ListDisks returns available disks using lsblk.
// Filters out loop, rom, and sr devices. Only returns TYPE="disk".
func ListDisks() ([]Disk, error) {
	out, err := exec.Command("lsblk", "-dno", "NAME,SIZE,MODEL,TYPE").Output()
	if err != nil {
		return nil, fmt.Errorf("lsblk: %w", err)
	}

	var disks []Disk
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}

		name := fields[0]
		size := fields[1]
		typeField := fields[len(fields)-1] // TYPE is always last
		model := strings.Join(fields[2:len(fields)-1], " ")

		// Filter: only real disks, skip loop/rom/sr
		if typeField != "disk" {
			continue
		}
		if strings.HasPrefix(name, "loop") || strings.HasPrefix(name, "rom") || strings.HasPrefix(name, "sr") {
			continue
		}
		if model == "" {
			model = "(unknown)"
		}

		disks = append(disks, Disk{
			Name:  name,
			Path:  "/dev/" + name,
			Size:  size,
			Model: model,
		})
	}

	return disks, nil
}

// PartitionSeparator returns "p" for NVMe/mmcblk/md devices, "" otherwise.
func PartitionSeparator(diskPath string) string {
	name := strings.TrimPrefix(diskPath, "/dev/")
	if strings.HasPrefix(name, "nvme") || strings.HasPrefix(name, "mmcblk") || strings.HasPrefix(name, "md") {
		return "p"
	}
	return ""
}

// PartitionPath returns the partition device path (e.g. /dev/sda1 or /dev/nvme0n1p1).
func PartitionPath(diskPath string, partNum int) string {
	return fmt.Sprintf("%s%s%d", diskPath, PartitionSeparator(diskPath), partNum)
}

// DiskSizeMB returns the disk size in megabytes.
func DiskSizeMB(diskPath string) (int, error) {
	out, err := exec.Command("blockdev", "--getsize64", diskPath).Output()
	if err != nil {
		return 0, fmt.Errorf("blockdev: %w", err)
	}
	var bytes int64
	if _, err := fmt.Sscanf(strings.TrimSpace(string(out)), "%d", &bytes); err != nil {
		return 0, fmt.Errorf("parse size: %w", err)
	}
	return int(bytes / 1024 / 1024), nil
}

// DiskInfo returns the size and model of a disk via lsblk.
func DiskInfo(diskPath string) (size, model string) {
	out, _ := exec.Command("lsblk", "-dno", "SIZE,MODEL", diskPath).Output()
	fields := strings.Fields(strings.TrimSpace(string(out)))
	if len(fields) >= 1 {
		size = fields[0]
	}
	if len(fields) >= 2 {
		model = strings.Join(fields[1:], " ")
	}
	return
}
