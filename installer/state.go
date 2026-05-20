package main

// Step represents a wizard step in the installer.
type Step int

const (
	StepWelcome     Step = iota // Welcome screen
	StepSelectDisk              // Disk selection
	StepConfirm                 // Installation confirmation
	StepInstalling              // Installation in progress
	StepDone                    // Installation complete
)

// String returns the human-readable name of a step.
func (s Step) String() string {
	switch s {
	case StepWelcome:
		return "Welcome"
	case StepSelectDisk:
		return "Select Disk"
	case StepConfirm:
		return "Confirm"
	case StepInstalling:
		return "Installing"
	case StepDone:
		return "Done"
	default:
		return "Unknown"
	}
}
