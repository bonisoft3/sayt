# lint-version.nu — Checks all version copies match the canonical VERSION file
use tools.nu [run-cue]

export def main [] {
	let v = open ($env.FILE_PWD | path join "VERSION") | str trim
	let bare = $v | str replace "v" ""

	let checks = [
		[file expected];
		["saytw" $v]
		["saytw.ps1" $v]
		["sayt.zig" $v]
		["compose.yaml" $v]
		["config.cue" $v]
		[".claude-plugin/plugin.json" $bare]
		[".claude-plugin/marketplace.json" $bare]
	]

	let failures = $checks | where { |c|
		let path = $env.FILE_PWD | path join $c.file
		not (open $path --raw | str contains $c.expected)
	}

	if ($failures | is-not-empty) {
		print -e $"Version drift \(canonical: ($v)\):"
		$failures | each { |f| print -e $"  ✗ ($f.file)" } | ignore
		exit 1
	}
	print $"All version strings match ($v)"
}
