# setup.nu — Install runtimes and tools
use tools.nu [run-mise]

export def --wrapped main [...args] {
	# Clear MISE_LOCKED so .mise.toml settings prevail.
	# sayt.sh sets MISE_LOCKED=0 for tool-stub compatibility,
	# but mise install should respect the config's locked setting.
	# See https://github.com/jdx/mise/discussions/7728
	do { hide-env -i MISE_LOCKED; run-mise install ...$args }
}
