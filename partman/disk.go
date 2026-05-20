package main

import "strings"

// Disk represents a block device.
type Disk struct {
	Name  string
	Path  string
	Size  string
	Model string
}

// Partition represents a partition.
type Partition struct {
	Name       string
	Path       string
	Size       string
	FSType     string
	MountPoint string
	Label      string
}

// PartitionSeparator returns "p" for NVMe/mmcblk/md, "" otherwise.
func PartitionSeparator(diskPath string) string {
	name := strings.TrimPrefix(diskPath, "/dev/")
	if strings.HasPrefix(name, "nvme") || strings.HasPrefix(name, "mmcblk") || strings.HasPrefix(name, "md") {
		return "p"
	}
	return ""
}

// GetPartitionNumber extracts the partition number from a partition path.
func GetPartitionNumber(partPath string, parentDisk string) string {
	num := strings.TrimPrefix(partPath, parentDisk)
	sep := PartitionSeparator(parentDisk)
	if sep != "" {
		num = strings.TrimPrefix(num, sep)
	}
	return num
}
