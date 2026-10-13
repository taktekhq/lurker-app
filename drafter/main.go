// Command drafter polls the lurker-app worker for shared photos and turns
// each one into Reddit post drafts using the claude CLI. See SPEC.md at
// the repo root and README.md in this folder for setup.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

const pollInterval = 30 * time.Second

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}
	command := os.Args[1]

	fs := flag.NewFlagSet(command, flag.ExitOnError)
	configPath := fs.String("config", defaultConfigPath(), "path to config.json")
	if err := fs.Parse(os.Args[2:]); err != nil {
		os.Exit(1)
	}

	cfg, err := LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	token := os.Getenv(cfg.TokenEnv)
	if token == "" {
		log.Fatalf("environment variable %s is empty", cfg.TokenEnv)
	}

	client := NewInboxClient(cfg.InboxURL, token)
	d := &Drafter{Config: cfg, Client: client, RunClaude: RunClaudeCLI}

	switch command {
	case "run":
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		d.RunLoop(ctx, pollInterval)
	case "once":
		did, err := d.ProcessOne(context.Background())
		if err != nil {
			log.Fatalf("process: %v", err)
		}
		if !did {
			fmt.Println("nothing to do")
		}
	default:
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: drafter <run|once> [-config path]")
}

func defaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "config.json"
	}
	return filepath.Join(home, ".config", "lurker-drafter", "config.json")
}
