package pkg

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/ulikunitz/xz"
)

// DebInfo holds .deb package metadata
type DebInfo struct {
	Name        string
	Version     string
	Description string
	Depends     string
	Arch        string
}

// System libraries that should NOT be overwritten
var protectedLibs = []string{
	"/ld-linux", "/ld.so", "/ld-",
	"/libc.so", "/libstdc++", "/libgcc_s.so", "/libm.so",
	"/libpthread.so", "/libdl.so", "/librt.so", "/libresolv.so",
	"/libnss_", "/libutil.so", "/libcrypt.so",
}

// GetDebControl reads only the control metadata from a .deb file
func GetDebControl(path string) (*DebInfo, error) {
	tmpDir, err := os.MkdirTemp("", "zapt-ctrl-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmpDir)

	extractDir := filepath.Join(tmpDir, "extracted")
	if err := os.MkdirAll(extractDir, 0755); err != nil {
		return nil, err
	}
	if err := extractAr(path, extractDir); err != nil {
		return nil, err
	}

	for _, ctar := range []string{"control.tar.gz", "control.tar.xz", "control.tar.zst"} {
		info, err := parseControl(filepath.Join(extractDir, ctar))
		if err == nil {
			return info, nil
		}
	}
	return nil, fmt.Errorf("control file not found in %s", path)
}

// VerifyDeb checks if a file is a valid .deb
func VerifyDeb(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	// Check for ar magic "!<arch>"
	buf := make([]byte, 8)
	if _, err := f.Read(buf); err != nil {
		return fmt.Errorf("read header: %w", err)
	}
	if string(buf[:8]) != "!<arch>\n" {
		return fmt.Errorf("not a valid .deb file (missing ar magic)")
	}

	return nil
}

// ExtractDeb extracts a .deb file and installs it to /
func ExtractDeb(path string) (*DebInfo, error) {
	if err := RequireRoot(); err != nil {
		return nil, err
	}

	// Create temp directory for extraction
	tmpDir, err := os.MkdirTemp("", "zapt-deb-*")
	if err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create backup directory
	backupDir := filepath.Join(tmpDir, "backup")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return nil, fmt.Errorf("create backup dir: %w", err)
	}

	// Extract .deb using ar
	extractDir := filepath.Join(tmpDir, "extracted")
	if err := os.MkdirAll(extractDir, 0755); err != nil {
		return nil, err
	}
	if err := extractAr(path, extractDir); err != nil {
		return nil, fmt.Errorf("extract ar: %w", err)
	}

	// Parse control file
	info, err := parseControl(filepath.Join(extractDir, "control.tar.gz"))
	if err != nil {
		info, err = parseControl(filepath.Join(extractDir, "control.tar.xz"))
		if err != nil {
			info, err = parseControl(filepath.Join(extractDir, "control.tar.zst"))
			if err != nil {
				return nil, fmt.Errorf("parse control: %w", err)
			}
		}
	}

	// Extract data.tar.* to temp dir first (not directly to /)
	dataFile := findDataTar(extractDir)
	if dataFile == "" {
		return nil, fmt.Errorf("data.tar.* not found in .deb")
	}

	dataDir := filepath.Join(tmpDir, "data")
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, err
	}
	if err := extractDataToDir(dataFile, dataDir); err != nil {
		return nil, fmt.Errorf("extract data: %w", err)
	}

	// Install files with safety checks (inspired by sailfish installer)
	fmt.Printf("Installing %s %s...\n", info.Name, info.Version)
	installed, skipped, installedELFs, err := installFilesWithSafety(dataDir, backupDir)
	if err != nil {
		return nil, fmt.Errorf("install files: %w", err)
	}

	fmt.Printf("  Installed: %d files\n", installed)
	if skipped > 0 {
		fmt.Printf("  Skipped:   %d files (protected libs)\n", skipped)
	}

	// Check library dependencies on installed ELF binaries
	fmt.Printf("  Checking library dependencies...\n")
	checkInstalledLibs(installedELFs, "/")

	// Run postinst if exists
	postinst := findScript(extractDir, "postinst")
	if postinst != "" {
		fmt.Printf("  Running postinst: %s\n", postinst)
		if err := exec.Command("sh", postinst, "configure").Run(); err != nil {
			fmt.Fprintf(os.Stderr, "  Warning: postinst failed: %v\n", err)
		}
	}

	// Update library cache
	fmt.Printf("  Updating library cache...\n")
	exec.Command("ldconfig").Run()

	// Register in zapt database
	if err := registerPackage(info); err != nil {
		fmt.Fprintf(os.Stderr, "  Warning: register failed: %v\n", err)
	}

	// Show backup location if any files were backed up
	if entries, _ := os.ReadDir(backupDir); len(entries) > 0 {
		fmt.Printf("  Backup saved to: %s\n", backupDir)
	}

	return info, nil
}

