package main

import (
	"fmt"
	"strings"
)

// Disk represents a block device detected from /sys/block.
type Disk struct {
	Name  string // e.g. "sda", "nvme0n1"
	Path  string // e.g. "/dev/sda"
	Size  string // e.g. "500G"
	Model string // e.g. "Samsung SSD 870"
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
