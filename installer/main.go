package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
)

var version = "dev"

func main() {
	log.SetPrefix("[installer] ")
	log.SetFlags(0)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	step := StepWelcome
	var selectedDisk *Disk
	exitCode := 0
	done := false

	for !done {
		switch step {
		case StepWelcome:
			if !YadWelcome() {
				done = true
			} else {
				step = StepSelectDisk
			}

		case StepSelectDisk:
			disks, err := ListDisks()
			if err != nil {
				log.Printf("Error listing disks: %v", err)
			}

			result, err := YadSelectDisk(disks)
			if err != nil {
				exitCode = 1
				done = true
				break
			}

			switch result {
			case "":
				// No radio button selected — show warning, stay on step
				YadNoDiskSelected()
			case "cancel":
				// User clicked Cancel or closed window
				done = true
			case "back":
				step = StepWelcome
			default:
				// Find the selected disk
				for _, d := range disks {
					if d.Path == result {
						selectedDisk = &d
						break
					}
				}
				if selectedDisk == nil {
					YadNoDiskSelected()
				} else {
					step = StepConfirm
				}
			}

		case StepConfirm:
			if selectedDisk == nil {
				step = StepSelectDisk
				continue
			}

			proceed, goBack := YadConfirm(*selectedDisk)
			if goBack {
				step = StepSelectDisk
				selectedDisk = nil
			} else if !proceed {
				done = true
			} else {
				step = StepInstalling
			}

		case StepInstalling:
			if selectedDisk == nil {
				step = StepSelectDisk
				continue
			}

			ch := make(chan Progress, 10)
			errCh := make(chan error, 1)

			go func() {
				errCh <- runInstall(ctx, *selectedDisk, ch)
			}()

			rc := YadProgress(*selectedDisk, ch)
			installErr := <-errCh

			if rc == 1 {
				// User cancelled — stop install gracefully
				cancel()
				done = true
			} else if installErr != nil {
				log.Printf("Installation failed: %v", installErr)
				YadInstallFailed(installLog)
				exitCode = 1
				done = true
			} else {
				step = StepDone
			}

		case StepDone:
			if selectedDisk == nil {
				done = true
				break
			}

			if YadDone(*selectedDisk) {
				if err := exec.Command("reboot").Run(); err != nil {
					log.Printf("reboot failed: %v", err)
				}
			}
			done = true

		default:
			fmt.Fprintf(os.Stderr, "Unknown step: %d\n", step)
			exitCode = 1
			done = true
		}
	}

	os.Exit(exitCode)
}
