#!/bin/sh
set -e

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sayt"
MISE_VERSION="v2026.3.5"
MISE_DIR="$CACHE_DIR/mise-$MISE_VERSION"
MISE_BIN="$MISE_DIR/mise"

if [ ! -x "$MISE_BIN" ]; then
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$OS" in
    linux) OS_NAME="linux" ;;
    darwin) OS_NAME="macos" ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
  esac

  case "$ARCH" in
    x86_64|amd64) ARCH_NAME="x64" ;;
    aarch64|arm64) ARCH_NAME="arm64" ;;
    armv7l|armv7*) ARCH_NAME="armv7" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac

  SUFFIX=""
  EXT=""
  if [ "$OS_NAME" = "linux" ]; then
    SUFFIX="-musl"
  fi

  if [ -n "${SAYT_MISE_URL:-}" ]; then
    MISE_URL="$SAYT_MISE_URL"
  else
    BASE="${SAYT_MISE_BASE:-https://github.com/jdx/mise/releases/download/$MISE_VERSION}"
    BASE="${BASE%/}"
    MISE_URL="$BASE/mise-${MISE_VERSION}-${OS_NAME}-${ARCH_NAME}${SUFFIX}${EXT}"
  fi

  mkdir -p "$MISE_DIR"
  curl -fsSL "$MISE_URL" -o "$MISE_BIN"
  chmod +x "$MISE_BIN"
fi

NU_STUB="$ROOT_DIR/nu.musl.toml"
if [ -f "/lib64/ld-linux-x86-64.so.2" ] || [ -f "/lib/ld-linux-aarch64.so.1" ] || [ -f "/lib/ld-linux-armhf.so.3" ]; then
  NU_STUB="$ROOT_DIR/nu.toml"
elif [ ! -f "$NU_STUB" ]; then
  NU_STUB="$ROOT_DIR/nu.toml"
fi

if [ -f "$ROOT_DIR/.mise.toml" ]; then
  "$MISE_BIN" trust -y -a -q
fi

MISE_LOCKED=0 exec "$MISE_BIN" tool-stub "$NU_STUB" "$ROOT_DIR/sayt.nu" "$@"
