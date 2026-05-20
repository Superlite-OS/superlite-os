package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

const installLog = "/tmp/superlite-install.log"

// runInstall executes the full installation pipeline.
// Each phase sends Progress updates to ch. On any error, cleanup runs via defer.
func runInstall(ctx context.Context, disk Disk, ch chan<- Progress) error {
	defer close(ch)

	logFile, err := os.Create(installLog)
	if err != nil {
		return fmt.Errorf("create log: %w", err)
	}
	defer logFile.Close()

	log := func(format string, args ...interface{}) {
		fmt.Fprintf(logFile, format+"\n", args...)
	}

	checkCtx := func() error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			return nil
		}
	}

	// Phase 1: Partition
	if err := phasePartition(disk, ch, log); err != nil {
		return fmt.Errorf("partition: %w", err)
	}
	if err := checkCtx(); err != nil {
		return err
	}

	// Phase 2: Format
	if err := phaseFormat(disk, ch, log); err != nil {
		return fmt.Errorf("format: %w", err)
	}
	if err := checkCtx(); err != nil {
		return err
	}

	// Phase 3: Mount (defer unmount on failure)
	mounts, err := phaseMount(disk, ch, log)
	if err != nil {
		return fmt.Errorf("mount: %w", err)
	}
	defer func() {
		for i := len(mounts) - 1; i >= 0; i-- {
			exec.Command("umount", mounts[i]).Run()
		}
	}()
	if err := checkCtx(); err != nil {
		return err
	}

	// Phase 4: Install system
	if err := phaseSetupDisk(ctx, ch, log); err != nil {
		return fmt.Errorf("setup-disk: %w", err)
	}
	if err := checkCtx(); err != nil {
		return err
	}

	// Phase 5: Copy desktop config
	if err := phaseCopyDesktop(ch, log); err != nil {
		return fmt.Errorf("desktop: %w", err)
	}

	// Phase 6: Bootloader
	if err := phaseBootloader(disk, ch, log); err != nil {
		return fmt.Errorf("bootloader: %w", err)
	}

	ch <- Progress{Percent: 100, Text: "Installation complete!"}
	return nil
}

func phasePartition(disk Disk, ch chan<- Progress, log func(string, ...interface{})) error {
	ch <- Progress{Percent: 5, Text: "Partitioning " + disk.Path + "..."}

	// Wipe
	log("wipefs -a %s", disk.Path)
	exec.Command("wipefs", "-a", disk.Path).Run()

	// GPT label
	log("parted -s %s mklabel gpt", disk.Path)
	if out, err := exec.Command("parted", "-s", disk.Path, "mklabel", "gpt").CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mklabel gpt: %w", err)
	}

	// EFI partition (512 MB)
	log("parted -s %s mkpart ESP fat32 1MiB 513MiB", disk.Path)
	if out, err := exec.Command("parted", "-s", disk.Path, "mkpart", "ESP", "fat32", "1MiB", "513MiB").CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mkpart ESP: %w", err)
	}
	exec.Command("parted", "-s", disk.Path, "set", "1", "esp", "on").Run()

	// Swap partition (size/10, max 2GB)
	sizeMB, _ := DiskSizeMB(disk.Path)
	swapMB := sizeMB / 10
	if swapMB > 2048 {
		swapMB = 2048
	}
	swapEnd := 513 + swapMB
	log("parted -s %s mkpart primary linux-swap 513MiB %dMiB", disk.Path, swapEnd)
	if out, err := exec.Command("parted", "-s", disk.Path, "mkpart", "primary", "linux-swap", "513MiB", fmt.Sprintf("%dMiB", swapEnd)).CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mkpart swap: %w", err)
	}

	// Root partition (remaining)
	log("parted -s %s mkpart primary ext4 %dMiB 100%%", disk.Path, swapEnd)
	if out, err := exec.Command("parted", "-s", disk.Path, "mkpart", "primary", "ext4", fmt.Sprintf("%dMiB", swapEnd), "100%").CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mkpart root: %w", err)
	}

	ch <- Progress{Percent: 25, Text: "Partitioning complete"}
	return nil
}

func phaseFormat(disk Disk, ch chan<- Progress, log func(string, ...interface{})) error {
	ch <- Progress{Percent: 25, Text: "Formatting partitions..."}

	sep := PartitionSeparator(disk.Path)

	// EFI (FAT32)
	efi := disk.Path + sep + "1"
	log("mkfs.fat -F32 %s", efi)
	if out, err := exec.Command("mkfs.fat", "-F32", efi).CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mkfs fat32: %w", err)
	}

	// Swap
	swap := disk.Path + sep + "2"
	log("mkswap %s", swap)
	if out, err := exec.Command("mkswap", swap).CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mkswap: %w", err)
	}

	// Root (ext4)
	root := disk.Path + sep + "3"
	log("mkfs.ext4 -F %s", root)
	if out, err := exec.Command("mkfs.ext4", "-F", root).CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return fmt.Errorf("mkfs ext4: %w", err)
	}

	ch <- Progress{Percent: 40, Text: "Formatting complete"}
	return nil
}

func phaseMount(disk Disk, ch chan<- Progress, log func(string, ...interface{})) ([]string, error) {
	ch <- Progress{Percent: 40, Text: "Mounting partitions..."}

	sep := PartitionSeparator(disk.Path)
	root := disk.Path + sep + "3"
	efi := disk.Path + sep + "1"
	swap := disk.Path + sep + "2"

	var mounts []string

	// Mount root
	log("mount %s /mnt", root)
	if out, err := exec.Command("mount", root, "/mnt").CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return mounts, fmt.Errorf("mount root: %w", err)
	}
	mounts = append(mounts, "/mnt")

	// Mount EFI
	efiDir := "/mnt/boot/efi"
	os.MkdirAll(efiDir, 0755)
	log("mount %s %s", efi, efiDir)
	if out, err := exec.Command("mount", efi, efiDir).CombinedOutput(); err != nil {
		log("ERROR: %s", string(out))
		return mounts, fmt.Errorf("mount efi: %w", err)
	}
	mounts = append(mounts, efiDir)

	// Activate swap
	log("swapon %s", swap)
	exec.Command("swapon", swap).Run()

	ch <- Progress{Percent: 50, Text: "Partitions mounted"}
	return mounts, nil
}

