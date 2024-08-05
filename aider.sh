#!/bin/sh
echo aider "$@"
pkgx +pypa.github.io/pipx pipx run -q aider-chat "$@"
