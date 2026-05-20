package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const sysBlock = "/sys/block"

// ListDisks returns available disks by reading /sys/block/.
func ListDisks() ([]Disk, error) {
	entries, err := os.ReadDir(sysBlock)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", sysBlock, err)
	}

	var disks []Disk
	for _, e := range entries {
		name := e.Name()

		if strings.HasPrefix(name, "loop") ||
			strings.HasPrefix(name, "ram") ||
			strings.HasPrefix(name, "rom") ||
			strings.HasPrefix(name, "sr") {
			continue
		}

		devPath := filepath.Join(sysBlock, name)

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

// ListPartitions returns partitions for a given disk.
func ListPartitions(diskPath string) ([]Partition, error) {
	diskName := strings.TrimPrefix(diskPath, "/dev/")
	devPath := filepath.Join(sysBlock, diskName)

	entries, err := os.ReadDir(devPath)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", devPath, err)
	}

	// Load mount points from /proc/mounts
	mounts := parseProcMounts()

	var parts []Partition
	for _, e := range entries {
		name := e.Name()
		// Partitions are named like sda1, sda2, nvme0n1p1, etc.
		if !strings.HasPrefix(name, diskName) {
			continue
		}
		// Skip the disk itself (e.g. "sda" matches prefix of "sda1" but is not a partition entry)
		if name == diskName {
			continue
		}

		partPath := filepath.Join(devPath, name)
		sizeBytes, _ := diskSizeBytes(partPath)
		fstype := readFSType(name)
		mountPoint := mounts["/dev/"+name]
		label := readPartLabel(partPath)

		parts = append(parts, Partition{
			Name:       name,
			Path:       "/dev/" + name,
			Size:       humanSize(sizeBytes),
			FSType:     fstype,
			MountPoint: mountPoint,
			Label:      label,
		})
	}
	return parts, nil
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

// GetParentDisk returns the parent disk device for a partition.
func GetParentDisk(partPath string) string {
	partName := strings.TrimPrefix(partPath, "/dev/")

	entries, _ := os.ReadDir(sysBlock)
	for _, e := range entries {
		diskName := e.Name()
		// Check if this partition belongs to this disk
		if strings.HasPrefix(partName, diskName) && partName != diskName {
			// Verify the partition dir exists under this disk
			partDir := filepath.Join(sysBlock, diskName, partName)
			if _, err := os.Stat(partDir); err == nil {
				return "/dev/" + diskName
			}
		}
	}
	return ""
}

// PartitionCount returns the number of partitions on a disk.
func PartitionCount(diskPath string) int {
	name := strings.TrimPrefix(diskPath, "/dev/")
	devPath := filepath.Join(sysBlock, name)

	entries, err := os.ReadDir(devPath)
	if err != nil {
		return 0
	}

	count := 0
	for _, e := range entries {
		partName := e.Name()
		if strings.HasPrefix(partName, name) && partName != name {
			count++
		}
	}
	return count
}

// parseProcMounts reads /proc/mounts and returns a map of device -> mountpoint.
func parseProcMounts() map[string]string {
	mounts := make(map[string]string)
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return mounts
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) >= 2 {
			mounts[fields[0]] = fields[1]
		}
	}
	return mounts
}

// readFSType reads filesystem type from /sys/block/<parent>/<part>/partition/... or uses blkid fallback.
func readFSType(partName string) string {
	// Try to find the partition in sysfs
	entries, _ := os.ReadDir(sysBlock)
	for _, e := range entries {
		diskName := e.Name()
		if strings.HasPrefix(partName, diskName) && partName != diskName {
			// Try reading uevent for FS type info
			ueventPath := filepath.Join(sysBlock, diskName, partName, "uevent")
			if data, err := os.ReadFile(ueventPath); err == nil {
				for _, line := range strings.Split(string(data), "\n") {
					if strings.HasPrefix(line, "PARTN=") || strings.HasPrefix(line, "DEVTYPE=") {
						// Not directly useful for fstype
					}
				}
			}
		}
	}

	// Fallback: try reading superblock magic bytes from the block device
	devPath := "/dev/" + partName
	return detectFSType(devPath)
}

// detectFSType reads the first 4096 bytes of a block device and checks magic bytes.
func detectFSType(devPath string) string {
	f, err := os.Open(devPath)
	if err != nil {
		return ""
	}
	defer f.Close()

	buf := make([]byte, 4096)
	if _, err := f.Read(buf); err != nil {
		return ""
	}

	// ext2/3/4: superblock at offset 0x400, magic 0xEF53 at offset 0x38
	if len(buf) > 0x438 && buf[0x438] == 0x53 && buf[0x439] == 0xEF {
		return "ext4"
	}

	// XFS: magic "XFSB" at offset 0
	if len(buf) > 4 && string(buf[0:4]) == "XFSB" {
		return "xfs"
	}

	// FAT32: jump boot + "MSDOS" or "FAT32" at offset 0x52
	if len(buf) > 0x56 {
		fatSig := string(buf[0x52:0x57])
		if fatSig == "FAT32" {
			return "vfat"
		}
	}
	// FAT16: "FAT16" at offset 0x36
	if len(buf) > 0x3B {
		fatSig := string(buf[0x36:0x3B])
		if fatSig == "FAT16" {
			return "vfat"
		}
	}
	// FAT12: "FAT12" at offset 0x36
	if len(buf) > 0x3B {
		fatSig := string(buf[0x36:0x3B])
		if fatSig == "FAT12" {
			return "vfat"
		}
	}

	// btrfs: magic "_BHRfS_M" at offset 0x10040
	if len(buf) > 0x47 {
		btrfsMagic := []byte("_BHRfS_M")
		// Check at offset 0x10040 in a second read
	}

	// ntfs: "NTFS" at offset 0x03
	if len(buf) > 7 && string(buf[3:7]) == "NTFS" {
		return "ntfs"
	}

	// swap: "SWAPSPACE2" at offset 0x400
	if len(buf) > 0x40A {
		swapSig := string(buf[0x400:0x40A])
		if swapSig == "SWAPSPACE2" || swapSig == "SWAPSPACE" {
			return "swap"
		}
	}

	return ""
}

// readPartLabel reads the partition label from sysfs.
func readPartLabel(partPath string) string {
	data, err := os.ReadFile(filepath.Join(partPath, "device", "model"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
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

// humanSize formats bytes to human-readable string.
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
