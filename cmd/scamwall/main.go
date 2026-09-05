// SPDX-License-Identifier: AGPL-3.0-only

// Command scamwall is the ScamWall command-line interface.
//
// Phase 1 is read-only and dry-run. No subcommand can modify Pi-hole.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"runtime/debug"
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/LordHorkos/scamwall/internal/adapters/pihole"
	"github.com/LordHorkos/scamwall/internal/audit"
	"github.com/LordHorkos/scamwall/internal/config"
	"github.com/LordHorkos/scamwall/internal/feed"
	"github.com/LordHorkos/scamwall/internal/policy"
)

// Build metadata, overridable with -ldflags at build time.
var (
	version = "dev"
	commit  = "unknown"
	built   = "unknown"
)

// Exit codes.
const (
	exitOK      = 0
	exitFailure = 1
	exitUsage   = 2
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr *os.File) int {
	if len(args) == 0 {
		usage(stderr)
		return exitUsage
	}

	cmd := args[0]
	rest := args[1:]

	// Signals are translated into context cancellation so that an interrupted
	// run still unwinds through the deferred logout rather than dying with a
	// live session on the server.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log := audit.New(stderr)

	switch cmd {
	case "version":
		return cmdVersion(stdout, rest)
	case "doctor":
		return cmdDoctor(ctx, stdout, log, rest)
	case "status":
		return cmdStatus(ctx, stdout, log, rest)
	case "validate-feed":
		return cmdValidateFeed(stdout, log, rest)
	case "plan":
		return cmdPlan(stdout, log, rest)
	case "sync":
		return cmdSync(ctx, stdout, log, rest)
	case "help", "-h", "--help":
		usage(stdout)
		return exitOK
	default:
		fmt.Fprintf(stderr, "unknown command %q\n\n", cmd)
		usage(stderr)
		return exitUsage
	}
}

func usage(w *os.File) {
	fmt.Fprint(w, `scamwall - local-first fraud-domain protection for Pi-hole

Usage:
  scamwall <command> [flags]

Commands:
  version         Print build and enforcement information
  doctor          Check configuration, trust material and connectivity
  status          Authenticate, read Pi-hole version, log out
  validate-feed   Verify and validate the configured signed feed
  plan            Compute the proposed blocking plan (offline)
  sync --dry-run  Compute the plan and report it without submitting anything

Phase 1 is read-only. No command modifies Pi-hole.
`)
}

// newFlagSet builds a flag set with the shared -config flag.
func newFlagSet(name string, w *os.File) (*flag.FlagSet, *string) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(w)
	cfgPath := fs.String("config", config.DefaultConfigPath, "path to the configuration file")
	return fs, cfgPath
}

func loadConfig(path string) (config.Config, error) {
	cfg, err := config.Load(path)
	if err != nil {
		return config.Config{}, fmt.Errorf("configuration: %w", err)
	}
	return cfg, nil
}

func cmdVersion(w *os.File, args []string) int {
	fs, _ := newFlagSet("version", w)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	rev := commit
	if rev == "unknown" {
		if info, ok := debug.ReadBuildInfo(); ok {
			for _, s := range info.Settings {
				if s.Key == "vcs.revision" {
					rev = s.Value
				}
			}
		}
	}

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintf(tw, "scamwall\t%s\n", version)
	fmt.Fprintf(tw, "commit\t%s\n", rev)
	fmt.Fprintf(tw, "built\t%s\n", built)
	fmt.Fprintf(tw, "enforcement compiled in\t%t\n", policy.EnforcementCompiledIn)
	fmt.Fprintf(tw, "mode\tread-only, dry-run\n")
	_ = tw.Flush()
	return exitOK
}

// check is one doctor result line.
type check struct {
	name   string
	ok     bool
	detail string
}

