package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List installed .deb packages",
	Long:  "List packages installed via zapt",
	RunE: func(cmd *cobra.Command, args []string) error {
		return listInstalled()
	},
}

func listInstalled() error {
	pkgs, err := pkg.ListInstalled()
	if err != nil {
		return err
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(w, "PACKAGE\tVERSION\tARCH\n")
	for _, p := range pkgs {
		fmt.Fprintf(w, "%s\t%s\t%s\n", p.Name, p.Version, p.Arch)
	}
	w.Flush()

	fmt.Printf("\n%d packages installed\n", len(pkgs))
	return nil
}