// ExtractDebToRoot extracts a .deb file and installs it to a custom root directory.
// This is useful for installing packages into a chroot or ISO build root.
func ExtractDebToRoot(path, root string) (*DebInfo, error) {
	// Create temp directory for extraction
	tmpDir, err := os.MkdirTemp("", "zapt-deb-*")
	if err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create backup directory
	backupDir := filepath.Join(tmpDir, "backup")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return nil, fmt.Errorf("create backup dir: %w", err)
	}

	// Extract .deb using ar
	extractDir := filepath.Join(tmpDir, "extracted")
	if err := os.MkdirAll(extractDir, 0755); err != nil {
		return nil, err
	}
	if err := extractAr(path, extractDir); err != nil {
		return nil, fmt.Errorf("extract ar: %w", err)
	}

	// Parse control file
	info, err := parseControl(filepath.Join(extractDir, "control.tar.gz"))
	if err != nil {
		info, err = parseControl(filepath.Join(extractDir, "control.tar.xz"))
		if err != nil {
			info, err = parseControl(filepath.Join(extractDir, "control.tar.zst"))
			if err != nil {
				return nil, fmt.Errorf("parse control: %w", err)
			}
		}
	}

	// Extract data.tar.* to temp dir
	dataFile := findDataTar(extractDir)
	if dataFile == "" {
		return nil, fmt.Errorf("data.tar.* not found in .deb")
	}

	dataDir := filepath.Join(tmpDir, "data")
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, err
	}
	if err := extractDataToDir(dataFile, dataDir); err != nil {
		return nil, fmt.Errorf("extract data: %w", err)
	}

	// Install files to custom root
	fmt.Printf("Installing %s %s to %s...\n", info.Name, info.Version, root)
	installed, skipped, installedELFs, err := installFilesToRoot(dataDir, backupDir, root)
	if err != nil {
		return nil, fmt.Errorf("install files: %w", err)
	}

	fmt.Printf("  Installed: %d files\n", installed)
	if skipped > 0 {
		fmt.Printf("  Skipped:   %d files\n", skipped)
	}

	// Check library dependencies on installed ELF binaries
	fmt.Printf("  Checking library dependencies...\n")
	checkInstalledLibs(installedELFs, root)

	// Run postinst if exists (only if installing to /)
	if root == "/" {
		postinst := findScript(extractDir, "postinst")
		if postinst != "" {
			fmt.Printf("  Running postinst: %s\n", postinst)
			if err := exec.Command("sh", postinst, "configure").Run(); err != nil {
				fmt.Fprintf(os.Stderr, "  Warning: postinst failed: %v\n", err)
			}
		}

		// Update library cache
		fmt.Printf("  Updating library cache...\n")
		exec.Command("ldconfig").Run()
	}

	// Register in zapt database (under custom root)
	if err := registerPackageToRoot(info, root); err != nil {
		fmt.Fprintf(os.Stderr, "  Warning: register failed: %v\n", err)
	}

	return info, nil
}

// Allowed destination prefixes for .deb file extraction
var allowedDestPrefixes = []string{
	"/bin/", "/sbin/", "/lib/", "/lib64/", "/libexec/",
	"/usr/", "/etc/", "/opt/", "/share/",
}

// isAllowedDestPath checks if a destination path is within allowed system directories
func isAllowedDestPath(destPath string) bool {
	// Reject path traversal
	if strings.Contains(destPath, "..") {
		return false
	}
	// Must be an absolute path under one of the allowed prefixes
	for _, prefix := range allowedDestPrefixes {
		if strings.HasPrefix(destPath, prefix) || destPath+"/" == prefix {
			return true
		}
	}
	return false
}

