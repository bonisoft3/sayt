#!/usr/bin/env nu
# Tests for sayt/summary's cache accounting, on both arms: the build-history API
# (rawjson) and the `--progress plain` log depot falls back to.
# Run with: nu summary_test.nu (from plugins/sayt directory)

use std/assert

const ACTION = ".github/actions/sayt/summary/action.yml"
const STEP = "Compute cache-hit summary"

# One build, described the way each arm receives it. Reading it as buildkit does:
# two hits, two misses (9.9s and 1.0s, the latter consumed by two targets), one
# miss that moved no bytes, one vertex resolved to an existing ref and never
# scheduled, and two steps that are not build steps.
#
# Keyed by step NAME instead of vertex id/digest this reads 2/6: the two
# heavy-compile vertices collapse into one group (and the 1.0s miss inherits the
# 9.9s one's duration), the `[beta …]` label becomes a group of its own, and #7 —
# which never ran — is counted as a miss.
const SHARED_PLAIN = "#1 [internal] load build definition from Dockerfile
#1 DONE 0.1s
#2 [alpha build 1/4] RUN make deps
#2 CACHED
#2 DONE 0.0s
#3 [alpha build 2/4] RUN heavy-compile
#3 [beta build 2/4] RUN heavy-compile
#3 DONE 1.0s
#4 [alpha build 2/4] RUN heavy-compile
#4 DONE 9.9s
#5 [alpha models 1/2] ADD --checksum=sha256:aaaa https://example.invalid/a /a
#5 CACHED
#6 [alpha models 2/2] ADD --checksum=sha256:bbbb https://example.invalid/b /b
#6 DONE 0.0s
#7 [alpha build 3/4] RUN never-scheduled
#8 [alpha build 4/4] COPY src /src
#8 DONE 0.2s
"

# The same build as buildkit's history reports it: an announce message naming
# every vertex, then a completion message. `cached` only ever appears on the
# completion event, and a vertex that was never scheduled gets no second event.
const SHARED_RAWJSON = '{"vertexes":[{"digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/4] RUN make deps"},{"digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 2/4] RUN heavy-compile"},{"digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[beta build 2/4] RUN heavy-compile"},{"digest":"sha256:3333333333333333333333333333333333333333333333333333333333333333","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 2/4] RUN heavy-compile"},{"digest":"sha256:4444444444444444444444444444444444444444444444444444444444444444","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha models 1/2] ADD --checksum=sha256:aaaa https://example.invalid/a /a"},{"digest":"sha256:5555555555555555555555555555555555555555555555555555555555555555","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha models 2/2] ADD --checksum=sha256:bbbb https://example.invalid/b /b"},{"digest":"sha256:6666666666666666666666666666666666666666666666666666666666666666","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 3/4] RUN never-scheduled"},{"digest":"sha256:7777777777777777777777777777777777777777777777777777777777777777","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 4/4] COPY src /src"},{"digest":"sha256:8888888888888888888888888888888888888888888888888888888888888888","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[internal] load build definition from Dockerfile"}]}
{"vertexes":[{"digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/4] RUN make deps","started":"2026-08-22T00:00:11.000000000Z","completed":"2026-08-22T00:00:11.000000000Z","cached":true},{"digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 2/4] RUN heavy-compile","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:01.000000000Z"},{"digest":"sha256:3333333333333333333333333333333333333333333333333333333333333333","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 2/4] RUN heavy-compile","started":"2026-08-22T00:00:01.000000000Z","completed":"2026-08-22T00:00:10.900000000Z"},{"digest":"sha256:4444444444444444444444444444444444444444444444444444444444444444","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha models 1/2] ADD --checksum=sha256:aaaa https://example.invalid/a /a","started":"2026-08-22T00:00:12.000000000Z","completed":"2026-08-22T00:00:12.000000000Z","cached":true},{"digest":"sha256:5555555555555555555555555555555555555555555555555555555555555555","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha models 2/2] ADD --checksum=sha256:bbbb https://example.invalid/b /b","started":"2026-08-22T00:00:13.000000000Z","completed":"2026-08-22T00:00:13.040000000Z"},{"digest":"sha256:7777777777777777777777777777777777777777777777777777777777777777","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 4/4] COPY src /src","started":"2026-08-22T00:00:14.000000000Z","completed":"2026-08-22T00:00:14.200000000Z"},{"digest":"sha256:8888888888888888888888888888888888888888888888888888888888888888","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[internal] load build definition from Dockerfile","started":"2026-08-22T00:00:15.000000000Z","completed":"2026-08-22T00:00:15.100000000Z","cached":true}]}
'

