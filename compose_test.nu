use std/assert
use tools.nu [mise-bin]

const path_self = path self

# A project's COMPOSE_PROJECT_NAME template runs `mise tool-stub` through
# `exec()`, and a stub with a cold cache resolves that same `[env]`: a child
# that still saw MISE_SHELL took the exec branch again, without bound. This
# renders the template's two clearing prefixes, the ones its `exec()` commands
# start with, around a child that reports the variable instead of recursing.
def test_exec_child_runs_without_mise_shell [] {
	let dir = (mktemp -d)
	# A backslash in the probe's path on every platform, not only Windows: a
	# Tera literal reads backslash escapes, so each must reach it doubled.
	let probe_dir = ($dir | path join 'a\Users')
	mkdir $probe_dir
	let probe = ($probe_dir | path join probe.nu)
	"print ($env.MISE_SHELL? | default '')" | save $probe
	let tera = {|path| $path | str replace -a '\' '\\' }
	let child = $'"(do $tera $nu.current-exe)" "(do $tera $probe)"'
	[
		"[env]"
		("CLEARED = '''{% if os() == 'windows' %}{{ exec(command='(set MISE_SHELL=) && " + $child + "') }}{% else %}{{ exec(command='MISE_SHELL= " + $child + "') }}{% endif %}'''")
		# The same shape clearing another variable, so neither command starts with
		# the quote cmd /c would strip.
		("INHERITED = '''{% if os() == 'windows' %}{{ exec(command='(set SAYT_PROBE=) && " + $child + "') }}{% else %}{{ exec(command='SAYT_PROBE= " + $child + "') }}{% endif %}'''")
	] | str join "\n" | save ($dir | path join mise.toml)
	let mise = (mise-bin)
	let r = (do {
		cd $dir
		with-env {MISE_SHELL: "zsh", MISE_TRUSTED_CONFIG_PATHS: $dir} { ^$mise env --json | complete }
	})
	assert equal $r.exit_code 0 $r.stderr
	let env_out = ($r.stdout | from json)
	# Without the prefix the child sees it, so the probe measures something.
	assert equal $env_out.INHERITED "zsh"
	assert equal $env_out.CLEARED ""
	rm -rf $dir
}

def main [] {
	test_exec_child_runs_without_mise_shell
	print "compose_test: all passed"
}