// installFilesWithSafety installs files with backup and protection
func installFilesWithSafety(dataDir, backupDir string) (installed, skipped int, installedELFs []string, err error) {
	// Walk the data directory using WalkDir with Lstat for symlink support
	err = filepath.WalkDir(dataDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}

		// Get relative path
		relPath, err := filepath.Rel(dataDir, path)
		if err != nil {
			return err
		}

		// Skip the root directory
		if relPath == "." {
			return nil
		}

		// Map paths: usr/bin → bin, usr/lib → lib, etc.
		destPath := mapDebPath(relPath)

		// Validate destination path (prevent path traversal)
		if !isAllowedDestPath(destPath) {
			fmt.Printf("  SKIP [not allowed]: %s -> %s\n", relPath, destPath)
			skipped++
			return nil
		}

		// Check if this is a protected library
		if isProtectedLib(destPath) {
			fmt.Printf("  SKIP [protected]: %s -> %s\n", relPath, destPath)
			skipped++
			return nil
		}

		// Check if file is owned by apk (prevent conflicts)
		if isOwnedByApk(destPath) {
			fmt.Printf("  SKIP [apk-owned]: %s -> %s\n", relPath, destPath)
			skipped++
			return nil
		}

		// Get info using Lstat (doesn't follow symlinks)
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}

		// Create directories
		if info.IsDir() {
			return os.MkdirAll(destPath, info.Mode())
		}

		// Handle symlinks
		if info.Mode()&os.ModeSymlink != 0 {
			linkTarget, err := os.Readlink(path)
			if err != nil {
				return err
			}

			// For files going to glibcLibDir: fix broken absolute symlinks
			if strings.HasPrefix(destPath, glibcLibDir+"/") {
				// If real file already exists at dest, skip this symlink
				if existing, err := os.Lstat(destPath); err == nil && existing.Mode().IsRegular() {
					installed++
					return nil
				}
				// Absolute symlink pointing outside glibcLibDir → will break in squashfs
				// Resolve: copy the real target file instead of creating a broken symlink
				if filepath.IsAbs(linkTarget) {
					// Try to find the real file in the .deb extraction
					// The target might have been extracted to glibcLibDir with a different name
					// Just create a relative symlink to the basename (same dir)
					relTarget := filepath.Base(linkTarget)
					realTarget := filepath.Join(filepath.Dir(destPath), relTarget)
					if _, err := os.Stat(realTarget); err == nil {
						os.Remove(destPath)
						if err := os.Symlink(relTarget, destPath); err != nil {
							return err
						}
						installed++
						return nil
					}
					// Target doesn't exist yet — skip, will be created when real file is extracted
					installed++
					return nil
				}
			}

			os.Remove(destPath) // Remove existing if any
			if err := os.Symlink(linkTarget, destPath); err != nil {
				return err
			}
			installed++
			return nil
		}

		// Backup existing file
		if _, err := os.Stat(destPath); err == nil {
			backupPath := filepath.Join(backupDir, relPath)
			os.MkdirAll(filepath.Dir(backupPath), 0755)
			os.Rename(destPath, backupPath)
		}

		// Copy file
		if err := copyFileWithMode(path, destPath, info.Mode()); err != nil {
			return err
		}

		// Track ELF files for ldd checking
		if isELF(path) {
			installedELFs = append(installedELFs, destPath)
			// If this is an ELF binary (not a .so), create a glibc wrapper
			if !isSoFile(destPath) && isBinaryPath(destPath) {
				if err := createGlibcWrapper(destPath, "/"); err != nil {
					fmt.Printf("  Warning: could not create wrapper for %s: %v\n", destPath, err)
				}
			}
		}

		installed++
		return nil
	})

	return installed, skipped, installedELFs, err
}

