package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var searchCmd = &cobra.Command{
	Use:   "search [term]",
	Short: "Search Debian pool for packages",
	Long:  "Search configured Debian repositories for packages matching the query.",
	Args:  cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		query := args[0]
		return runSearch(query)
	},
}

func runSearch(query string) error {
	sources, err := pkg.LoadSources("")
	if err != nil {
		return fmt.Errorf("load sources: %w", err)
	}

	var allPkgs []pkg.Package
	for _, src := range sources {
		pkgs, err := pkg.DebianSearch(src, query)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: debian search failed: %v\n", err)
			continue
		}
		allPkgs = append(allPkgs, pkgs...)
	}

	if len(allPkgs) == 0 {
		fmt.Printf("No packages found for '%s'\n", query)
		return nil
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(w, "PACKAGE\tVERSION\tDESCRIPTION\n")
	for _, p := range allPkgs {
		fmt.Fprintf(w, "%s\t%s\t%s\n", p.Name, p.Version, p.Description)
	}
	w.Flush()

	fmt.Printf("\n%d packages found\n", len(allPkgs))
	return nil
}
