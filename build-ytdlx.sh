#!/usr/bin/env bash
# ytdlx-build - adaptive yt-dlp source installer for Ubuntu/Debian
# Generated for Ubuntu 24.04, but detects compatible Debian-family systems.
set -Eeuo pipefail

PROGRAM="ytdlx-build"
REPO="https://github.com/yt-dlp/yt-dlp.git"
CHANNEL="nightly"          # stable | master
RUNTIME="auto"           # auto | deno | node | quickjs | none
PREFIX=""
NO_APT=0
NO_FFMPEG=0
FORCE=0
VERBOSE=0

MIN_PYTHON="3.10"
MIN_DENO="2.3.0"
MIN_NODE="22.0.0"
MIN_QJS_DATE="2023-12-09"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$PROGRAM" "$*"; }
warn() { printf '\033[1;33m[%s WARNING]\033[0m %s\n' "$PROGRAM" "$*" >&2; }
die()  { printf '\033[1;31m[%s ERROR]\033[0m %s\n' "$PROGRAM" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

version_ge() {
    if have dpkg; then
        dpkg --compare-versions "$1" ge "$2"
    else
        [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
    fi
}

usage() {
cat <<'TXT'
ytdlx-build - adaptive yt-dlp source builder/installer

Usage:
  ./ytdlx-build [options]
  ./ytdlx-build --doctor
  ./ytdlx-build --notes

Options:
  --channel stable|master
      Build latest stable tag or current upstream master.

  --runtime auto|deno|node|quickjs|none
      JavaScript runtime policy.
      auto prefers and installs Deno.

  --prefix PATH
      Installation root.
      Root/sudo default:
          /opt/ytdlx

      User default:
          ~/.local/share/ytdlx

  --no-apt
      Do not install OS dependencies automatically.

  --no-ffmpeg
      Do not require/install FFmpeg.

  --force
      Recreate Python venv and refresh selected runtime.

  -v, --verbose
      Verbose pip/build output.

  --doctor
      Detect host compatibility without installing.

  --notes
      Show compatibility information.

  -h, --help
      Show this help.

Installed commands:
  ytdlx
      yt-dlp wrapper pinned to selected JavaScript runtime.

  yt-dlp
      Direct executable from isolated Python environment.

  ytdlx-build
      Installed maintenance/rebuild command.
TXT
}

notes() {
cat <<TXT
YTDLX compatibility notes
=========================

Operating systems
-----------------
Primary target:
  Ubuntu 24.04 LTS

Also intended to work on:
  Ubuntu releases with Python >= $MIN_PYTHON
  Debian releases with Python >= $MIN_PYTHON

Other Linux distributions may work, but dependency installation
must generally be handled manually.

Python
------
Minimum:
  CPython >= $MIN_PYTHON

Ubuntu 24.04 normally provides Python 3.12.

The installer uses an isolated Python virtual environment and does
not install yt-dlp packages into Ubuntu's system Python.

JavaScript runtimes
-------------------
YouTube extraction increasingly depends on a supported JavaScript
runtime.

Preferred:
  Deno >= $MIN_DENO

Also supported:
  Node.js >= $MIN_NODE
  QuickJS >= $MIN_QJS_DATE

Auto mode prefers Deno.

Bun is intentionally not automatically selected because current
yt-dlp support for Bun is deprecated.

Architectures
-------------
Automatic Deno installation supports:

  x86_64
  amd64
  aarch64
  arm64

Other architectures can still work if a compatible JavaScript
runtime is already installed.

FFmpeg
------
ffmpeg and ffprobe are strongly recommended.

They are required for many operations involving:

  video/audio merging
  remuxing
  transcoding
  metadata
  thumbnails
  multi-stream downloads
  format conversion

Use --no-ffmpeg only for deliberately minimal installations.

Installation layout
-------------------

Root / sudo:

  /opt/ytdlx/
      src/
      venv/
      build-info.txt

  /usr/local/bin/ytdlx
  /usr/local/bin/yt-dlp
  /usr/local/bin/ytdlx-build

Unprivileged:

  ~/.local/share/ytdlx/
      src/
      venv/
      build-info.txt

  ~/.local/bin/ytdlx
  ~/.local/bin/yt-dlp
  ~/.local/bin/ytdlx-build

Channels
--------
stable
  Latest version-like upstream git tag.

master
  Current upstream master branch.

Master can be useful when a website changes and yt-dlp has already
merged a fix that has not reached a stable release.
TXT
}

os_info() {
    OS_ID="unknown"
    OS_VERSION="unknown"
    OS_NAME="Unknown Linux"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release

        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    fi

    ARCH="$(uname -m)"
}

python_version_of() {
    "$1" -c \
        'import sys; print(".".join(map(str, sys.version_info[:3])))' \
        2>/dev/null || true
}

find_python() {
    local c v

    PYTHON=""
    PYTHON_VERSION=""

    for c in \
        python3.14 \
        python3.13 \
        python3.12 \
        python3.11 \
        python3.10 \
        python3
    do
        if have "$c"; then
            v="$(python_version_of "$c")"

            if [[ -n "$v" ]] && version_ge "$v" "$MIN_PYTHON"; then
                PYTHON="$(command -v "$c")"
                PYTHON_VERSION="$v"
                return 0
            fi
        fi
    done

    return 1
}

deno_version() {
    deno --version 2>/dev/null |
        awk 'NR == 1 { print $2 }'
}

node_version() {
    node --version 2>/dev/null |
        sed 's/^v//'
}

qjs_version_text() {
    qjs --version 2>&1 |
        head -n1 || true
}

runtime_status() {
    local d="missing"
    local n="missing"
    local q="missing"

    if have deno; then
        d="$(deno_version)"
    fi

    if have node; then
        n="$(node_version)"
    fi

    if have qjs; then
        q="$(qjs_version_text)"
    fi

    printf 'Deno:    %s\n' "$d"
    printf 'Node:    %s\n' "$n"
    printf 'QuickJS: %s\n' "$q"
}

doctor() {
    os_info

    printf 'YTDLX host diagnostic\n'
    printf '=====================\n'

    printf 'OS:       %s\n' "$OS_NAME"
    printf 'Arch:     %s\n' "$ARCH"
    printf 'Kernel:   %s\n' "$(uname -sr)"

    if find_python; then
        printf 'Python:   %s (%s) - OK\n' \
            "$PYTHON_VERSION" \
            "$PYTHON"
    else
        printf 'Python:   no supported Python >= %s found\n' \
            "$MIN_PYTHON"
    fi

    if have ffmpeg; then
        printf 'FFmpeg:   %s\n' \
            "$(ffmpeg -version | head -n1)"
    else
        printf 'FFmpeg:   missing\n'
    fi

    if have ffprobe; then
        printf 'FFprobe:  present\n'
    else
        printf 'FFprobe:  missing\n'
    fi

    if have git; then
        printf 'Git:      %s\n' "$(git --version)"
    else
        printf 'Git:      missing\n'
    fi

    printf '\nJavaScript runtimes:\n'
    runtime_status

    printf '\nCompatibility assessment:\n'

    if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
        printf '  OS family: supported for automatic package setup\n'
    else
        printf '  OS family: manual dependency mode recommended\n'
    fi

    if find_python; then
        printf '  Python: compatible\n'
    else
        printf '  Python: incompatible/missing (need CPython >= %s)\n' \
            "$MIN_PYTHON"
    fi

    if have deno &&
       version_ge "$(deno_version)" "$MIN_DENO"
    then
        printf '  JS: Deno %s compatible (preferred)\n' \
            "$(deno_version)"

    elif have node &&
         version_ge "$(node_version)" "$MIN_NODE"
    then
        printf '  JS: Node %s compatible\n' \
            "$(node_version)"

    elif have qjs; then
        printf '  JS: QuickJS detected; verify it is >= %s\n' \
            "$MIN_QJS_DATE"

    else
        printf '  JS: no supported runtime detected\n'
        printf '      auto mode can install Deno on x86_64/aarch64\n'
    fi

    exit 0
}

# Handle informational commands early.
for arg in "$@"; do
    case "$arg" in
        --notes)
            notes
            exit 0
            ;;

        --doctor)
            doctor
            ;;
    esac