// installFilesToRoot installs files to a custom root directory (e.g., /mnt for ISO builds)
// glibc .so files are redirected to /usr/lib/glibc/ to avoid musl conflicts.
// ELF binaries get wrapper scripts that set LD_LIBRARY_PATH=/usr/lib/glibc.
func installFilesToRoot(dataDir, backupDir, root string) (installed, skipped int, installedELFs []string, err error) {
	// Use WalkDir with Lstat to properly handle symlinks
	err = filepath.WalkDir(dataDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}

		relPath, err := filepath.Rel(dataDir, path)
		if err != nil {
			return err
		}

		if relPath == "." {
			return nil
		}

		// Map paths
		destPath := mapDebPath(relPath)

		// Validate destination path
		if !isAllowedDestPath(destPath) {
			fmt.Printf("  SKIP [not allowed]: %s -> %s\n", relPath, destPath)
			skipped++
			return nil
		}

		// Prepend root
		fullPath := filepath.Join(root, destPath)

		// Get info using Lstat (doesn't follow symlinks)
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}

		// Handle directories
		if info.IsDir() {
			return os.MkdirAll(fullPath, info.Mode())
		}

		// Ensure parent directory exists
		if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
			return err
		}

		// Handle symlinks
		if info.Mode()&os.ModeSymlink != 0 {
			linkTarget, err := os.Readlink(path)
			if err != nil {
				return err
			}
			os.Remove(fullPath) // Remove existing if any
			if err := os.Symlink(linkTarget, fullPath); err != nil {
				return err
			}
			installed++
			return nil
		}

		// Backup existing file
		if _, err := os.Stat(fullPath); err == nil {
			backupPath := filepath.Join(backupDir, relPath)
			os.MkdirAll(filepath.Dir(backupPath), 0755)
			os.Rename(fullPath, backupPath)
		}

		// Copy regular file
		if err := copyFileWithMode(path, fullPath, info.Mode()); err != nil {
			return err
		}

		// Track ELF files for ldd checking
		if isELF(path) {
			installedELFs = append(installedELFs, fullPath)
			// If this is an ELF binary (not a .so), create a glibc wrapper
			if !isSoFile(destPath) && isBinaryPath(destPath) {
				if err := createGlibcWrapper(fullPath, root); err != nil {
					fmt.Printf("  Warning: could not create wrapper for %s: %v\n", destPath, err)
				}
			}
		}

		installed++
		return nil
	})

	return installed, skipped, installedELFs, err
}

// isBinaryPath checks if a path is for executables (bin/sbin directories)
func isBinaryPath(path string) bool {
	return strings.HasPrefix(path, "/bin/") ||
		strings.HasPrefix(path, "/sbin/") ||
		strings.HasPrefix(path, "/usr/bin/") ||
		strings.HasPrefix(path, "/usr/sbin/") ||
		strings.HasPrefix(path, "/usr/libexec/") ||
		strings.HasPrefix(path, "/opt/")
}

// createGlibcWrapper moves a glibc-linked ELF binary to /usr/lib/glibc/bin/
// and creates a shell wrapper at the original location that sets LD_LIBRARY_PATH.
// The wrapper always uses absolute runtime paths (without root prefix) so it
// works correctly when the filesystem is mounted at a different location
// (e.g., modloop squashfs mounted at /.modloop/).
func createGlibcWrapper(binPath, root string) error {
	glibcBin := filepath.Join(root, glibcLibDir, "bin")
	if err := os.MkdirAll(glibcBin, 0755); err != nil {
		return err
	}

	// Move real binary to /usr/lib/glibc/bin/
	binName := filepath.Base(binPath)
	realPath := filepath.Join(glibcBin, binName)
	if err := os.Rename(binPath, realPath); err != nil {
		return err
	}

	// Runtime path: always use absolute path without root prefix
	// At runtime, the binary will be at /usr/lib/glibc/bin/<name> (via bind mount)
	runtimePath := filepath.Join(glibcLibDir, "bin", binName)

	// Create wrapper script at original location
	// Include all possible glibc library paths for robustness
	wrapper := fmt.Sprintf(`#!/bin/sh
export LD_LIBRARY_PATH="%s:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
exec "%s" "$@"
`, glibcLibDir, runtimePath)

	if err := os.WriteFile(binPath, []byte(wrapper), 0755); err != nil {
		return err
	}

	fmt.Printf("  WRAPPER: %s -> %s\n", binPath, runtimePath)
	return nil
}

// mapDebPath maps Debian paths to system paths
// glibcLibDir is where glibc-linked .so files are isolated from musl
const glibcLibDir = "/usr/lib/glibc"

