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

// VirtualPackages maps virtual package names to their real providers.
// Used when dependency resolution encounters names like "zlib1g" or "perl:any".
var VirtualPackages = map[string]string{
	"zlib1g":                   "zlib1g",
	"default-dbus-session-bus": "dbus",
	"default-dbus-system-bus":  "dbus",
	"perl:any":                 "perl-base",
	"perl":                     "perl-base",
	"libssl3":                  "libssl3",
	"libffi8":                  "libffi8",
	"libglib2.0-0":            "libglib2.0-0",
	"libpcre2-8-0":            "libpcre2-8-0",
	"libselinux1":             "libselinux1",
	"libmount1":               "libmount1",
	"libblkid1":               "libblkid1",
	"libuuid1":                "libuuid1",
	"libffi7":                 "libffi8",       // version upgrade
	"libpcre3":                "libpcre2-8-0",  // pcre -> pcre2
	"libcrypt1":               "libcrypt1",
	"libstdc++6":              "libstdc++6",
	"libgcc-s1":               "libgcc-s1",
	"libwayland-server0":      "libwayland-server0",
	"libwayland-client0":      "libwayland-client0",
	"shared-mime-info":        "shared-mime-info",
	"libtiff6":                "libtiff6",
	"default-libmysqlclient-dev": "default-libmysqlclient-dev",
	"libcrypt-dev":            "libcrypt-dev",
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
		"libc6":             "libc.so",
		"libstdc++6":        "libstdc++.so",
		"libgcc-s1":         "libgcc_s.so",
		"libglib2.0-0":      "libglib-2.0.so",
		"libx11-6":          "libX11.so",
		"libz1":             "libz.so",
		"libpcre3":          "libpcre.so",
		"libsystemd0":       "libsystemd.so",
		"liblzma5":          "liblzma.so",
		"liblz4-1":          "liblz4.so",
		"libhwy1":           "libhwy.so",
		"libdbus-1-3":       "libdbus-1.so",
		"libgmp10":          "libgmp.so",
		"libgnutls30":       "libgnutls.so",
		"libhogweed6":       "libhogweed.so",
		"nettle":            "libnettle.so",
		"libffi8":           "libffi.so",
		"libpcre2-8-0":      "libpcre2-8.so",
		"libselinux1":       "libselinux.so",
		"libmount1":         "libmount.so",
		"libblkid1":         "libblkid.so",
		"libuuid1":          "libuuid.so",
		"zlib1g":            "libz.so",
		"libexpat1":         "libexpat.so",
		"libxml2":           "libxml2.so",
		"libxcb1":           "libxcb.so",
		"libxau6":           "libXau.so",
		"libxdmcp6":         "libXdmcp.so",
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