done

while [[ $# -gt 0 ]]; do
    case "$1" in

        --channel)
            [[ $# -ge 2 ]] ||
                die "--channel needs a value"

            CHANNEL="$2"
            shift 2
            ;;

        --runtime)
            [[ $# -ge 2 ]] ||
                die "--runtime needs a value"

            RUNTIME="$2"
            shift 2
            ;;

        --prefix)
            [[ $# -ge 2 ]] ||
                die "--prefix needs a value"

            PREFIX="$2"
            shift 2
            ;;

        --no-apt)
            NO_APT=1
            shift
            ;;

        --no-ffmpeg)
            NO_FFMPEG=1
            shift
            ;;

        --force)
            FORCE=1
            shift
            ;;

        -v|--verbose)
            VERBOSE=1
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            die "Unknown option: $1"
            ;;
    esac
done

[[ "$CHANNEL" == "stable" ||
   "$CHANNEL" == "master" ]] ||
    die "--channel must be stable or master"

case "$RUNTIME" in
    auto|deno|node|quickjs|none)
        ;;
    *)
        die "unsupported --runtime: $RUNTIME"
        ;;
esac

os_info

log "Detected: $OS_NAME / $ARCH"

# ------------------------------------------------------------
# Privilege / layout detection
# ------------------------------------------------------------

