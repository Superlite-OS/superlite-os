package main

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

// Disk represents a block device.
type Disk struct {
	Name  string
	Path  string
	Size  string
	Model string
}

// Partition represents a partition from lsblk.
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

// ListDisks returns available disks.
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
		typeField := fields[len(fields)-1]
		model := strings.Join(fields[2:len(fields)-1], " ")

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

// ListPartitions returns partitions for a given disk.
func ListPartitions(diskPath string) ([]Partition, error) {
	out, err := exec.Command("lsblk", "-no", "NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL", diskPath).Output()
	if err != nil {
		return nil, fmt.Errorf("lsblk: %w", err)
	}

	diskName := strings.TrimPrefix(diskPath, "/dev/")

	var parts []Partition
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 1 {
			continue
		}
		name := fields[0]
		// Skip the disk itself and loop devices
		if name == diskName || strings.HasPrefix(name, "loop") {
			continue
		}

		p := Partition{Name: name, Path: "/dev/" + name}
		if len(fields) >= 2 {
			p.Size = fields[1]
		}
		if len(fields) >= 3 {
			p.FSType = fields[2]
		}
		if len(fields) >= 4 {
			p.MountPoint = fields[3]
		}
		if len(fields) >= 5 {
			p.Label = strings.Join(fields[4:], " ")
		}
		parts = append(parts, p)
	}
	return parts, nil
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

// PartitionCount returns the number of partitions on a disk.
func PartitionCount(diskPath string) int {
	out, err := exec.Command("parted", "-s", diskPath, "print").Output()
	if err != nil {
		return 0
	}
	count := 0
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if len(line) > 0 && line[0] >= '0' && line[0] <= '9' {
			count++
		}
	}
	return count
}

// GetParentDisk returns the parent disk device for a partition.
func GetParentDisk(partPath string) string {
	out, _ := exec.Command("lsblk", "-no", "PKNAME", partPath).Output()
	name := strings.TrimSpace(strings.Split(string(out), "\n")[0])
	if name == "" {
		return ""
	}
	return "/dev/" + name
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
