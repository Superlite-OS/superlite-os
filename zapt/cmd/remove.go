package cmd

import (
	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var removeCmd = &cobra.Command{
	Use:     "remove [package]",
	Short:   "Remove an installed .deb package",
	Aliases: []string{"uninstall", "del"},
	Args:    cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		for _, name := range args {
			if err := pkg.RemovePackage(name); err != nil {
				return err
			}
		}
		return nil
	},
}
