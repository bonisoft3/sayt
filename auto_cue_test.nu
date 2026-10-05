use std/assert
use auto-cue.nu [check-shares]

def in-scratch [files: record, body: closure] {
	let dir = (mktemp -d)
	$files | transpose name text | each { |f| $f.text | save ($dir | path join $f.name) } | ignore
	let out = (do { cd $dir; do $body })
	rm -rf $dir
	$out
}

# A named `v` group compares every match, so a document stating a version
# twice is held to it both times, not just where it first names it.
def test_named_group_compares_every_match [] {
	let failures = (in-scratch {pin: 'Sayt **1.2.3**', doc: "Sayt **1.2.3**\nsayt/v1.2.4/saytw"} {
		check-shares [{pattern: '(?:Sayt \*\*|sayt/v)(?<v>\d+\.\d+\.\d+)', files: [pin doc]}]
	})
	assert equal ($failures | length) 1
	assert ($failures.0 | str contains "doc: 1.2.4")
	let agreeing = (in-scratch {pin: 'Sayt **1.2.3**', doc: "Sayt **1.2.3**\nsayt/v1.2.3/saytw"} {
		check-shares [{pattern: '(?:Sayt \*\*|sayt/v)(?<v>\d+\.\d+\.\d+)', files: [pin doc]}]
	})
	assert equal $agreeing []
}

# Without one, only the first match counts, as the pins in sayt's own
# .say.cue rely on: compose.yaml names other versions after its own.
def test_unnamed_pattern_compares_the_first_match [] {
	let failures = (in-scratch {VERSION: 'v1.0.0', compose: "x: v1.0.0\nimage: v9.9.9"} {
		check-shares [{pattern: 'v\d+\.\d+\.\d+', files: [VERSION compose]}]
	})
	assert equal $failures []
}

def main [] {
	test_named_group_compares_every_match
	test_unnamed_pattern_compares_the_first_match
	print "auto_cue_test: all passed"
}
