#!/usr/bin/env nu
# Tests for --task flag: go-task delegation, "say verb" naming, CLI_ARGS passthrough
# Run with: nu task_flag_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running --task flag tests...\n"

	test_task_flag_calls_say_verb_task
	test_task_flag_passes_cli_args
	test_task_flag_no_args_calls_say_verb
	test_task_flag_with_sayt_dir_set
	test_task_flag_rejects_unknown_verb
	test_task_flag_sayt_resolves_from_saytw_in_cwd
	test_task_flag_sayt_resolves_from_repo_root_saytw

	print "\nAll --task flag tests passed!"
}

def make-task-dir [] {
	let tmpdir = (mktemp -d)
	# Initialize a git repo so MONOREPO_ROOT resolves
	git -C $tmpdir init --quiet
	$tmpdir
}

# Helper: create a Taskfile that echoes what was called
def write-echo-taskfile [dir: string] {
	$'version: "3"

vars:
  SAYT:
    sh: echo "${SAYT_DIR:+nu ${SAYT_DIR}/sayt.nu}"

tasks:
  say generate:
    desc: "test generate"
    cmds:
      - echo "CALLED_GENERATE {{.CLI_ARGS}}"

  say build:
    desc: "test build"
    cmds:
      - echo "CALLED_BUILD {{.CLI_ARGS}}"

  say setup:
    desc: "test setup"
    cmds:
      - echo "CALLED_SETUP {{.CLI_ARGS}}"

  say help:
    desc: "test help"
    cmds:
      - echo "CALLED_HELP {{.CLI_ARGS}}"
' | save ($dir | path join "Taskfile.yaml")
}

def test_task_flag_calls_say_verb_task [] {
	print "test --task maps verb to 'say <verb>' task..."
	let tmpdir = (make-task-dir)
	write-echo-taskfile $tmpdir
	let result = (do { nu sayt.nu --task -d $tmpdir generate } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code)"
	assert ($result.stdout | str contains "CALLED_GENERATE") "expected CALLED_GENERATE in output"
	rm -rf $tmpdir
}

def test_task_flag_passes_cli_args [] {
	print "test --task passes extra args via CLI_ARGS..."
	let tmpdir = (make-task-dir)
	write-echo-taskfile $tmpdir
	let result = (do { nu sayt.nu --task -d $tmpdir generate --force --verbose } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code)"
	assert ($result.stdout | str contains "--force") "expected --force in output"
	assert ($result.stdout | str contains "--verbose") "expected --verbose in output"
	rm -rf $tmpdir
}

def test_task_flag_no_args_calls_say_verb [] {
	print "test --task with no extra args works..."
	let tmpdir = (make-task-dir)
	write-echo-taskfile $tmpdir
	let result = (do { nu sayt.nu --task -d $tmpdir help } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code)"
	assert ($result.stdout | str contains "CALLED_HELP") "expected CALLED_HELP in output"
	rm -rf $tmpdir
}

def test_task_flag_with_sayt_dir_set [] {
	print "test --task sets SAYT_DIR env for Taskfile..."
	let tmpdir = (make-task-dir)
	$'version: "3"

tasks:
  say help:
    desc: "print SAYT_DIR"
    cmds:
      - echo "SAYT_DIR=${SAYT_DIR}"
' | save ($tmpdir | path join "Taskfile.yaml")
	let result = (do { nu sayt.nu --task -d $tmpdir help } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code)"
	assert ($result.stdout | str contains "SAYT_DIR=") "expected SAYT_DIR= in output"
	assert ($result.stdout | str contains "sayt") "SAYT_DIR should contain sayt path"
	rm -rf $tmpdir
}

def test_task_flag_rejects_unknown_verb [] {
	print "test --task rejects unknown verb before delegating..."
	let tmpdir = (make-task-dir)
	write-echo-taskfile $tmpdir
	let result = (do { nu sayt.nu --task -d $tmpdir check } | complete)
	assert ($result.stderr | str contains "Unknown subcommand") "expected Unknown subcommand in stderr"
	# Should NOT have called any task
	assert (not ($result.stdout | str contains "CALLED_")) "should not delegate to task for unknown verb"
	rm -rf $tmpdir
}

def test_task_flag_sayt_resolves_from_saytw_in_cwd [] {
	print "test SAYT var resolves ./saytw when present..."
	let tmpdir = (make-task-dir)
	# Create a fake saytw that echoes its args
	'#!/bin/sh
echo "SAYTW_CWD $@"
' | save ($tmpdir | path join "saytw")
	chmod +x ($tmpdir | path join "saytw")
	'version: "3"

vars:
  SAYT:
    sh: |
      if [ -n "${SAYT_DIR}" ]; then
        echo "nu ${SAYT_DIR}/sayt.nu"
      elif [ -x "./saytw" ]; then
        echo "./saytw"
      else
        echo "sayt"
      fi

tasks:
  say invoke:
    desc: "call sayt"
    cmds:
      - "{{.SAYT}} generate {{.CLI_ARGS}}"
' | save ($tmpdir | path join "Taskfile.yaml")
	# Run without SAYT_DIR so it falls back to ./saytw
	let result = (do { task --dir $tmpdir "say invoke" } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code)"
	let out = $result.stdout
	assert ($out | str contains "SAYTW_CWD") "expected SAYTW_CWD ./saytw used"
	rm -rf $tmpdir
}

def test_task_flag_sayt_resolves_from_repo_root_saytw [] {
	print "test SAYT var resolves repo root saytw when cwd has none..."
	let tmpdir = (make-task-dir)
	# Create saytw at git repo root
	'#!/bin/sh
echo "SAYTW_ROOT $@"
' | save ($tmpdir | path join "saytw")
	chmod +x ($tmpdir | path join "saytw")
	# Create a subdirectory with a Taskfile (no local saytw)
	let subdir = ($tmpdir | path join "sub")
	mkdir $subdir
	'version: "3"

vars:
  MONOREPO_ROOT:
    sh: git rev-parse --show-toplevel
  SAYT:
    sh: |
      if [ -n "${SAYT_DIR}" ]; then
        echo "nu ${SAYT_DIR}/sayt.nu"
      elif [ -x "./saytw" ]; then
        echo "./saytw"
      elif [ -x "$(git rev-parse --show-toplevel)/saytw" ]; then
        echo "$(git rev-parse --show-toplevel)/saytw"
      else
        echo "sayt"
      fi

tasks:
  say invoke:
    desc: "call sayt"
    cmds:
      - "{{.SAYT}} generate {{.CLI_ARGS}}"
' | save ($subdir | path join "Taskfile.yaml")
	# Run from subdir without SAYT_DIR
	let result = (do { task --dir $subdir "say invoke" } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code)"
	let out = $result.stdout
	assert ($out | str contains "SAYTW_ROOT") "expected SAYTW_ROOT repo root saytw used"
	rm -rf $tmpdir
}
