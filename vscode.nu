# vscode.nu — VS Code tasks.json task runner
use tools.nu [run-cue run-mise]

const _self_dir = (path self | path dirname)

def vtr-to-argv [task: record] {
  let cmd_tokens = if ($task.cmd | str contains ' ') { $task.cmd | split row ' ' } else { [ $task.cmd ] }
  let base_args = if ($task.args | describe | str contains "list") { $task.args } else { [ $task.args ] }
  $base_args | prepend $cmd_tokens | flatten
}

# Resolve the cwd from a task record, expanding ${workspaceFolder} to $env.PWD.
# `cwd` in vscode tasks.json is meant for the VSCode UI's terminal launch and is
# expressed relative to the workspace root. When sayt invokes the same task from
# the project subdir (e.g. `cd guis/web && just build`), substituting PWD doubles
# the path (`guis/web/guis/web`). If the resolved path doesn't exist, return
# null — the cwd was never sayt's concern, only vscode's.
def vtr-resolve-cwd [task: record] {
  if ("cwd" not-in ($task | columns)) {
    return null
  }
  let resolved = ($task.cwd | str replace '${workspaceFolder}' $env.PWD)
  if ($resolved | path exists) { $resolved } else { null }
}

def run-task [argv: list<string>, envs: record] {
  let script = '
    let argv = ($env._SAYT_VTR_ARGV | from json)
    let envs = ($env._SAYT_VTR_ENVS | from json)
    hide-env _SAYT_VTR_ARGV _SAYT_VTR_ENVS
    # Mise preserves inherited PATH order in children; active pins must lead it.
    let tools = (^$env.SAYT_MISE_BIN bin-paths --json | from json | each { |tool| $tool.path | path dirname } | uniq)
    $env.PATH = ($tools ++ $env.PATH | uniq)
    let found = (which --all ($argv | first) | where type == external | get 0?.path)
    if ($found | is-not-empty) {
      with-env $envs { ^$found ...($argv | skip 1) }
    } else {
      let cmd = ($argv | each { |a| if ($a | into string | str contains " ") { $a | to nuon } else { $a } } | str join " ")
      with-env $envs { ^$nu.current-exe -c $cmd }
    }
  '
  with-env {_SAYT_VTR_ARGV: ($argv | to json --raw), _SAYT_VTR_ENVS: ($envs | to json --raw)} {
    run-mise exec -- $nu.current-exe -c $script
  }
}

export def --wrapped vtr [...args: string] {
  if (not (".vscode/tasks.json" | path exists)) {
    print -e "vscode tasks file not found at .vscode/tasks.json"
    exit -1
  }
  let label = if ($args | is-empty) { "build" } else { $args | first }
  let extra_args = $args | skip 1
  let script_dir = $_self_dir
  let platform = match $nu.os-info.name { "windows" => "windows", "macos" => "osx", _ => "linux" }
  let cue_result = (run-cue export -p vscode ($script_dir | path join "vscode.cue") ($script_dir | path join "vscode_runner.cue") .vscode/tasks.json -t $'label=($label)' -t $'platform=($platform)' --out json | from json)

  # Run dependency tasks first
  for dep in ($cue_result.deps? | default []) {
    let dep_argv = vtr-to-argv $dep
    let dep_cwd = vtr-resolve-cwd $dep
    let orig_pwd = $env.PWD
    if $dep_cwd != null {
      cd $dep_cwd
    }
    run-task $dep_argv ($dep.env? | default {})
    cd $orig_pwd
  }

  # Run the main command
  let argv = (vtr-to-argv $cue_result.command | append $extra_args)
  let cmd_cwd = vtr-resolve-cwd $cue_result.command
  let orig_pwd = $env.PWD
  if $cmd_cwd != null {
    cd $cmd_cwd
  }
  run-task $argv ($cue_result.command.env? | default {})
  cd $orig_pwd
}