func mapDebPath(relPath string) string {
	// Remove leading ./
	relPath = strings.TrimPrefix(relPath, "./")

	// Map usr/* to root /*
	mappings := map[string]string{
		"usr/bin":     "bin",
		"usr/sbin":    "sbin",
		"usr/lib":     "lib",
		"usr/lib64":   "lib64",
		"usr/libexec": "libexec",
		"usr/include": "include",
		"usr/share":   "share",
		"etc":         "etc",
	}

	for prefix, replacement := range mappings {
		if strings.HasPrefix(relPath, prefix) {
			result := "/" + replacement + relPath[len(prefix):]
			// Redirect .so files to glibc isolation directory
			// This prevents glibc .so from overwriting musl .so in /lib/
			if isSoFile(result) && (strings.HasPrefix(result, "/lib/") || strings.HasPrefix(result, "/lib64/")) {
				return glibcLibDir + "/" + filepath.Base(result)
			}
			return result
		}
	}

	result := "/" + relPath
	// Also redirect .so files that are directly under lib/ (not from usr/lib mapping)
	// e.g. lib/x86_64-linux-gnu/libtinfo.so.6 from some .deb packages
	if isSoFile(result) && (strings.HasPrefix(result, "/lib/") || strings.HasPrefix(result, "/lib64/")) {
		return glibcLibDir + "/" + filepath.Base(result)
	}
	return result
}

// isSoFile checks if a path is a shared library (.so, .so.N, .so.N.N)
func isSoFile(path string) bool {
	base := filepath.Base(path)
	// Match: libc.so.6, libstdc++.so, libpthread-2.36.so, ld-linux-x86-64.so.2
	if strings.Contains(base, ".so") {
		return true
	}
	// Match: ld-linux-x86-64.so.2, ld-musl-x86_64.so.1
	if strings.HasPrefix(base, "ld-") {
		return true
	}
	return false
}

// isProtectedLib checks if a path is a protected system library.
// Paths already redirected to glibcLibDir are NOT protected — they are
// isolated from musl and safe to install.
func isProtectedLib(path string) bool {
	// Allow glibcLibDir — these are isolated from musl system libs
	if strings.HasPrefix(path, glibcLibDir+"/") {
		return false
	}
	for _, lib := range protectedLibs {
		if strings.Contains(path, lib) {
			return true
		}
	}
	return false
}

// isOwnedByApk checks if a file is owned by an Alpine apk package
func isOwnedByApk(path string) bool {
	cmd := exec.Command("apk", "info", "-W", path)
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	// Output format: "<path> is owned by <package>" or error
	return strings.Contains(string(out), "is owned by")
}

// copyFileWithMode copies a file preserving permissions
func copyFileWithMode(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	// Create destination directory
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}

	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

// extractAr extracts an ar archive (.deb file) using pure Go implementation.
// .deb format: "!<arch>\n" header followed by ar entries.
// Each entry: 60-byte header (name16, timestamp12, owner6, group6, mode8, size10, magic2)
// followed by file data padded to 2-byte boundary.
func extractAr(debPath, destDir string) error {
	f, err := os.Open(debPath)
	if err != nil {
		return fmt.Errorf("open deb: %w", err)
	}
	defer f.Close()

	// Read and verify ar magic "!<arch>\n"
	magic := make([]byte, 8)
	if _, err := io.ReadFull(f, magic); err != nil {
		return fmt.Errorf("read ar magic: %w", err)
	}
	if string(magic) != "!<arch>\n" {
		return fmt.Errorf("not a valid ar archive (got %q)", string(magic))
	}

	// Read entries
	for {
		// Read 60-byte header
		header := make([]byte, 60)
		n, err := io.ReadFull(f, header)
		if err != nil {
			if err == io.EOF || n == 0 {
				break
			}
			return fmt.Errorf("read ar header: %w", err)
		}

		// Parse header fields
		name := strings.TrimSpace(string(header[0:16]))
		sizeStr := strings.TrimSpace(string(header[48:58]))

		size, err := strconv.ParseInt(sizeStr, 10, 64)
		if err != nil {
			return fmt.Errorf("parse ar entry size %q: %w", sizeStr, err)
		}

		// Clean up name (remove trailing / if present)
		name = strings.TrimSuffix(name, "/")

		// Read file data
		data := make([]byte, size)
		if _, err := io.ReadFull(f, data); err != nil {
			return fmt.Errorf("read ar entry %q data: %w", name, err)
		}

		// Write to destination
		destPath := filepath.Join(destDir, name)
		if err := os.WriteFile(destPath, data, 0644); err != nil {
			return fmt.Errorf("write ar entry %q: %w", name, err)
		}

		// Skip padding (ar entries are 2-byte aligned)
		if size%2 != 0 {
			f.Seek(1, io.SeekCurrent)
		}
	}

	return nil
}

