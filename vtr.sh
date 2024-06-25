#!/bin/sh
# We created this indirection until https://github.com/NathanVaughn/vscode-task-runner/issues/45 is fixed
# but even after that it is still worth to hide the magic.
echo vtr "$@"
pkgx +pypa.github.io/pipx pipx run -q vscode-task-runner "$@"
