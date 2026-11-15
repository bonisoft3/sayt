# config.nu — Shared config-loading for sayt verbs and built-in lint rules
use tools.nu [run-cue vrun verbosity]

const _self_dir = (path self | path dirname)

# A .say.nu's last value is the config, handed to cue as JSON on stdout.
const say_nu_loader = r#'const NU_LIB_DIRS = LIBDIRS
let config = do { source SAY_NU }
if ($config | describe -d).type != "record" { error make {msg: $"(SAY_NU) must end with a record, got ($config | describe)"} }
$config | to json'#

# A path relative-to that works with sibling directories like python relpath.
export def "path relpath" [base: string] {
	let target_parts = $in | path expand | path split
	let start_parts = $base | path expand | path split

	let common_len = ($target_parts | zip $start_parts | take while { $in.0 == $in.1 } | length)
	let ups = ($start_parts | length) - $common_len

	let result = (if $ups > 0 { 1..$ups | each { ".." } } else { [] }) | append ($target_parts | skip
		$common_len)

	if ($result | is-empty) { "." } else { $result | path join }
}

export def load-config [--config: string] {
	let config = $config | default ($env.SAYT_CONFIG? | default ".say.{cue,yaml,yml,json,toml,nu}")
	# Step 1: Find and merge all .say.* config files
	let default = $_self_dir | path join "config.cue" | path relpath $env.PWD
	let config_files = glob $config | each { |f| $f | path relpath $env.PWD } | append $default
  let nu_file = $config_files | where { |it| $it | str ends-with ".nu" } | get 0?
  let cue_files = $config_files | where { |it| not ($it | str ends-with ".nu") }
	# Step 2: Generate merged configuration
	let nu_result = if ($nu_file | is-empty) {
		if (verbosity) != "quiet" { print -e -n $"echo | " }
		$in
	} else {
		let loader = $say_nu_loader | str replace --all SAY_NU ($nu_file | to nuon) | str replace LIBDIRS ([$_self_dir] | to nuon)
		vrun --trail="| " nu -n -c $loader
	}
  let stdin = if ($nu_file | is-empty) { [-] } else { [json: -] }
  let config = $nu_result | run-cue export ...$cue_files --out yaml ...$stdin | from yaml
	return $config
}
