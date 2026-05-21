package pkg

import (
	"fmt"
	"regexp"
)

// Package represents a searchable package from Debian pool
type Package struct {
	Name        string
	Version     string
	Description string
	Filename    string // Pool path from Packages.gz
	Source      string
	Size        int64
	Installed   bool
}

// validPackageName matches safe package names: alphanumeric, hyphens, dots, plus, underscores
var validPackageName = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._+\-]*$`)

// ValidatePackageName checks if a package name is safe to pass to exec.Command
func ValidatePackageName(name string) error {
	if name == "" {
		return fmt.Errorf("package name is empty")
	}
	if len(name) > 256 {
		return fmt.Errorf("package name too long: %d chars", len(name))
	}
	if !validPackageName.MatchString(name) {
		return fmt.Errorf("invalid package name: %q (contains unsafe characters)", name)
	}
	return nil
}