func cmdDoctor(ctx context.Context, w *os.File, log *audit.Logger, args []string) int {
	fs, cfgPath := newFlagSet("doctor", w)
	skipNet := fs.Bool("offline", false, "skip connectivity checks")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	var checks []check
	add := func(name string, err error, okDetail string) bool {
		if err != nil {
			checks = append(checks, check{name, false, err.Error()})
			return false
		}
		checks = append(checks, check{name, true, okDetail})
		return true
	}

	cfg, err := loadConfig(*cfgPath)
	if !add("configuration", err, fmt.Sprintf("loaded (dry_run=%t)", cfg.Runtime.DryRun)) {
		return report(w, checks)
	}

	add("enforcement absent", func() error {
		if policy.EnforcementCompiledIn {
			return errors.New("enforcement is compiled into this build, which Phase 1 forbids")
		}
		return nil
	}(), "not compiled in")

	// The secret is checked for presence and shape only. Its content is never
	// read into a report, and its length is the most that is ever disclosed.
	secret, secErr := config.LoadSecretFile(cfg.Pihole.SecretPath)
	if add("application password", secErr, fmt.Sprintf("readable, %d bytes", secret.Len())) {
		defer secret.Destroy()
	}

	client, cliErr := pihole.New(cfg, log)
	add("certificate authority", cliErr, "loaded and parsed: "+cfg.Pihole.CAPath)

	_, feedErr := loadFeed(cfg)
	add("feed", feedErr, "signature and manifest valid: "+cfg.Feed.Path)

	if !*skipNet && cliErr == nil {
		state, probeErr := client.ProbeAuth(ctx)
		detail := "reachable over TLS"
		if probeErr == nil && state.Message != "" {
			detail += "; " + state.Message
		}
		add("pi-hole connectivity", probeErr, detail)
	}

	return report(w, checks)
}

func report(w *os.File, checks []check) int {
	failed := 0
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	for _, c := range checks {
		mark := "ok"
		if !c.ok {
			mark = "FAIL"
			failed++
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\n", mark, c.name, c.detail)
	}
	_ = tw.Flush()
	fmt.Fprintf(w, "\n%d checks, %d failed\n", len(checks), failed)
	if failed > 0 {
		return exitFailure
	}
	return exitOK
}

func cmdStatus(ctx context.Context, w *os.File, log *audit.Logger, args []string) int {
	fs, cfgPath := newFlagSet("status", w)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		return fail(w, err)
	}

	secret, err := config.LoadSecretFile(cfg.Pihole.SecretPath)
	if err != nil {
		return fail(w, err)
	}
	defer secret.Destroy()

	client, err := pihole.New(cfg, log)
	if err != nil {
		return fail(w, err)
	}

	var info *pihole.VersionInfo
	err = client.WithSession(ctx, secret, func(ctx context.Context) error {
		var innerErr error
		info, innerErr = client.Version(ctx)
		return innerErr
	})
	if err != nil {
		return fail(w, err)
	}

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintf(tw, "component\tlocal\tbranch\tremote\n")
	fmt.Fprintf(tw, "core\t%s\t%s\t%s\n", info.Core.LocalVersion, info.Core.LocalBranch, info.Core.RemoteVersion)
	fmt.Fprintf(tw, "web\t%s\t%s\t%s\n", info.Web.LocalVersion, info.Web.LocalBranch, info.Web.RemoteVersion)
	fmt.Fprintf(tw, "ftl\t%s\t%s\t%s\n", info.FTL.LocalVersion, info.FTL.LocalBranch, info.FTL.RemoteVersion)
	_ = tw.Flush()
	fmt.Fprintln(w, "\nsession closed")
	return exitOK
}

func loadFeed(cfg config.Config) (*feed.Validated, error) {
	key, err := cfg.TrustPublicKeyBytes()
	if err != nil {
		return nil, err
	}
	return feed.LoadFile(cfg.Feed.Path, feed.Options{
		MaxFileBytes: cfg.Feed.MaxFileBytes,
		MaxRecords:   cfg.Feed.MaxRecords,
		TrustKeyID:   cfg.Feed.TrustKeyID,
		TrustKey:     key,
	})
}

