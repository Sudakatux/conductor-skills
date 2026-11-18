#!/bin/sh
# Find a conductor CLI that has `create-app` and `integration`, or install the pinned release.
#
#   sh ensure-cli.sh            # check only; exit 3 when missing
#   sh ensure-cli.sh --install  # download, verify sha256, install (no sudo, no Node)
#
# Success prints one line the agent uses for every later command:
#   CONDUCTOR_BIN=/absolute/path/to/conductor
#
# Install dir: $CONDUCTOR_CLI_DIR, else ~/.local/bin. Nothing else is touched:
# no shell startup files, no global npm, no sudo.
set -eu

# Pinned release. Bump all three together. sha256 values are GitHub's per-asset
# digests (gh api repos/<repo>/releases/tags/<tag> -q '.assets[]|.name+" "+.digest').
CLI_REPO="Sudakatux/conductor-cli"   # FORK ONLY: conductor-oss/conductor-cli once `create-app` ships
CLI_VERSION="v0.1.10-createapp.2"
sha_for() {
  case "$1" in
    conductor_darwin_amd64) echo 1a224209bbba0c67c3e7fe8b9b7753c08d59cea1096d4baa36a7929dd069af55 ;;
    conductor_darwin_arm64) echo c739fd61e89ba73e645c88674bc4b9af532c7c26c151ae3f6c5612ad9ed5c36b ;;
    conductor_linux_amd64)  echo fda5ac1563cc7bd995938569069faae2d46eeaefc9b7ac7302c96da771bb1cfc ;;
    conductor_linux_arm64)  echo d7ba2a280d988d1f806cd776b163294ea174e0d14d663708edab01a05afe16dc ;;
    *) echo "" ;;
  esac
}

DIR="${CONDUCTOR_CLI_DIR:-$HOME/.local/bin}"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# A usable CLI knows `create-app` (connect without a pasted secret) and `integration`
# (add an LLM provider with a hidden key prompt). Older ones are "too old".
has_login() { [ -x "$1" ] && "$1" create-app --help >/dev/null 2>&1 && "$1" integration add --help >/dev/null 2>&1; }

found() { echo "CONDUCTOR_BIN=$1"; exit 0; }

if c=$(command -v conductor 2>/dev/null) && has_login "$c"; then found "$c"; fi
if has_login "$DIR/conductor"; then found "$DIR/conductor"; fi

if [ "$INSTALL" -ne 1 ]; then
  if c=$(command -v conductor 2>/dev/null) || { [ -x "$DIR/conductor" ] && c="$DIR/conductor"; }; then
    echo "MISSING: $c lacks 'create-app' or 'integration' (too old)." >&2
  else
    echo "MISSING: no conductor CLI found." >&2
  fi
  echo "Ask the user, then run: sh \"$0\" --install  (installs $CLI_VERSION to $DIR)" >&2
  exit 3
fi

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) echo "unsupported OS $(uname -s); on Windows use ensure-cli.ps1" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
asset="conductor_${os}_${arch}"
want=$(sha_for "$asset")
[ -n "$want" ] || { echo "no pinned checksum for $asset" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/$CLI_REPO/releases/download/$CLI_VERSION/$asset"
echo "Downloading $url" >&2
curl -fsSL "$url" -o "$tmp/conductor"

if command -v shasum >/dev/null 2>&1; then
  got=$(shasum -a 256 "$tmp/conductor" | awk '{print $1}')
else
  got=$(sha256sum "$tmp/conductor" | awk '{print $1}')
fi
if [ "$got" != "$want" ]; then
  echo "CHECKSUM MISMATCH for $asset: expected $want, got $got. Not installed." >&2
  exit 1
fi

mkdir -p "$DIR"
chmod 755 "$tmp/conductor"
mv "$tmp/conductor" "$DIR/conductor"
has_login "$DIR/conductor" || { echo "installed $DIR/conductor but it has no 'create-app'" >&2; exit 1; }

case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo "Note: $DIR is not on PATH; use the full path below." >&2 ;;
esac
echo "Installed conductor $CLI_VERSION (sha256 verified)." >&2
found "$DIR/conductor"
