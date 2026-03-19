# vscode.nu — VS Code tasks.json task runner
use tools.nu [run-cue vrun]

def vtr-to-argv [task: record] {
  let cmd_tokens = if ($task.cmd | str contains ' ') { $task.cmd | split row ' ' } else { [ $task.cmd ] }
  let base_args = if ($task.args | describe | str contains "list") { $task.args } else { [ $task.args ] }
  $base_args | prepend $cmd_tokens | flatten
}

# Resolve the cwd from a task record, expanding ${workspaceFolder} to $env.PWD.
def vtr-resolve-cwd [task: record] {
  if ("cwd" in ($task | columns)) {
    $task.cwd | str replace '${workspaceFolder}' $env.PWD
  } else {
    null
  }
}

export def --wrapped vtr [...args: string] {
  if (not (".vscode/tasks.json" | path exists)) {
    print -e "vscode tasks file not found at .vscode/tasks.json"
    exit -1
  }
  let label = if ($args | is-empty) { "build" } else { $args | first }
  let extra_args = $args | skip 1
  let script_dir = ($env.FILE_PWD? | default ($env.PWD | path join "plugins/sayt"))
  let platform = if ($nu.os-info.name == 'Windows') { "windows" } else { "posix" }
  let cue_result = (run-cue export -p vscode ($script_dir | path join "vscode.cue") ($script_dir | path join "vscode_runner.cue") .vscode/tasks.json -t $'label=($label)' -t $'platform=($platform)' --out json | from json)

  # Run dependency tasks first
  for dep in $cue_result.deps {
    let dep_argv = vtr-to-argv $dep
    let dep_cwd = vtr-resolve-cwd $dep
    let orig_pwd = $env.PWD
    if $dep_cwd != null {
      cd $dep_cwd
    }
    vrun ($dep_argv | first) ...($dep_argv | skip 1)
    cd $orig_pwd
  }

  # Run the main command
  let argv = (vtr-to-argv $cue_result.command | append $extra_args)
  let cmd_cwd = vtr-resolve-cwd $cue_result.command
  let orig_pwd = $env.PWD
  if $cmd_cwd != null {
    cd $cmd_cwd
  }
  vrun ($argv | first) ...($argv | skip 1)
  cd $orig_pwd
}
