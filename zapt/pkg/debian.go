package pkg

import (
	"bufio"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Supported architectures (amd64 + all for fast search)
var DebianArchitectures = []string{
	"amd64",
	"all",
}

// DebianSearch searches Debian package repositories
func DebianSearch(src Source, query string) ([]Package, error) {
	if src.Dist == "" {
		src.Dist = "bookworm"
	}
	if src.Comp == "" {
		src.Comp = "main"
	}

	var allPkgs []Package

	// Search across multiple architectures
	for _, arch := range DebianArchitectures {
		url := fmt.Sprintf("https://%s/debian/dists/%s/%s/binary-%s/Packages.gz", src.URL, src.Dist, src.Comp, arch)

		pkgs, err := searchDebianURL(url, query, arch)
		if err != nil {
			// Silently skip failed architectures
			continue
		}
		allPkgs = append(allPkgs, pkgs...)
	}

	return allPkgs, nil
}

// searchDebianURL searches a specific Debian Packages.gz URL
func searchDebianURL(url, query, arch string) ([]Package, error) {
	resp, err := HTTPClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http status: %d", resp.StatusCode)
	}

	gz, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	return parsePackagesIndex(gz, query, "debian")
}

// parsePackagesIndex parses a Debian Packages index
func parsePackagesIndex(r io.Reader, query string, source string) ([]Package, error) {
	var pkgs []Package
	scanner := bufio.NewScanner(r)

	var currentPkg Package
	inPackage := false

	for scanner.Scan() {
		line := scanner.Text()

		if line == "" {
			if inPackage && matchesQuery(currentPkg.Name, currentPkg.Description, query) {
				currentPkg.Source = source
				pkgs = append(pkgs, currentPkg)
			}
			currentPkg = Package{}
			inPackage = false
			continue
		}

		if strings.HasPrefix(line, " ") {
			continue
		}

		parts := strings.SplitN(line, ": ", 2)
		if len(parts) != 2 {
			continue
		}

		key, value := parts[0], parts[1]
		switch key {
		case "Package":
			currentPkg.Name = value
			inPackage = true
		case "Version":
			currentPkg.Version = value
		case "Description":
			currentPkg.Description = value
		case "Filename":
			currentPkg.Filename = value
		case "Architecture":
			// Store arch info if needed
		}
	}

	if inPackage && matchesQuery(currentPkg.Name, currentPkg.Description, query) {
		currentPkg.Source = source
		pkgs = append(pkgs, currentPkg)
	}

	return pkgs, nil
}

// matchesQuery checks if name or description matches query
func matchesQuery(name, desc, query string) bool {
	q := strings.ToLower(query)
	return strings.Contains(strings.ToLower(name), q) ||
		strings.Contains(strings.ToLower(desc), q)
}