# One stage name, two chain IDs, one cached and one not: `cache-from` can match
# at most one of them next run. The gate must fail the job. Both carry inputs, or
# they would read as source ops and be dropped.
const DIVERGENT_RAWJSON = '{"vertexes":[{"digest":"sha256:aaaa111111111111111111111111111111111111111111111111111111111111","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:00.000000000Z","cached":true},{"digest":"sha256:bbbb222222222222222222222222222222222222222222222222222222222222","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile","started":"2026-08-22T00:00:01.000000000Z","completed":"2026-08-22T00:00:04.000000000Z"}]}
'

# One stage name, two chain IDs, one cached and one never scheduled. Nothing was
# recomputed, so there is no divergence to fail on.
const UNSCHEDULED_PAIR_RAWJSON = '{"vertexes":[{"digest":"sha256:cccc333333333333333333333333333333333333333333333333333333333333","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile"},{"digest":"sha256:dddd444444444444444444444444444444444444444444444444444444444444","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile"}]}
{"vertexes":[{"digest":"sha256:cccc333333333333333333333333333333333333333333333333333333333333","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:00.000000000Z","cached":true}]}
'

# A remote `ADD` as buildkit reports it, warm: the inputless source op and the
# file op that caches, under one name.
const REMOTE_ADD_RAWJSON = '{"vertexes":[{"digest":"sha256:5017000000000000000000000000000000000000000000000000000000000000","name":"[alpha models 1/1] ADD --checksum=sha256:aaaa https://example.invalid/a /a","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:00.000000000Z"},{"digest":"sha256:f11e000000000000000000000000000000000000000000000000000000000000","inputs":["sha256:5017000000000000000000000000000000000000000000000000000000000000","sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha models 1/1] ADD --checksum=sha256:aaaa https://example.invalid/a /a","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:00.000000000Z","cached":true}]}
'

const LS_JSON = '{"ref":"builder/builder0/testuid","name":"fixture","status":"Completed","created_at":"2026-08-22T00:00:00.000000000Z","completed_at":"2026-08-22T00:00:16.000000000Z","cached_steps":2,"completed_steps":5,"total_steps":9}
'

def main [] {
	print "Running sayt/summary tests...\n"

	if $nu.os-info.name == "windows" {
		print "    SKIP (composite-action steps are `shell: bash`)"
		return
	}

	test_progress_log_counts_executed_steps
	test_progress_log_tables_separate_the_three_verdicts
	test_progress_log_headline_only_without_debug
	test_rawjson_counts_executed_steps
	test_rawjson_tables_key_by_digest
	test_rawjson_collapses_an_execution_shared_across_records
	test_rawjson_keeps_distinct_executions_of_one_digest
	test_labels_render_in_announce_order
	test_both_arms_agree_on_the_same_build
	test_divergence_gate_fails_on_differing_cache_outcomes
	test_divergence_gate_ignores_vertices_that_never_ran
	test_source_ops_are_not_counted
	test_divergence_gate_ignores_source_ops

	print "\nAll sayt/summary tests passed!"
}

