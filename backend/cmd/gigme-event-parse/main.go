package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"gigme/backend/internal/eventparser"
	"gigme/backend/internal/eventparser/core"
)

func main() {
	sourceFlag := flag.String("source", string(core.SourceAuto), "source type: auto|telegram|web|instagram|vk")
	timeoutFlag := flag.Duration("timeout", 20*time.Second, "parse timeout")
	flag.Parse()
	if flag.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: gigme-event-parse [-source auto] \"<url-or-channel>\"")
		os.Exit(2)
	}
	input := strings.TrimSpace(flag.Arg(0))
	source := core.SourceType(strings.TrimSpace(*sourceFlag))
	if source == "" {
		source = core.SourceAuto
	}
	if !source.Valid() {
		fmt.Fprintf(os.Stderr, "invalid source: %s\n", source)
		os.Exit(2)
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeoutFlag)
	defer cancel()
	event, err := eventparser.ParseEventWithSource(ctx, input, source)
	if err != nil {
		fmt.Fprintf(os.Stderr, "parse error: %v\n", err)
		os.Exit(1)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(event)
}