func phaseSetupDisk(ctx context.Context, ch chan<- Progress, log func(string, ...interface{})) error {
	ch <- Progress{Percent: 50, Text: "Installing base system (this may take a few minutes)..."}

	log("setup-disk -m sys /mnt")
	out, err := exec.CommandContext(ctx, "setup-disk", "-m", "sys", "/mnt").CombinedOutput()
	log("%s", string(out))
	if err != nil {
		return fmt.Errorf("setup-disk: %w", err)
	}

	ch <- Progress{Percent: 85, Text: "Base system installed"}
	return nil
}

func phaseCopyDesktop(ch chan<- Progress, log func(string, ...interface{})) error {
	ch <- Progress{Percent: 85, Text: "Installing desktop environment..."}

	// Copy skel dotfiles to installed root
	skelDir := "/etc/skel"
	if _, err := os.Stat(skelDir); err == nil {
		log("Copying skel dotfiles to /mnt/root")
		os.MkdirAll("/mnt/root", 0755)
		copyDir(skelDir, "/mnt/root", log)
	}

	// Copy live session configs (may have runtime changes)
	liveConfig := "/root/.config"
	if _, err := os.Stat(liveConfig); err == nil {
		log("Copying live .config to /mnt/root/.config")
		os.MkdirAll("/mnt/root/.config", 0755)
		copyDir(liveConfig, "/mnt/root/.config", log)
	}

	// Copy wallpapers, icons, fonts
	copyPairs := []struct{ src, dst string }{
		{"/root/Pictures", "/mnt/root/Pictures"},
		{"/root/.icons", "/mnt/root/.icons"},
		{"/usr/share/fonts", "/mnt/usr/share/fonts"},
		{"/usr/share/icons", "/mnt/usr/share/icons"},
	}
	for _, p := range copyPairs {
		if _, err := os.Stat(p.src); err == nil {
			log("cp -a %s %s", p.src, p.dst)
			exec.Command("cp", "-a", p.src, p.dst).Run()
		}
	}

	// Copy MOTD
	exec.Command("cp", "/etc/motd", "/mnt/etc/motd").Run()

	// Fix ownership
	exec.Command("chroot", "/mnt", "chown", "-R", "root:root", "/root").Run()

	ch <- Progress{Percent: 95, Text: "Desktop environment installed"}
	return nil
}

func phaseBootloader(disk Disk, ch chan<- Progress, log func(string, ...interface{})) error {
	ch <- Progress{Percent: 95, Text: "Installing bootloader..."}

	// Mount efivarfs for grub-install
	efivarsDir := "/mnt/sys/firmware/efi/efivars"
	os.MkdirAll(efivarsDir, 0755)
	exec.Command("mount", "-t", "efivarfs", "efivarfs", efivarsDir).Run()
	defer exec.Command("umount", efivarsDir).Run()

	// Try grub-install with fallbacks
	grubOK := false
	attempts := []struct {
		name string
		args []string
	}{
		{"uefi-removable", []string{"chroot", "/mnt", "grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi", "--removable"}},
		{"uefi-superlite", []string{"chroot", "/mnt", "grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi", "--bootloader-id=superlite"}},
		{"bios", []string{"chroot", "/mnt", "grub-install", "--target=i386-pc", disk.Path}},
	}

	for _, a := range attempts {
		log("Trying grub-install: %s", a.name)
		if out, err := exec.Command(a.args[0], a.args[1:]...).CombinedOutput(); err == nil {
			log("grub-install %s: OK", a.name)
			grubOK = true
			break
		} else {
			log("grub-install %s failed: %s", a.name, string(out))
		}
	}

	if !grubOK {
		log("WARNING: All grub-install attempts failed")
	}

	// Ensure fallback boot path
	efiBoot := "/mnt/boot/efi/EFI/BOOT"
	efiSuperlite := "/mnt/boot/efi/EFI/superlite/grubx64.efi"
	if _, err := os.Stat(efiBoot); os.IsNotExist(err) {
		if _, err := os.Stat(efiSuperlite); err == nil {
			os.MkdirAll(efiBoot, 0755)
			exec.Command("cp", efiSuperlite, filepath.Join(efiBoot, "BOOTX64.EFI")).Run()
		}
	}

	// Generate grub config
	log("grub-mkconfig")
	exec.Command("chroot", "/mnt", "grub-mkconfig", "-o", "/boot/grub/grub.cfg").CombinedOutput()

	ch <- Progress{Percent: 100, Text: "Bootloader installed"}
	return nil
}

// copyDir recursively copies src to dst using cp -a.
func copyDir(src, dst string, log func(string, ...interface{})) {
	entries, err := os.ReadDir(src)
	if err != nil {
		return
	}
	for _, entry := range entries {
		name := entry.Name()
		if name == "." || name == ".." {
			continue
		}
		srcPath := filepath.Join(src, name)
		dstPath := filepath.Join(dst, name)
		if err := exec.Command("cp", "-a", srcPath, dstPath).Run(); err != nil {
			log("WARNING: cp %s -> %s: %v", srcPath, dstPath, err)
		}
	}
}

