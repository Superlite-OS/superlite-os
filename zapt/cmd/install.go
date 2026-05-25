package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var installRoot string
var allowProtected bool

var installCmd = &cobra.Command{
	Use:   "install [package or .deb file]",
	Short: "Install a package by name, .deb file, or URL",
	Long: `Install a package by name from the Debian pool, or from a .deb file/URL.
Dependencies listed in the package's Depends field are automatically
resolved and installed from the Debian pool.

Examples:
  zapt install htop
  zapt install firefox-esr
  zapt install ./package.deb
  zapt install https://example.com/package.deb
  zapt install --root /mnt htop`,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		visited := make(map[string]bool)
		for _, arg := range args {
			if err := installPackage(arg, visited); err != nil {
				return err
			}
		}
		return nil
	},
}

func init() {
	installCmd.Flags().StringVar(&installRoot, "root", "/", "Install root directory (default: /)")
}

func installPackage(target string, visited map[string]bool) error {
	// Download if URL
	if strings.HasPrefix(target, "http://") || strings.HasPrefix(target, "https://") {
		fmt.Printf("Downloading %s...\n", target)
		localPath, err := pkg.DownloadFile(target)
		if err != nil {
			return fmt.Errorf("download: %w", err)
		}
		defer os.Remove(localPath)
		target = localPath
	}

	// If not a .deb file, treat as package name → search Debian pool
	if !strings.HasSuffix(target, ".deb") {
		localPath, err := resolvePackageName(target)
		if err != nil {
			return fmt.Errorf("resolve package '%s': %w", target, err)
		}
		defer os.Remove(localPath)
		target = localPath
	}

	// Verify .deb file
	if err := pkg.VerifyDeb(target); err != nil {
		return fmt.Errorf("invalid .deb file: %w", err)
	}

	// Get package info first to resolve deps
	controlInfo, err := pkg.GetDebControl(target)
	if err != nil {
		return fmt.Errorf("read control: %w", err)
	}

	// Mark as visited to avoid cycles
	visited[controlInfo.Name] = true

	// Resolve and install dependencies first
	if controlInfo.Depends != "" {
		deps := pkg.ParseDepends(controlInfo.Depends)
		for _, dep := range deps {
			if visited[dep] {
				continue
			}
			if pkg.IsPackageInstalled(dep, installRoot) {
				continue
			}
			fmt.Printf("Resolving dependency: %s\n", dep)
			if err := resolveDep(dep, visited); err != nil {
				fmt.Fprintf(os.Stderr, "  Warning: could not install dependency %s: %v\n", dep, err)
			}
		}
	}

	// Extract and install
	fmt.Printf("Installing %s...\n", target)
	info, err := pkg.ExtractDebToRoot(target, installRoot)
	if err != nil {
		return fmt.Errorf("extract .deb: %w", err)
	}

	fmt.Printf("Installed %s %s\n", info.Name, info.Version)
	return nil
}

// resolvePackageName searches Debian pool for a package name and downloads its .deb file.
func resolvePackageName(name string) (string, error) {
	sources, err := pkg.LoadSources("")
	if err != nil {
		return "", err
	}

	for _, src := range sources {
		pkgs, err := pkg.DebianSearch(src, name)
		if err != nil {
			continue
		}
		// Find exact name match
		for _, p := range pkgs {
			if p.Name == name && p.Filename != "" {
				debURL := fmt.Sprintf("https://deb.debian.org/debian/%s", p.Filename)
				fmt.Printf("Found %s %s in Debian pool, downloading...\n", p.Name, p.Version)
				localPath, err := pkg.DownloadFile(debURL)
				if err != nil {
					return "", fmt.Errorf("download %s: %w", name, err)
				}
				return localPath, nil
			}
		}
	}
	return "", fmt.Errorf("package '%s' not found in Debian pool", name)
}

func resolveDep(depName string, visited map[string]bool) error {
	if visited[depName] {
		return nil
	}

	// Search Debian pool for the dependency
	sources, err := pkg.LoadSources("")
	if err != nil {
		return err
	}

	for _, src := range sources {
		pkgs, err := pkg.DebianSearch(src, depName)
		if err != nil {
			continue
		}
		// Find exact name match
		for _, p := range pkgs {
			if p.Name == depName && p.Filename != "" {
				// Download the .deb
				debURL := fmt.Sprintf("https://deb.debian.org/debian/%s", p.Filename)
				fmt.Printf("  Downloading %s from Debian pool...\n", depName)
				localPath, err := pkg.DownloadFile(debURL)
				if err != nil {
					return fmt.Errorf("download %s: %w", depName, err)
				}
				defer os.Remove(localPath)

				// Install recursively (this will resolve its own deps)
				return installPackage(localPath, visited)
			}
		}
	}
	return fmt.Errorf("package %s not found in Debian pool", depName)
}

// InstallFromFile installs a .deb file from a local path (used by desktop entry handler)
func InstallFromFile(path string) error {
	visited := make(map[string]bool)
	return installPackage(path, visited)
}

// InstallFromURL downloads and installs a .deb from URL
func InstallFromURL(url string) error {
	visited := make(map[string]bool)
	return installPackage(url, visited)
}

// InstallDeb installs a .deb to a specific root (for ISO build)
func InstallDeb(debPath, root string) error {
	if err := pkg.VerifyDeb(debPath); err != nil {
		return err
	}
	info, err := pkg.ExtractDebToRoot(debPath, root)
	if err != nil {
		return err
	}
	fmt.Printf("Installed %s %s to %s\n", info.Name, info.Version, root)
	return nil
}

// InstallDebsInDir installs all .deb files in a directory
func InstallDebsInDir(dir, root string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	var debs []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".deb") {
			debs = append(debs, filepath.Join(dir, e.Name()))
		}
	}
	if len(debs) == 0 {
		return fmt.Errorf("no .deb files found in %s", dir)
	}
	visited := make(map[string]bool)
	for _, deb := range debs {
		if err := installPackage(deb, visited); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: %v\n", err)
		}
	}
	return nil
}