func cmdValidateFeed(w *os.File, _ *audit.Logger, args []string) int {
	fs, cfgPath := newFlagSet("validate-feed", w)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		return fail(w, err)
	}
	v, err := loadFeed(cfg)
	if err != nil {
		return fail(w, err)
	}

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintf(tw, "feed id\t%s\n", v.FeedID)
	fmt.Fprintf(tw, "manifest version\t%s\n", v.ManifestVersion)
	fmt.Fprintf(tw, "signing key id\t%s\n", v.KeyID)
	fmt.Fprintf(tw, "issued at\t%s\n", v.IssuedAt.UTC().Format(time.RFC3339))
	fmt.Fprintf(tw, "expires at\t%s\n", v.ExpiresAt.UTC().Format(time.RFC3339))
	fmt.Fprintf(tw, "valid indicators\t%d\n", len(v.Indicators))
	fmt.Fprintf(tw, "expired indicators\t%d\n", v.ExpiredCount)
	_ = tw.Flush()
	fmt.Fprintln(w, "\nsignature verified")
	return exitOK
}

func cmdPlan(w *os.File, _ *audit.Logger, args []string) int {
	fs, cfgPath := newFlagSet("plan", w)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		return fail(w, err)
	}
	v, err := loadFeed(cfg)
	if err != nil {
		return fail(w, err)
	}
	printPlan(w, policy.Compute(v))
	return exitOK
}

func printPlan(w *os.File, p *policy.Plan) {
	fmt.Fprintf(w, "proposed plan (%s)\n", p.FormatVersion)
	fmt.Fprintf(w, "feed:   %s (manifest %s)\n", p.FeedID, p.ManifestVersion)
	fmt.Fprintf(w, "digest: %s\n\n", p.Digest)

	if p.IsEmpty() {
		fmt.Fprintln(w, "no domains proposed for blocking")
	} else {
		for _, e := range p.Entries {
			fmt.Fprintf(w, "  block  %s", e.Domain)
			if e.Category != "" {
				fmt.Fprintf(w, "  [%s]", e.Category)
			}
			fmt.Fprintln(w)
		}
	}

	fmt.Fprintf(w, "\n%d proposed, %d excluded (%d not block, %d below confidence, %d expired)\n",
		p.Count(), p.Exclusions.Total(),
		p.Exclusions.NotBlockAction, p.Exclusions.BelowConfidence, p.Exclusions.ExpiredInFeed)
}

func cmdSync(ctx context.Context, w *os.File, log *audit.Logger, args []string) int {
	fs, cfgPath := newFlagSet("sync", w)
	// Dry-run is the immutable default. The flag exists so that an explicit
	// --dry-run reads naturally and so that --dry-run=false fails loudly
	// rather than silently doing nothing an operator might misread as success.
	dryRun := fs.Bool("dry-run", true, "compute and report the plan without submitting it (always required in Phase 1)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if !*dryRun {
		fmt.Fprintln(w, "refusing to run: --dry-run=false is not available.")
		fmt.Fprintln(w, "ScamWall Phase 1 is read-only; enforcement is not compiled into this build.")
		return exitUsage
	}

	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		return fail(w, err)
	}
	v, err := loadFeed(cfg)
	if err != nil {
		return fail(w, err)
	}
	plan := policy.Compute(v)

	secret, err := config.LoadSecretFile(cfg.Pihole.SecretPath)
	if err != nil {
		return fail(w, err)
	}
	defer secret.Destroy()

	client, err := pihole.New(cfg, log)
	if err != nil {
		return fail(w, err)
	}

	var info *pihole.VersionInfo
	err = client.WithSession(ctx, secret, func(ctx context.Context) error {
		var innerErr error
		info, innerErr = client.Version(ctx)
		return innerErr
	})
	if err != nil {
		return fail(w, err)
	}

	fmt.Fprintf(w, "connected to Pi-hole (core %s, web %s, ftl %s)\n\n",
		info.Core.LocalVersion, info.Web.LocalVersion, info.FTL.LocalVersion)
	printPlan(w, plan)

	fmt.Fprintln(w, "\nDRY RUN: nothing was submitted to Pi-hole.")
	fmt.Fprintln(w, "No blocking change was made. Enforcement is not compiled into this build.")
	return exitOK
}

func fail(w *os.File, err error) int {
	fmt.Fprintf(w, "error: %v\n", err)
	return exitFailure
}
