package cmd

import (
	"github.com/spf13/cobra"
)

var version = "dev"

func SetVersion(v string) {
	version = v
}

var rootCmd = &cobra.Command{
	Use:   "zapt",
	Short: "Debian package manager for SuperLite OS",
	Long: `zapt is a lightweight .deb package manager for Alpine-based SuperLite OS.
It installs .deb files from local paths, URLs, or Debian pool repositories.`,
	Version: version,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.AddCommand(installCmd)
	rootCmd.AddCommand(removeCmd)
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(infoCmd)
	rootCmd.AddCommand(searchCmd)
}
