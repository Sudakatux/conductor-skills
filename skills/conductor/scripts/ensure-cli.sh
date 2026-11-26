#!/bin/sh
# Find a conductor CLI, or install the pinned release.
#
#   sh ensure-cli.sh                       # any conductor on PATH or in the install dir
#   sh ensure-cli.sh --need create-app     # one that has these commands (comma-separated:
#                                          #   create-app,integration); exit 3 when missing/too old
#   sh ensure-cli.sh --need create-app --install   # download, verify sha256, install (no sudo, no Node)
#
# Success prints one line the agent uses for every later command:
#   CONDUCTOR_BIN=/absolute/path/to/conductor
#
# Install dir: $CONDUCTOR_CLI_DIR, else ~/.local/bin. Nothing else is touched:
# no shell startup files, no global npm, no sudo. Windows: use ensure-cli.ps1.
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
NEED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --need) [ $# -ge 2 ] || { echo "--need takes a value (create-app, integration)" >&2; exit 2; }
            NEED="$NEED $(echo "$2" | tr ',' ' ')"; shift ;;
    --need=*) NEED="$NEED $(echo "${1#--need=}" | tr ',' ' ')" ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
for n in $NEED; do
  case "$n" in
    create-app|integration) ;;
    *) echo "unknown --need value: $n (create-app, integration)" >&2; exit 2 ;;
  esac
done

# A usable CLI is executable. With --need it must also know each named command:
# `create-app` (connect to Developer Edition without a pasted secret) and
# `integration` (the user adds an LLM provider with a hidden key prompt).
usable() {
  [ -x "$1" ] || return 1
  for n in $NEED; do
    case "$n" in
      create-app)  "$1" create-app --help >/dev/null 2>&1 || return 1 ;;
      integration) "$1" integration add --help >/dev/null 2>&1 || return 1 ;;
    esac
  done
  return 0
}

found() { echo "CONDUCTOR_BIN=$1"; exit 0; }

if c=$(command -v conductor 2>/dev/null) && usable "$c"; then found "$c"; fi
if usable "$DIR/conductor"; then found "$DIR/conductor"; fi

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
  *) windows=0 ;;
esac
ps1="$(dirname "$0")/ensure-cli.ps1"
need_csv=$(echo $NEED | tr ' ' ',')

if [ "$INSTALL" -ne 1 ]; then
  if c=$(command -v conductor 2>/dev/null) || { [ -x "$DIR/conductor" ] && c="$DIR/conductor"; }; then
    echo "MISSING: $c lacks one of: $need_csv (too old)." >&2
  else
    echo "MISSING: no conductor CLI found." >&2
  fi
  if [ "$windows" -eq 1 ]; then
    echo "Ask the user, then run: powershell -NoProfile -ExecutionPolicy Bypass -File \"$ps1\"${need_csv:+ -Need $need_csv} -Install" >&2
  else
    echo "Ask the user, then run: sh \"$0\"${need_csv:+ --need $need_csv} --install  (installs $CLI_VERSION to $DIR)" >&2
  fi
  exit 3
fi

if [ "$windows" -eq 1 ]; then
  echo "Windows (Git Bash/MSYS): install with powershell -NoProfile -ExecutionPolicy Bypass -File \"$ps1\"${need_csv:+ -Need $need_csv} -Install" >&2
  exit 1
fi
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) echo "unsupported OS $(uname -s)" >&2; exit 1 ;;
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
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$url" -o "$tmp/conductor" || { echo "download failed: $url" >&2; exit 1; }
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$tmp/conductor" "$url" || { echo "download failed: $url" >&2; exit 1; }
else
  echo "neither curl nor wget is installed; cannot download $url" >&2
  exit 1
fi

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
usable "$DIR/conductor" || { echo "installed $DIR/conductor but it lacks: $need_csv" >&2; exit 1; }

case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo "Note: $DIR is not on PATH; use the full path below." >&2 ;;
esac
echo "Installed conductor $CLI_VERSION (sha256 verified)." >&2
found "$DIR/conductor"
