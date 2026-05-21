package pkg

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

const (
	DefaultConfig = "/etc/zapt/sources.conf"
)

// Source represents a Debian package source
type Source struct {
	URL  string // e.g. deb.debian.org
	Dist string // e.g. bookworm, stable
	Comp string // e.g. main, contrib, non-free
	Name string
}

// LoadSources reads sources from config file
func LoadSources(path string) ([]Source, error) {
	if path == "" {
		path = DefaultConfig
	}

	// If config doesn't exist, return default Debian bookworm sources
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return DefaultSources(), nil
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open sources: %w", err)
	}
	defer f.Close()

	var sources []Source
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		s := parseSourceLine(line)
		if s != nil {
			sources = append(sources, *s)
		}
	}

	if len(sources) == 0 {
		return DefaultSources(), nil
	}
	return sources, nil
}

// DefaultSources returns Debian Bookworm sources
func DefaultSources() []Source {
	return []Source{
		{URL: "deb.debian.org", Dist: "bookworm", Comp: "main"},
		{URL: "deb.debian.org", Dist: "bookworm", Comp: "contrib"},
	}
}

func parseSourceLine(line string) *Source {
	// Format: deb.debian.org bookworm main
	parts := strings.Fields(line)
	if len(parts) >= 2 {
		s := &Source{URL: parts[0], Dist: parts[1]}
		if len(parts) >= 3 {
			s.Comp = parts[2]
		} else {
			s.Comp = "main"
		}
		return s
	}
	return nil
}
