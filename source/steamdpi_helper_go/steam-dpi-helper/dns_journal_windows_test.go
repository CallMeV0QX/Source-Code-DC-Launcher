package main

import (
	"golang.org/x/sys/windows"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestJournalReplacementAndRemovalSurviveTransientReaderLocks(t *testing.T) {
	directory := t.TempDir()
	target, replacement := filepath.Join(directory, "session.json"), filepath.Join(directory, "replacement.json")
	if err := os.WriteFile(target, []byte("before"), 0600); err != nil {
		t.Fatal(err)
	}
	reader, err := openDNSJournal(target)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	if err := os.WriteFile(replacement, []byte("after"), 0600); err != nil {
		t.Fatal(err)
	}
	from, _ := windows.UTF16PtrFromString(replacement)
	to, _ := windows.UTF16PtrFromString(target)
	previous, err := io.ReadAll(reader)
	if err != nil || string(previous) != "before" {
		t.Fatal("opened journal snapshot changed")
	}
	released := make(chan struct{})
	go func() { time.Sleep(40 * time.Millisecond); reader.Close(); close(released) }()
	if err := replaceDNSFile(from, to); err != nil {
		<-released
		t.Fatal("guardian read blocked journal replacement:", err)
	}
	<-released
	current, err := openDNSJournal(target)
	if err != nil {
		t.Fatal(err)
	}
	defer current.Close()
	next, err := io.ReadAll(current)
	if err != nil || string(next) != "after" {
		t.Fatal("replacement snapshot was not retained")
	}
	released = make(chan struct{})
	go func() { time.Sleep(40 * time.Millisecond); current.Close(); close(released) }()
	if err := (dnsJournalStore{directory}).Delete(); err != nil {
		<-released
		t.Fatal("guardian read blocked cleanup:", err)
	}
	<-released
}
