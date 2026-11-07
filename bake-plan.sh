#!/usr/bin/env bash
set -euo pipefail
sayt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project=$1
bake_file=$2
shift 2
export MISE_LOCKED=0
mise tool-stub "$sayt_dir/compose.toml" --profile '*' -f "$project/compose.yaml" config \
  | mise tool-stub "$sayt_dir/buildx.toml" bake -f - -f "$project/$bake_file" "$@"