# Runs the action's summary step and returns its exit code plus the job summary
# it wrote. Exactly one of --log / --rawjson selects the arm: --log stubs the
# build-history API unavailable, --rawjson serves it from the fixture.
def run-summary [--log: string, --rawjson: string, --rawjson2: string, --debug]: nothing -> record {
	let dir = (mktemp -d)
	let root = ($env.FILE_PWD? | default (pwd))

	let step = (open ($root | path join $ACTION) | get runs.steps | where name == $STEP | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script

	let log_path = ($dir | path join "progress.log")
	let stub = ($dir | path join "stub")
	mkdir $stub
	if $rawjson != null {
		# --rawjson2 makes the fixture span two build records, the shape a bake job
		# produces: the action pulls each ref's rawjson into its own file.
		$rawjson | save -f ($dir | path join "uid1.rawjson")
		mut ls = ($LS_JSON | str replace "testuid" "uid1")
		mut dispatch = $"  *'history logs'*uid1*\) cat '($dir)/uid1.rawjson' ;;\n"
		if $rawjson2 != null {
			$rawjson2 | save -f ($dir | path join "uid2.rawjson")
			$ls = $"($ls)($LS_JSON | str replace 'testuid' 'uid2')"
			$dispatch = $"($dispatch)  *'history logs'*uid2*\) cat '($dir)/uid2.rawjson' ;;\n"
		}
		$ls | save -f ($dir | path join "ls.json")
		# `history export` is left failing: the .dockerbuild is not under test and
		# the step is required to stay green without it.
		$"#!/bin/sh\ncase \"$*\" in\n  *'history ls'*\) cat '($dir)/ls.json' ;;\n($dispatch)  *\) exit 1 ;;\nesac\n" | save -f ($stub | path join "docker")
	} else {
		$log | save -f $log_path
		"#!/bin/sh\nexit 1\n" | save -f ($stub | path join "docker")
	}
	chmod +x ($stub | path join "docker")

	let out = ($dir | path join "summary.md")
	touch $out
	let result = (do {
		with-env {
			PATH: ($env.PATH | prepend $stub)
			BUILDX_BUILDER: (if $rawjson != null { "fixture-builder" } else { "" })
			SAYT_SUMMARY_NAME: "fixture"
			SAYT_SUMMARY_DEBUG: (if $debug { "true" } else { "false" })
			SAYT_SUMMARY_PROGRESS_LOG: (if $rawjson != null { "" } else { $log_path })
			SAYT_SUMMARY_OUT: ($dir | path join "unused.dockerbuild")
			GITHUB_STEP_SUMMARY: $out
		} { ^bash $script }
	} | complete)

	let summary = (open --raw $out)
	rm -rf $dir
	{ exit: $result.exit_code, summary: $summary, stderr: $result.stderr }
}

# The tables a run produced, with the section headers dropped: enough to compare
# two arms row for row.
def rows-of [summary: string]: nothing -> list<string> {
	$summary | lines | where {|l| ($l | str starts-with "| `") }
}

def ok [r: record, ctx: string] {
	assert ($r.exit == 0) $"($ctx): expected exit 0, got ($r.exit): ($r.stderr)"
}

# ---------------------------------------------------------------- progress log

# A vertex that prints neither CACHED nor DONE was never scheduled: it neither
# hit nor missed, and counting it as a miss reports a regression on a step that
# takes minutes when it genuinely runs.
def test_progress_log_counts_executed_steps [] {
	print "test progress-log headline counts executed steps only..."
	let r = (run-summary --log $SHARED_PLAIN)
	ok $r "progress-log"
	assert ($r.summary | str contains "**2/5**") $"expected 2/5 executed steps, got: ($r.summary)"
	assert ($r.summary | str contains "(40%)") $"expected 40%, got: ($r.summary)"
	assert ($r.summary | str contains "1 never ran (excluded)") $"expected the unscheduled step called out, got: ($r.summary)"
}

def test_progress_log_tables_separate_the_three_verdicts [] {
	print "test progress-log tables misses, zero-cost misses and unresolved apart..."
	let r = (run-summary --log $SHARED_PLAIN --debug)
	ok $r "progress-log"

	assert ($r.summary | str contains "### Misses (2, slowest first)") $"expected two real misses, got: ($r.summary)"
	assert ($r.summary | str contains "### Zero-cost misses (1)") $"expected one zero-cost miss, got: ($r.summary)"
	assert ($r.summary | str contains "### Unresolved (1, excluded from the ratio)") $"expected one unscheduled step, got: ($r.summary)"

	# Two vertices share this step name. Both must appear, each with its own
	# duration — neither borrowing the other's.
	let heavy = ($r.summary | lines | where {|l| $l | str contains "heavy-compile" } | where {|l| $l | str starts-with "| `" })
	assert (($heavy | length) == 2) $"expected both heavy-compile vertices, got: ($heavy)"
	assert ($heavy.0 | str contains "| 9.9s |") $"slowest miss should be 9.9s, got: ($heavy.0)"
	assert ($heavy.1 | str contains "| 1.0s |") $"second miss should be 1.0s, got: ($heavy.1)"
	# Every consuming target is named, so the row is attributable whichever
	# label buildkit happened to print first.
	assert ($heavy.1 | str contains "`[beta build 2/4] RUN heavy-compile`") $"expected both consumer labels, got: ($heavy.1)"

	assert ($r.summary | str contains "sha256:bbbb") $"zero-cost ADD miss should be listed, got: ($r.summary)"
	assert ($r.summary | str contains "`[alpha build 3/4] RUN never-scheduled`") $"unscheduled step should be listed, got: ($r.summary)"
	# COPY is excluded by the step definition, on both arms.
	assert (not ($r.summary | str contains "COPY src /src")) $"COPY must not be counted, got: ($r.summary)"
}

def test_progress_log_headline_only_without_debug [] {
	print "test progress-log debug=false emits the headline alone..."
	let r = (run-summary --log $SHARED_PLAIN)
	ok $r "progress-log"
	assert (not ($r.summary | str contains "### Misses")) $"misses table leaked without debug: ($r.summary)"
	assert (not ($r.summary | str contains "### Zero-cost misses")) $"zero-cost table leaked without debug: ($r.summary)"
	assert (not ($r.summary | str contains "### Unresolved")) $"unresolved table leaked without debug: ($r.summary)"
}

# ------------------------------------------------------------------- rawjson

def test_rawjson_counts_executed_steps [] {
	print "test rawjson headline counts executed steps only..."
	let r = (run-summary --rawjson $SHARED_RAWJSON)
	ok $r "rawjson"
	assert ($r.summary | str contains "**2/5**") $"expected 2/5 executed steps, got: ($r.summary)"
	assert ($r.summary | str contains "(40%)") $"expected 40%, got: ($r.summary)"
	assert ($r.summary | str contains "1 never ran (excluded)") $"expected the unscheduled step called out, got: ($r.summary)"
}

def test_rawjson_tables_key_by_digest [] {
	print "test rawjson keys by digest, not step name..."
	let r = (run-summary --rawjson $SHARED_RAWJSON --debug)
	ok $r "rawjson"

	assert ($r.summary | str contains "### Misses (2, slowest first)") $"expected two real misses, got: ($r.summary)"
	assert ($r.summary | str contains "### Zero-cost misses (1)") $"expected one zero-cost miss, got: ($r.summary)"
	assert ($r.summary | str contains "### Unresolved (1, excluded from the ratio)") $"expected one unscheduled step, got: ($r.summary)"

	let heavy = ($r.summary | lines | where {|l| $l | str contains "heavy-compile" } | where {|l| $l | str starts-with "| `" })
	assert (($heavy | length) == 2) $"expected one row per digest, got: ($heavy)"
	assert ($heavy.0 | str contains "| 9.9s |") $"slowest miss should be 9.9s, got: ($heavy.0)"
	# Sub-second durations must survive: truncating to whole seconds files every
	# fast miss under "moved no bytes".
	assert ($heavy.1 | str contains "| 1.0s |") $"second miss should be 1.0s, got: ($heavy.1)"
	assert ($heavy.1 | str contains "`[beta build 2/4] RUN heavy-compile`") $"expected both consumer labels, got: ($heavy.1)"

	assert (not ($r.summary | str contains "COPY src /src")) $"COPY must not be counted, got: ($r.summary)"
	assert (not ($r.summary | str contains "load build definition")) $"[internal] ops must not be counted, got: ($r.summary)"
}

# One execution reported into several records has to count once. Counting it per
# record inflates both sides of the ratio: three concurrent bakes over a shared
# setup stage double the denominator.
def test_rawjson_collapses_an_execution_shared_across_records [] {
	print "test rawjson counts a shared execution once..."
	let ev = '{"digest":"sha256:eeee555555555555555555555555555555555555555555555555555555555555","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:05.000000000Z"}'
	let rec = $"\{\"vertexes\":[($ev)]\}\n"
	let r = (run-summary --rawjson $rec --rawjson2 $rec --debug)
	ok $r "rawjson"
	assert ($r.summary | str contains "**0/1**") $"expected one execution, got: ($r.summary)"
	let rows = (rows-of $r.summary | where {|l| $l | str contains "RUN compile" })
	assert (($rows | length) == 1) $"expected a single miss row, got: ($rows)"
}

# The same digest built cold and hit warm is two events, not one. Collapsing on
# digest alone lets the hit swallow the miss and reports a clean build.
def test_rawjson_keeps_distinct_executions_of_one_digest [] {
	print "test rawjson keeps cold and warm events of one digest apart..."
	let cold = '{"vertexes":[{"digest":"sha256:eeee555555555555555555555555555555555555555555555555555555555555","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:05.000000000Z"}]}'
	let warm = '{"vertexes":[{"digest":"sha256:eeee555555555555555555555555555555555555555555555555555555555555","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile","started":"2026-08-22T00:00:06.000000000Z","completed":"2026-08-22T00:00:06.000000000Z","cached":true}]}'
	let r = (run-summary --rawjson $"($cold)\n" --rawjson2 $"($warm)\n" --debug)
	ok $r "rawjson"
	assert ($r.summary | str contains "**1/2**") $"expected one hit and one miss, got: ($r.summary)"
	assert ($r.summary | str contains "| 5.0s |") $"the cold miss should keep its duration, got: ($r.summary)"
}

# Labels render in the order buildkit announced them. Sorting them instead reads
# the same until a vertex's targets happen to sort against announce order, at
# which point the two arms disagree on a row they are supposed to render alike.
def test_labels_render_in_announce_order [] {
	print "test consumer labels keep announce order..."
	let plain = "#1 [zulu build 1/1] RUN compile
#1 [alpha build 1/1] RUN compile
#1 DONE 1.0s
"
	let raw = '{"vertexes":[{"digest":"sha256:ffff666666666666666666666666666666666666666666666666666666666666","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[zulu build 1/1] RUN compile"},{"digest":"sha256:ffff666666666666666666666666666666666666666666666666666666666666","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[alpha build 1/1] RUN compile"}]}
{"vertexes":[{"digest":"sha256:ffff666666666666666666666666666666666666666666666666666666666666","inputs":["sha256:9999000000000000000000000000000000000000000000000000000000000000"],"name":"[zulu build 1/1] RUN compile","started":"2026-08-22T00:00:00.000000000Z","completed":"2026-08-22T00:00:01.000000000Z"}]}
'
	let a = (run-summary --log $plain --debug)
	let b = (run-summary --rawjson $raw --debug)
	ok $a "progress-log"
	ok $b "rawjson"
	let want = "| `[zulu build 1/1] RUN compile`<br>`[alpha build 1/1] RUN compile` | 1.0s |"
	assert ((rows-of $a.summary | first) == $want) $"progress-log reordered labels: (rows-of $a.summary)"
	assert ((rows-of $b.summary | first) == $want) $"rawjson reordered labels: (rows-of $b.summary)"
}

def test_both_arms_agree_on_the_same_build [] {
	print "test both arms report the same build identically..."
	let a = (run-summary --log $SHARED_PLAIN --debug)
	let b = (run-summary --rawjson $SHARED_RAWJSON --debug)
	ok $a "progress-log"
	ok $b "rawjson"

	# The headlines differ in provenance wording; the accounting must not.
	assert ($a.summary | str contains "**2/5**") $"progress-log: ($a.summary)"
	assert ($b.summary | str contains "**2/5**") $"rawjson: ($b.summary)"

	let rows_a = (rows-of $a.summary)
	let rows_b = (rows-of $b.summary | where {|l| not ($l | str contains "`fixture`") })
	assert ($rows_a == $rows_b) $"arms disagree.\nprogress-log:\n($rows_a | str join (char nl))\nrawjson:\n($rows_b | str join (char nl))"
}

# ---------------------------------------------------------- divergence gate

def test_divergence_gate_fails_on_differing_cache_outcomes [] {
	print "test divergence gate fails the job on split chain IDs..."
	let r = (run-summary --rawjson $DIVERGENT_RAWJSON)
	assert ($r.exit == 1) $"expected exit 1 on divergence, got ($r.exit): ($r.summary)"
	assert ($r.summary | str contains "Chain-ID divergence") $"expected the divergence table, got: ($r.summary)"
}

def test_divergence_gate_ignores_vertices_that_never_ran [] {
	print "test divergence gate ignores vertices that never ran..."
	let r = (run-summary --rawjson $UNSCHEDULED_PAIR_RAWJSON)
	ok $r "divergence gate"
	assert (not ($r.summary | str contains "Chain-ID divergence")) $"unscheduled chain ID must not fail the job, got: ($r.summary)"
}

# Counting the source op leaves a miss no warm build can clear, so a project that
# fetches a URL could never reach 100%. The arms must agree despite reaching the
# count from different evidence.
def test_source_ops_are_not_counted [] {
	print "test a remote ADD counts once, on both arms..."
	let plain = "#1 [alpha models 1/1] ADD --checksum=sha256:aaaa https://example.invalid/a /a
#1 DONE 0.0s
#2 [alpha models 1/1] ADD --checksum=sha256:aaaa https://example.invalid/a /a
#2 CACHED
"
	let a = (run-summary --log $plain --debug)
	let b = (run-summary --rawjson $REMOTE_ADD_RAWJSON --debug)
	ok $a "progress-log"
	ok $b "rawjson"
	assert ($a.summary | str contains "**1/1**") $"progress-log should count the ADD once: ($a.summary)"
	assert ($b.summary | str contains "**1/1**") $"rawjson should count the ADD once: ($b.summary)"
	# The whole point: a warm build with a remote ADD can reach 100%.
	assert ($a.summary | str contains "✅") $"progress-log should be all-hit: ($a.summary)"
	assert ($b.summary | str contains "✅") $"rawjson should be all-hit: ($b.summary)"
	assert (not ($a.summary | str contains "### Zero-cost misses")) $"no zero-cost miss should survive: ($a.summary)"
}

# One cached vertex and one that never can is not a split chain ID; failing the
# job over it breaks every correct build that fetches a URL.
def test_divergence_gate_ignores_source_ops [] {
	print "test divergence gate ignores source ops..."
	let r = (run-summary --rawjson $REMOTE_ADD_RAWJSON)
	ok $r "divergence gate"
	assert (not ($r.summary | str contains "Chain-ID divergence")) $"a remote ADD must not fail the job, got: ($r.summary)"
}
