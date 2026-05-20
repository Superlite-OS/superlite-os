package pkg

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"time"
)

// HTTPClient is the shared HTTP client with timeouts
var HTTPClient = &http.Client{
	Timeout: 30 * time.Second,
}

// RunCommand runs a command and returns its output
func RunCommand(name string, args ...string) ([]byte, error) {
	cmd := exec.Command(name, args...)
	return cmd.Output()
}

// DownloadFile downloads a URL to a temporary file
func DownloadFile(url string) (string, error) {
	resp, err := HTTPClient.Get(url)
	if err != nil {
		return "", fmt.Errorf("http get: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("http get: status %d", resp.StatusCode)
	}

	// Create temp file
	tmp, err := os.CreateTemp("", "zapt-*.deb")
	if err != nil {
		return "", fmt.Errorf("create temp: %w", err)
	}
	defer tmp.Close()

	// Copy response body to file (max 500MB)
	maxSize := int64(500 * 1024 * 1024)
	if _, err := io.Copy(tmp, io.LimitReader(resp.Body, maxSize)); err != nil {
		os.Remove(tmp.Name())
		return "", fmt.Errorf("download: %w", err)
	}

	return tmp.Name(), nil
}

// IsRoot checks if running as root
func IsRoot() bool {
	return os.Geteuid() == 0
}

// RequireRoot exits if not root
func RequireRoot() error {
	if !IsRoot() {
		return fmt.Errorf("this operation requires root privileges")
	}
	return nil
}
