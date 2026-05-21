package pkg

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	dbDir = "/var/lib/zapt/installed"
)

// InstalledPackage represents a package installed via zapt
type InstalledPackage struct {
	Name        string
	Version     string
	Arch        string
	Description string
}

// ListInstalled returns all packages installed via zapt
func ListInstalled() ([]InstalledPackage, error) {
	entries, err := os.ReadDir(dbDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read db: %w", err)
	}

	var pkgs []InstalledPackage
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		p, err := readPackageEntry(filepath.Join(dbDir, e.Name()))
		if err != nil {
			continue
		}
		pkgs = append(pkgs, *p)
	}
	return pkgs, nil
}

// GetPackageInfo returns info about an installed package
func GetPackageInfo(name string) (*InstalledPackage, error) {
	if err := ValidatePackageName(name); err != nil {
		return nil, err
	}
	path := filepath.Join(dbDir, name)
	p, err := readPackageEntry(path)
	if err != nil {
		return nil, fmt.Errorf("package %q not installed via zapt", name)
	}
	return p, nil
}

// RemovePackage removes a package installed via zapt
func RemovePackage(name string) error {
	if err := ValidatePackageName(name); err != nil {
		return err
	}
	path := filepath.Join(dbDir, name)
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("package %q not installed via zapt", name)
	}

	// Read package info to know what files to remove
	p, err := readPackageEntry(path)
	if err != nil {
		return fmt.Errorf("read package entry: %w", err)
	}

	// Remove files listed in the package manifest
	// For now, just remove the db entry (files are tracked separately)
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove package entry: %w", err)
	}

	fmt.Printf("Removed %s %s\n", p.Name, p.Version)
	return nil
}

// ParseDepends parses a Debian Depends field into package names.
// Format: "libc6 (>= 2.17), libgcc-s1, libstdc++6 | libstdc++6-11"
func ParseDepends(depends string) []string {
	if depends == "" {
		return nil
	}
	var deps []string
	for _, group := range strings.Split(depends, ",") {
		group = strings.TrimSpace(group)
		if group == "" {
			continue
		}
		// Handle alternatives: pick first name (strip version constraints)
		alt := strings.Split(group, "|")
		name := strings.TrimSpace(alt[0])
		// Strip version constraint: "libc6 (>= 2.17)" -> "libc6"
		if idx := strings.Index(name, "("); idx > 0 {
			name = strings.TrimSpace(name[:idx])
		}
		if name != "" {
			deps = append(deps, name)
		}
	}
	return deps
}

// IsPackageInstalled checks if a package is installed (in zapt db or as system lib)
func IsPackageInstalled(name, root string) bool {
	if root == "" {
		root = "/"
	}
	// Check zapt database
	dbPath := filepath.Join(root, "var/lib/zapt/installed", name)
	if _, err := os.Stat(dbPath); err == nil {
		return true
	}
	// Check if it's a virtual package provided by another (e.g. libc6 provided by musl on Alpine)
	// Check common library patterns
	libPaths := []string{
		filepath.Join(root, "lib"),
		filepath.Join(root, "usr/lib"),
		filepath.Join(root, "usr/lib/x86_64-linux-gnu"),
		filepath.Join(root, "lib/x86_64-linux-gnu"),
		filepath.Join(root, "usr/lib/glibc"),
	}
	// Map common package names to library soname patterns
	libPatterns := map[string]string{
		"libc6":         "libc.so",
		"libstdc++6":    "libstdc++.so",
		"libgcc-s1":     "libgcc_s.so",
		"libglib2.0-0":  "libglib-2.0.so",
		"libx11-6":      "libX11.so",
		"libz1":         "libz.so",
		"libpcre3":      "libpcre.so",
	}
	if pattern, ok := libPatterns[name]; ok {
		for _, dir := range libPaths {
			entries, err := os.ReadDir(dir)
			if err != nil {
				continue
			}
			for _, e := range entries {
				if strings.Contains(e.Name(), pattern) {
					return true
				}
			}
		}
	}
	return false
}

func readPackageEntry(path string) (*InstalledPackage, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	p := &InstalledPackage{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		parts := strings.SplitN(line, ": ", 2)
		if len(parts) != 2 {
			continue
		}
		switch parts[0] {
		case "Package":
			p.Name = parts[1]
		case "Version":
			p.Version = parts[1]
		case "Architecture":
			p.Arch = parts[1]
		case "Description":
			p.Description = parts[1]
		}
	}
	if p.Name == "" {
		return nil, fmt.Errorf("invalid package entry")
	}
	return p, nil
}