// extractDataToDir extracts data.tar.* to a specific directory using pure Go
func extractDataToDir(tarPath, destDir string) error {
	f, err := os.Open(tarPath)
	if err != nil {
		return err
	}
	defer f.Close()

	var reader io.Reader = f
	if strings.HasSuffix(tarPath, ".gz") {
		gz, err := gzip.NewReader(f)
		if err != nil {
			return err
		}
		defer gz.Close()
		reader = gz
	} else if strings.HasSuffix(tarPath, ".xz") {
		xzReader, err := xz.NewReader(f)
		if err != nil {
			return err
		}
		reader = xzReader
	} else if strings.HasSuffix(tarPath, ".zst") {
		// Fallback to system tar for zstd
		cmd := exec.Command("tar", "--zstd", "xf", "-", "-C", destDir)
		cmd.Stdin = f
		return cmd.Run()
	}

	// First pass: extract all entries
	type pendingLink struct {
		dest   string
		target string
		isHard bool
	}
	var links []pendingLink

	tr := tar.NewReader(reader)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		// Clean up name (remove leading ./)
		name := strings.TrimPrefix(hdr.Name, "./")
		name = strings.TrimPrefix(hdr.Name, "/")
		if name == "" {
			continue
		}

		destPath := filepath.Join(destDir, name)

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(destPath, os.FileMode(hdr.Mode)); err != nil {
				return err
			}
		case tar.TypeReg:
			// Ensure parent directory exists
			if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
				return err
			}
			// Extract file
			outFile, err := os.OpenFile(destPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, os.FileMode(hdr.Mode))
			if err != nil {
				return err
			}
			if _, err := io.Copy(outFile, tr); err != nil {
				outFile.Close()
				return err
			}
			outFile.Close()
		case tar.TypeSymlink:
			// Defer symlink creation (target might not exist yet)
			links = append(links, pendingLink{
				dest:   destPath,
				target: hdr.Linkname,
				isHard: false,
			})
		case tar.TypeLink:
			// Defer hard link creation
			linkTarget := filepath.Join(destDir, strings.TrimPrefix(hdr.Linkname, "./"))
			linkTarget = filepath.Join(destDir, strings.TrimPrefix(hdr.Linkname, "/"))
			links = append(links, pendingLink{
				dest:   destPath,
				target: linkTarget,
				isHard: true,
			})
		}
	}

	// Second pass: create symlinks and hard links
	for _, link := range links {
		// Ensure parent directory exists
		if err := os.MkdirAll(filepath.Dir(link.dest), 0755); err != nil {
			return err
		}
		os.Remove(link.dest) // Remove existing if any

		if link.isHard {
			if err := os.Link(link.target, link.dest); err != nil {
				// Hard link might fail if target doesn't exist, skip
				fmt.Fprintf(os.Stderr, "  Warning: hard link %s -> %s: %v\n", link.dest, link.target, err)
			}
		} else {
			if err := os.Symlink(link.target, link.dest); err != nil {
				fmt.Fprintf(os.Stderr, "  Warning: symlink %s -> %s: %v\n", link.dest, link.target, err)
			}
		}
	}

	return nil
}

// findScript finds a script in the control archive
func findScript(dir, name string) string {
	// Look in common locations
	locations := []string{
		filepath.Join(dir, name),
		filepath.Join(dir, "control", name),
		filepath.Join(dir, "scripts", name),
	}

	for _, loc := range locations {
		if _, err := os.Stat(loc); err == nil {
			return loc
		}
	}
	return ""
}

// parseControl parses the control.tar.* to get package info
func parseControl(tarPath string) (*DebInfo, error) {
	f, err := os.Open(tarPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var reader io.Reader = f
	if strings.HasSuffix(tarPath, ".gz") {
		gz, err := gzip.NewReader(f)
		if err != nil {
			return nil, err
		}
		defer gz.Close()
		reader = gz
	} else if strings.HasSuffix(tarPath, ".xz") {
		xzReader, err := xz.NewReader(f)
		if err != nil {
			return nil, err
		}
		reader = xzReader
	}

	tr := tar.NewReader(reader)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		if hdr.Name == "./control" || hdr.Name == "control" {
			data, err := io.ReadAll(tr)
			if err != nil {
				return nil, err
			}
			return parseControlData(string(data)), nil
		}
	}

	return nil, fmt.Errorf("control file not found")
}

