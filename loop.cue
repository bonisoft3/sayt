// The loop, published as CUE: sayt's development-lifecycle contract for one
// app — the third first-class pronto concept beside the virtual cluster
// (mecha:cluster) and the virtual terminal (omnishell:terminal). Programs
// target a cluster, users touch a terminal, developers turn the loop.
// Override by unification; pin or fork this package to version the loop.
//
// Doctrine carried as data and conventions:
// - Verbs ride their builtins against the files this contract emits:
//   build/test read tasks.json (ide layer), launch drives compose.yaml's
//   `launch` service gate, lint runs the rulemap below.
// - Commands are argv-shaped: the task runner splits on spaces, no shell.
// - verify is agent-driven by default: the storybook renders the evidence,
//   the driving agent judges it; the API-key vision harness is the
//   unattended-CI upgrade.
package loop

import (
	"list"
	"strings"

	saycfg "github.com/bonisoft3/sayt:say"
)

#Loop: L={
	meta: {app: string}

	// The emitted .say.yaml must load under sayt's own config schema
	// (package say, config.cue). Validation is a hidden unification rather
	// than a type on sayYaml itself: typing the exported field would resolve
	// the schema's defaults into the emitted file, and .say.yaml carries
	// only the app's deltas — sayt applies the schema at load time.
	_sayValid: saycfg.say & L.surface.sayYaml.say

	// Declared checks projected into rulemap shape, bucketed by the layer each
	// one needs. Keyed by every verb so a bucket is an empty struct rather than
	// absent, which is what lets sayYaml test its length.
	_rulesFor: {
		for verb in ["lint", "test", "integrate"] {
			(verb): {
				for name, c in L.surface.checks if c.verb == verb {
					(name): cmds: [for d in c.cmds {do: d}]
				}
			}
		}
	}

	surface: {
		// argv-shaped commands (see doctrine above).
		buildCmd: string
		testCmd:  string

		// Validator surfaces for the lint rulemap.
		pipelineFiles: [...string] // docker/<app>-<name>.yaml, all kinds
		handlerFiles: [...string]  // app-relative handler sources; empty = no rule
		handlersCheck: *"../../plugins/pronto/check-handlers.ts" | string
		screenCssFiles: [...string] // app-relative screen stylesheets; empty = no rule
		screensCheck: *"../../plugins/pronto/check-screens.ts" | string
		bijectionCheck: *"../../plugins/pronto/check-bijection.ts" | string

		// Checks the virtual cluster and terminal declare about their own
		// surfaces; emit.cue merges both runtimes' sets in here. The verb is
		// what the check needs to run, so a battery that measures a rendered
		// page cannot land at lint however cheap it looks.
		checks: [Name=string]: {verb: "lint" | "test" | "integrate", cmds: [...string], note: string}
		checks: {}

		sayYaml: {
			say: {
				lint: rulemap: {
					L._rulesFor.lint
					...
					"cue": cmds: [{do: "mise exec -- cue vet ./..."}]
					"rpk": cmds: [{
						do: "mise exec -- redpanda-connect lint --skip-env-var-check " +
							strings.Join(L.surface.pipelineFiles, " ")
					}]
					// Runs last. sayt stops at the first failing rule, and rules with
					// equal priority are ordered by name — so an unprioritised
					// "bijection" sorts ahead of everything and a single violation
					// hides cue, rpk, handlers and screens entirely. It also
					// reads `cue export`, so cue vet diagnoses a malformed program
					// first rather than this rule failing on its precondition.
					"bijection": {
						priority: 1
						cmds: [{do: "deno run --allow-read=. --allow-run=cue \(L.surface.bijectionCheck) ."}]
					}
					if len(L.surface.handlerFiles) > 0 {
						"handlers": cmds: [{
							do: "deno run --allow-read=. \(L.surface.handlersCheck) " +
								strings.Join(list.SortStrings(L.surface.handlerFiles), " ")
						}]
					}
					if len(L.surface.screenCssFiles) > 0 {
						"screens": cmds: [{
							do: "deno run --allow-read=. \(L.surface.screensCheck) " +
								strings.Join(list.SortStrings(L.surface.screenCssFiles), " ")
						}]
					}
				}
				// A runtime that declares nothing at these layers emits no key at
				// all, leaving the app's builtin test/integrate untouched.
				if len(L._rulesFor.test) > 0 {test: rulemap: L._rulesFor.test}
				if len(L._rulesFor.integrate) > 0 {integrate: rulemap: L._rulesFor.integrate}
			}
		}

		tasksJson: {
			version: "2.0.0"
			tasks: [
				{
					label:   "build"
					type:    "shell"
					command: L.surface.buildCmd
					group: {kind: "build", isDefault: true}
				},
				{
					label:   "test"
					type:    "shell"
					command: L.surface.testCmd
					group: {kind: "test", isDefault: true}
				},
			]
		}
	}
}
