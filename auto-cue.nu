# auto-cue.nu — Built-in lint: vet, copy, shared
use tools.nu [run-cue]
use config.nu [load-config]

export def main [] {
	let config = load-config
	let lint = $config.say?.lint? | default {}

	let copy_failures = check-copies ($lint.copies? | default [])
	let shared_failures = check-shares ($lint.shares? | default [])
	let vet_failures = check-vet

	let failures = $copy_failures | append $shared_failures | append $vet_failures
	if ($failures | is-not-empty) {
		$failures | each { |f| print -e $f } | ignore
		exit 1
	}
}

def check-copies [checks: list] {
	$checks | each { |check|
		let first = $env.PWD | path join $check.0
		if not ($first | path exists) {
			[$"✗ ($check.0) not found"]
		} else {
			let canonical = open $first --raw
			$check | skip 1 | each { |file|
				let path = $env.PWD | path join $file
				if not ($path | path exists) {
					$"✗ ($file) not found"
				} else if (open $path --raw) != $canonical {
					$"✗ ($file) differs from ($check.0)\n  Run: cp ($check.0) ($file)"
				}
			}
		}
	} | flatten
}

# A pattern's first match agrees across its files. A pattern with a named
# group `v` compares that group instead, in every match: the version can then
# sit in context (`Sayt \*\*(?<v>...)`), and a file stating it twice states it
# the same both times.
export def check-shares [checks: list] {
	$checks | each { |check|
		let pattern = $check.pattern
		let named = ($pattern | str contains "(?<v>")
		let results = $check.files | each { |file|
			let path = $env.PWD | path join $file
			let matches = if ($path | path exists) { open $path --raw | parse -r ("(" + $pattern + ")") } else { [] }
			if ($matches | is-empty) {
				[{ file: $file, value: null, missing: true }]
			} else if $named {
				$matches | each { |m| { file: $file, value: $m.v, missing: false } }
			} else {
				[{ file: $file, value: ($matches | first | get capture0), missing: false }]
			}
		} | flatten
		let missing = $results | where missing | get file
		let found = $results | where { |r| not $r.missing }
		let unique = $found | get value | uniq

		let missing_errs = if ($missing | is-not-empty) {
			[$"✗ pattern '($pattern)' not found in: ($missing | str join ', ')"]
		} else { [] }

		let mismatch_errs = if ($unique | length) > 1 {
			let detail = $found | uniq | each { |v| $"  ($v.file): ($v.value)" } | str join "\n"
			[$"✗ pattern '($pattern)' mismatch:\n($detail)"]
		} else { [] }

		$missing_errs | append $mismatch_errs
	} | flatten
}

def check-vet [] {
	glob *.cue
		| where { |it| $it | path parse | get stem | path exists }
		| each { |file|
			let stem = $file | path parse | get stem
			let ext = $stem | path parse | get extension | fill -c text
			let result = do { run-cue vet -c ($file | path basename) $"($ext):($stem)" } | complete
			if $result.exit_code != 0 {
				$"✗ cue vet failed: ($file | path basename) against ($stem)"
			}
		}
}

