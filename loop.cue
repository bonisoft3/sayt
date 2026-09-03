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
	// Flat, and a LIST on purpose: `len()` over the struct the comprehension
	// below builds evaluates as incomplete and the setup guard silently never
	// fires — the emitted .say.yaml simply loses the rule with no error. A list
	// comprehension over the same source is concrete.
	_setupCmds: [for _, c in L.surface.checks if c.verb == "setup" for d in c.cmds {do: d}]

	_rulesFor: {
		for verb in ["setup", "lint", "test", "integrate"] {
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
		pipelineFiles: [...string] // docker/<app>-<name>.yaml, all kinds; empty = no rule
		factsCheck:                 *"../../plugins/pronto/check-facts.ts" | string
		deriveCheck:                *"../../plugins/pronto/derive.ts" | string

		// Checks the virtual cluster and terminal declare about their own
		// surfaces; emit.cue merges both runtimes' sets in here. The verb is
		// what the check needs to run, so a battery that measures a rendered
		// page cannot land at lint however cheap it looks.
		checks: [Name=string]: {verb: "setup" | "lint" | "test" | "integrate", cmds: [...string], note: string}
		checks: {}

		sayYaml: {
			say: {
				lint: rulemap: {
					L._rulesFor.lint
					...
					"cue": cmds: [{do: "mise exec -- cue vet ./..."}]
					// The derivation's own transform. It reads no app file; it rides
					// the app rulemap because that is the only verb a pronto plugin
					// file lands in.
					"derive": cmds: [{do: "deno run --allow-read=. \(L.surface.deriveCheck) --self-test"}]
					// Guarded like handlers and screens below: with no pipeline
					// files the command lints its own empty argument list, which
					// passes without reading anything.
					if len(L.surface.pipelineFiles) > 0 {
						"rpk": cmds: [{
							do: "mise exec -- redpanda-connect lint --skip-env-var-check " +
								strings.Join(L.surface.pipelineFiles, " ")
						}]
					}

					// Prioritised for bijection's reason at one remove: it reads the
					// derived facts rather than the program, so cue vet diagnoses a
					// malformed program before this rule reports on stale rows.
					"facts": {
						priority: 1
						cmds: [{
							do: "deno run --allow-read=.,../../plugins/pronto --allow-run=mise \(L.surface.factsCheck) ."
						}]
					}
				}
				// A runtime that declares nothing at these layers emits no key at
				// all, leaving the app's builtin test/integrate untouched.
				//
				// Where it DOES declare, config.cue's builtin rule carries
				// `stop: true`, so untouched it runs first and the declared rules
				// never do. `stop: false` alone fails the default disjunct and
				// resolves the builtin with NO cmds — so every cmd the builtin
				// should keep must be re-declared beside it (setup below is the
				// same pattern). test keeps its builtin: `./test.nu` runs
				// tasks.json's `cue vet -c ./...`, the concreteness gate the
				// declared batteries assume. integrate re-declares nothing on
				// purpose: its builtin drives `docker compose up integrate`, a
				// service this emitter never writes, so the verb would fail
				// before reaching the checks it emitted.
				if len(L._rulesFor.test) > 0 {
					test: rulemap: {
						L._rulesFor.test
						builtin: {stop: false, cmds: [{do: "test", use: "./test.nu"}]}
					}
				}
				if len(L._rulesFor.integrate) > 0 {
					integrate: rulemap: {L._rulesFor.integrate, builtin: {stop: false}}
				}

				// setup is the one layer whose declarations must APPEND to the
				// builtin rather than sit beside it. config.cue gives the builtin
				// rule `stop: true`, so a sibling rule is emitted, sorted after it,
				// and never runs; and `builtin: {stop: false}` fails the default
				// disjunct, which silently resolves builtin with no cmds at all —
				// setup would stop installing tools and say nothing. Re-declaring
				// the builtin's own cmd first is what keeps `mise install` in the
				// chain (services/esocial-rpa is the hand-written worked example).
				if len(L._setupCmds) > 0 {
					setup: rulemap: builtin: cmds: list.Concat([
						[{do: "setup", use: "./setup.nu"}],
						L._setupCmds,
					])
				}
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