// parseControlData parses control file content
func parseControlData(data string) *DebInfo {
	info := &DebInfo{}
	for _, line := range strings.Split(data, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Package:") {
			info.Name = strings.TrimSpace(strings.TrimPrefix(line, "Package:"))
		} else if strings.HasPrefix(line, "Version:") {
			info.Version = strings.TrimSpace(strings.TrimPrefix(line, "Version:"))
		} else if strings.HasPrefix(line, "Description:") {
			info.Description = strings.TrimSpace(strings.TrimPrefix(line, "Description:"))
		} else if strings.HasPrefix(line, "Depends:") {
			info.Depends = strings.TrimSpace(strings.TrimPrefix(line, "Depends:"))
		} else if strings.HasPrefix(line, "Architecture:") {
			info.Arch = strings.TrimSpace(strings.TrimPrefix(line, "Architecture:"))
		}
	}
	return info
}

// findDataTar finds the data.tar.* file
func findDataTar(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "data.tar") {
			return filepath.Join(dir, e.Name())
		}
	}
	return ""
}

// registerPackage registers a .deb package in zapt database
func registerPackage(info *DebInfo) error {
	return registerPackageToRoot(info, "/")
}

// registerPackageToRoot registers a .deb package in zapt database under a custom root
func registerPackageToRoot(info *DebInfo, root string) error {
	dbDir := filepath.Join(root, "var/lib/zapt/installed")
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		return err
	}

	// Write package info
	pkgFile := filepath.Join(dbDir, info.Name)
	content := fmt.Sprintf("Package: %s\nVersion: %s\nArchitecture: %s\nDescription: %s\n",
		info.Name, info.Version, info.Arch, info.Description)
	return os.WriteFile(pkgFile, []byte(content), 0644)
}

// isELF checks if a file is an ELF binary by reading magic bytes
func isELF(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	magic := make([]byte, 4)
	n, err := f.Read(magic)
	return err == nil && n == 4 && string(magic) == "\x7fELF"
}

// checkInstalledLibs runs ldd on installed ELF files and reports missing libraries.
// If root is not "/", LD_LIBRARY_PATH is set to include the root's lib directories.
func checkInstalledLibs(elfFiles []string, root string) {
	if len(elfFiles) == 0 {
		return
	}

	// Build LD_LIBRARY_PATH for custom root
	env := os.Environ()
	if root != "/" {
		libPaths := []string{
			filepath.Join(root, "lib"),
			filepath.Join(root, "usr/lib"),
			filepath.Join(root, "lib/x86_64-linux-gnu"),
			filepath.Join(root, "usr/lib/x86_64-linux-gnu"),
		}
		existing := os.Getenv("LD_LIBRARY_PATH")
		if existing != "" {
			libPaths = append(libPaths, existing)
		}
		env = append(env, "LD_LIBRARY_PATH="+strings.Join(libPaths, ":"))
	}

	allOK := true
	missingByFile := make(map[string][]string) // file -> missing libs
	missingPkgs := make(map[string]bool)       // unique lib base names

	for _, f := range elfFiles {
		cmd := exec.Command("ldd", f)
		cmd.Env = env
		out, err := cmd.CombinedOutput()
		if err != nil {
			// Static binary or can't analyze — not an error
			continue
		}
		var missing []string
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if strings.Contains(line, "not found") {
				parts := strings.Fields(line)
				if len(parts) > 0 {
					lib := parts[0]
					missing = append(missing, lib)
					base := lib
					if idx := strings.Index(base, ".so"); idx > 0 {
						base = base[:idx]
					}
					missingPkgs[base] = true
				}
			}
		}
		if len(missing) > 0 {
			allOK = false
			missingByFile[f] = missing
		}
	}

	if allOK {
		fmt.Printf("  All libraries satisfied\n")
		return
	}

	// Report per-file missing libs
	for f, libs := range missingByFile {
		// Show path relative to root for readability
		display := f
		if root != "/" && strings.HasPrefix(f, root) {
			display = f[len(root):]
		}
		fmt.Printf("  MISSING in %s: %s\n", display, strings.Join(libs, ", "))
	}

	// Report missing library groups
	if len(missingPkgs) > 0 {
		fmt.Printf("  Found %d missing library groups\n", len(missingPkgs))
	}
}

