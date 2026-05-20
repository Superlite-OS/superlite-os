package main

// Progress represents a single progress update from the install goroutine.
type Progress struct {
	Percent int
	Text    string
}