SUDO=()
CAN_SYSTEM=0

if [[ $EUID -eq 0 ]]; then
    CAN_SYSTEM=1

elif have sudo; then

    log "Requesting sudo access for package/system installation..."

    if sudo -v; then
        SUDO=(sudo)
        CAN_SYSTEM=1
    else
        warn "sudo authorization failed; using user mode where possible"
    fi
fi

if [[ -z "$PREFIX" ]]; then

    if [[ $CAN_SYSTEM -eq 1 ]]; then
        PREFIX="/opt/ytdlx"
    else
        PREFIX="$HOME/.local/share/ytdlx"
    fi
fi

if [[ "$PREFIX" == /opt/* ||
      "$PREFIX" == /usr/*
]]
then

    [[ $CAN_SYSTEM -eq 1 ]] ||
        die "Prefix $PREFIX requires root/sudo"

    BIN_DIR="/usr/local/bin"

else
    BIN_DIR="$HOME/.local/bin"
fi

SRC="$PREFIX/src"
VENV="$PREFIX/venv"
INFO="$PREFIX/build-info.txt"

# ------------------------------------------------------------
# Create installation directories
# ------------------------------------------------------------

if [[ $CAN_SYSTEM -eq 1 &&
      ( "$PREFIX" == /opt/* || "$PREFIX" == /usr/* )
]]
then

    "${SUDO[@]}" mkdir -p \
        "$PREFIX" \
        "$BIN_DIR"

    INSTALL_OWNER="${SUDO_USER:-$USER}"

    if [[ $EUID -eq 0 &&
          -z "${SUDO_USER:-}"
    ]]
    then
        INSTALL_OWNER="root"
    fi

    INSTALL_GROUP="$(
        id -gn "$INSTALL_OWNER" 2>/dev/null ||
        echo "$INSTALL_OWNER"
    )"

    "${SUDO[@]}" chown -R \
        "$INSTALL_OWNER:$INSTALL_GROUP" \
        "$PREFIX"

else

    mkdir -p \
        "$PREFIX" \
        "$BIN_DIR"
fi

# ------------------------------------------------------------
# Ubuntu / Debian dependency setup
# ------------------------------------------------------------

if [[ $NO_APT -eq 0 &&
      ( "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" )
]]
then

    if [[ $CAN_SYSTEM -eq 1 ]]; then

        log "Installing build/runtime dependencies with apt..."

        "${SUDO[@]}" apt-get update

        pkgs=(
            ca-certificates
            curl
            git
            python3
            python3-venv
            python3-pip
            python3-dev
            build-essential
            unzip
            zip
        )

        if [[ $NO_FFMPEG -eq 0 ]]; then
            pkgs+=(ffmpeg)
        fi

        "${SUDO[@]}" apt-get install -y \
            "${pkgs[@]}"

    else
        warn "No root/sudo: apt dependencies cannot be installed automatically"
    fi

elif [[ $NO_APT -eq 0 ]]; then

    warn "Automatic package installation only supports Ubuntu/Debian"
    warn "Existing tools will be detected instead"
fi

# ------------------------------------------------------------
# Verify base requirements
# ------------------------------------------------------------

have git ||
    die "git is required"

have curl ||
    die "curl is required"

find_python ||
    die "No compatible CPython >= $MIN_PYTHON found"

log "Using Python $PYTHON_VERSION at $PYTHON"

if [[ $NO_FFMPEG -eq 0 ]]; then

    have ffmpeg ||
        die "ffmpeg missing; install it or use --no-ffmpeg"

    have ffprobe ||
        die "ffprobe missing"
fi

# ------------------------------------------------------------
# Deno installer
# ------------------------------------------------------------

install_deno() {

    local deno_arch
    local url
    local tmp
    local zip
    local sumfile
    local install_target
    local expected
    local actual

    case "$ARCH" in

        x86_64|amd64)
            deno_arch="x86_64"
            ;;

        aarch64|arm64)
            deno_arch="aarch64"
            ;;

        *)
            die \
"Automatic Deno install unavailable for $ARCH.
Install Deno >= $MIN_DENO or Node >= $MIN_NODE manually."
            ;;
    esac

    install_target="$BIN_DIR/deno"

    tmp="$(mktemp -d)"

    zip="$tmp/deno.zip"
    sumfile="$tmp/deno.zip.sha256sum"

    url="https://github.com/denoland/deno/releases/latest/download/deno-${deno_arch}-unknown-linux-gnu.zip"

    log "Installing current official Deno for $ARCH..."

    curl \
        -fL \
        --retry 3 \
        --connect-timeout 20 \
        "$url" \
        -o "$zip"

    curl \
        -fL \
        --retry 3 \
        --connect-timeout 20 \
        "$url.sha256sum" \
        -o "$sumfile"

    expected="$(awk '{print $1}' "$sumfile")"

    actual="$(
        sha256sum "$zip" |
        awk '{print $1}'
    )"

    [[ -n "$expected" &&
       "$expected" == "$actual"
    ]] ||
        die "Deno SHA-256 verification failed"

    mkdir -p "$tmp/unpack"

    unzip -qo \
        "$zip" \
        -d "$tmp/unpack"

    [[ -x "$tmp/unpack/deno" ]] ||
        die "Deno archive did not contain executable 'deno'"

    if [[ "$BIN_DIR" == "/usr/local/bin" ]]; then

        "${SUDO[@]}" install \
            -m 0755 \
            "$tmp/unpack/deno" \
            "$install_target"

    else

        install \
            -m 0755 \
            "$tmp/unpack/deno" \
            "$install_target"
    fi

    export PATH="$BIN_DIR:$PATH"

    hash -r 2>/dev/null || true

    rm -rf "$tmp"
}

# ------------------------------------------------------------
# Runtime selection
# ------------------------------------------------------------

select_runtime() {

    JS_RUNTIME="none"
    JS_BIN=""
    JS_VERSION=""

    if [[ "$RUNTIME" == "none" ]]; then

        warn \
"JavaScript runtime disabled; full YouTube support may be reduced"

        return
    fi

    # --------------------------------------------------------
    # Deno
    # --------------------------------------------------------

    if [[ "$RUNTIME" == "auto" ||
          "$RUNTIME" == "deno"
    ]]
    then

        if have deno &&
           version_ge "$(deno_version)" "$MIN_DENO" &&
           [[ $FORCE -eq 0 ]]
        then

            JS_RUNTIME="deno"
            JS_BIN="$(command -v deno)"
            JS_VERSION="$(deno_version)"

            return
        fi

        install_deno

        if have deno &&
           version_ge "$(deno_version)" "$MIN_DENO"
        then

            JS_RUNTIME="deno"
            JS_BIN="$(command -v deno)"
            JS_VERSION="$(deno_version)"

            return
        fi

        if [[ "$RUNTIME" == "deno" ]]; then
            die "Deno install did not produce a compatible runtime"
        fi
    fi

    # --------------------------------------------------------
    # Node.js
    # --------------------------------------------------------

    if [[ "$RUNTIME" == "auto" ||
          "$RUNTIME" == "node"
    ]]
    then

        if have node &&
           version_ge "$(node_version)" "$MIN_NODE"
        then

            JS_RUNTIME="node"
            JS_BIN="$(command -v node)"
            JS_VERSION="$(node_version)"

            return
        fi

        if [[ "$RUNTIME" == "node" ]]; then
            die \
"Node >= $MIN_NODE is required; found $(node_version 2>/dev/null || echo none)"
        fi
    fi

    # --------------------------------------------------------
    # QuickJS
    # --------------------------------------------------------

    if [[ "$RUNTIME" == "auto" ||
          "$RUNTIME" == "quickjs"
    ]]
    then

        if have qjs; then

            JS_RUNTIME="quickjs"
            JS_BIN="$(command -v qjs)"
            JS_VERSION="$(qjs_version_text)"

            return
        fi

        if [[ "$RUNTIME" == "quickjs" ]]; then
            die "QuickJS executable qjs was not found"
        fi
    fi

    die \
"No supported JavaScript runtime found.
Recommended: Deno >= $MIN_DENO"
}

select_runtime

if [[ "$JS_RUNTIME" != "none" ]]; then

    log \
"JavaScript runtime: $JS_RUNTIME $JS_VERSION ($JS_BIN)"
fi

# ------------------------------------------------------------
# yt-dlp source
# ------------------------------------------------------------

if [[ -d "$SRC/.git" ]]; then

    log "Refreshing existing yt-dlp source..."

    git -C "$SRC" \
        remote set-url \
        origin \
        "$REPO"

    git -C "$SRC" \
        fetch \
        --tags \
        --prune \
        origin

else

    log "Cloning yt-dlp source..."

    rm -rf "$SRC"

    git clone \
        "$REPO" \
        "$SRC"

    git -C "$SRC" \
        fetch \
        --tags \
        --prune \
        origin
fi

# ------------------------------------------------------------
# Select source channel
# ------------------------------------------------------------

if [[ "$CHANNEL" == "master" ]]; then

    git -C "$SRC" \
        checkout \
        -q \
        -B master \
        origin/master

    git -C "$SRC" \
        reset \
        --hard \
        origin/master

    BUILD_REF="master@$(git -C "$SRC" rev-parse --short HEAD)"

else

    STABLE_TAG="$(
        git -C "$SRC" \
            tag \
            --list '[0-9][0-9][0-9][0-9].*' \
            --sort=-v:refname |
        head -n1
    )"

    [[ -n "$STABLE_TAG" ]] ||
        die "Could not determine latest stable yt-dlp tag"

    git -C "$SRC" \
        checkout \
        -q \
        --detach \
        "$STABLE_TAG"

    BUILD_REF="$STABLE_TAG"
fi

log "Selected yt-dlp source: $BUILD_REF"

# ------------------------------------------------------------
# Python virtual environment
# ------------------------------------------------------------

if [[ $FORCE -eq 1 &&
      -d "$VENV"
]]
then

    log "Removing existing venv (--force)..."

    rm -rf "$VENV"
fi

if [[ ! -x "$VENV/bin/python" ]]; then

    "$PYTHON" -m venv "$VENV"
fi

# ------------------------------------------------------------
# Build/install yt-dlp
# ------------------------------------------------------------

log "Building/installing yt-dlp into isolated venv..."

"$VENV/bin/python" \
    -m pip install \
    --upgrade \
    pip \
    wheel \
    'hatchling>=1.27.0'

if [[ $VERBOSE -eq 1 ]]; then

    "$VENV/bin/python" \
        -m pip install \
        --upgrade \
        "yt-dlp[default] @ file://$SRC"

else

    "$VENV/bin/python" \
        -m pip install \
        -q \
        --upgrade \
        "yt-dlp[default] @ file://$SRC"
fi

[[ -x "$VENV/bin/yt-dlp" ]] ||
    die "yt-dlp executable was not created"

# ------------------------------------------------------------
# Install direct yt-dlp command
# ------------------------------------------------------------

if [[ "$BIN_DIR" == "/usr/local/bin" ]]; then

    "${SUDO[@]}" ln \
        -sfn \
        "$VENV/bin/yt-dlp" \
        "$BIN_DIR/yt-dlp"

else

    ln \
        -sfn \
        "$VENV/bin/yt-dlp" \
        "$BIN_DIR/yt-dlp"
fi

# ------------------------------------------------------------
# Create ytdlx wrapper
# ------------------------------------------------------------

WRAPPER_TMP="$(mktemp)"

{
    echo '#!/usr/bin/env bash'
    echo 'set -e'

    printf \
        'YTDLP=%q\n' \
        "$VENV/bin/yt-dlp"

    if [[ "$JS_RUNTIME" != "none" ]]; then

        printf \
            'exec "$YTDLP" --js-runtimes %q "$
