#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CHANGED_PROFILE=0
CHANGED_ENV=0
CHANGED_PATH=0

# Always use the real system git — never a buildkit-compiled wrapper that may
# have been placed in TOM_BINARY_PATH.  We check well-known system locations
# first, then fall back to whatever is on PATH.
SYSTEM_GIT=""
for candidate in /usr/bin/git /usr/local/bin/git /opt/homebrew/bin/git; do
    if [[ -x "$candidate" ]]; then SYSTEM_GIT="$candidate"; break; fi
done
if [[ -z "$SYSTEM_GIT" ]]; then
    SYSTEM_GIT="$(command -v git 2>/dev/null || true)"
fi
if [[ -z "$SYSTEM_GIT" ]]; then
    echo "Error: git not found on the system. Please install git first."
    exit 1
fi

warn() {
    echo "⚠️  $1"
}

# ask_yes_no <prompt> [default]
#
# Prompts interactively when stdin is a terminal. When stdin is NOT a terminal
# (e.g. run over SSH with no controlling tty, as the fleet build does) it does
# not block: it applies <default> and reports the auto-decision. <default> is
# "y" or "n" (defaults to "n" when omitted). This is what keeps a non-interactive
# build from hanging — the previous `while read` loop spun forever on EOF because
# an empty response matched neither branch.
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    # Non-interactive: no tty on stdin → don't read, use the caller's default.
    if [[ ! -t 0 ]]; then
        case "$default" in
            y|yes) echo "$prompt [y/n]: y  (auto: non-interactive default)"; return 0 ;;
            *)     echo "$prompt [y/n]: n  (auto: non-interactive default)"; return 1 ;;
        esac
    fi

    while true; do
        # read returns non-zero on EOF; fall back to the default rather than spin.
        if ! read -r -p "$prompt [y/n]: " response; then
            case "$default" in y|yes) return 0 ;; *) return 1 ;; esac
        fi
        # Use tr for lowercase — compatible with macOS default Bash 3.2
        case "$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
        esac
    done
}

detect_platform() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return
    fi

    if [[ "$OSTYPE" == darwin* ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then
            echo "darwin-arm64"
        else
            echo "darwin-x64"
        fi
        return
    fi

    if [[ "$OSTYPE" == linux* ]]; then
        case "$(uname -m)" in
            aarch64|arm64) echo "linux-arm64" ;;
            armv7l|armhf) echo "linux-armhf" ;;
            *) echo "linux-x64" ;;
        esac
        return
    fi

    echo "unsupported"
}

# The shell startup files that every shell of the user reads — interactive or
# not, so an agent's tool shell, a script started from an editor and
# `ssh host 'cmd'` get the binaries too:
#   zsh  → ~/.zshenv (read by every zsh; ~/.zshrc is interactive only)
#   bash → ~/.bashrc, at its top: bash reads it for `ssh host 'cmd'`, and a
#          distribution's ~/.bashrc returns early for non-interactive shells,
#          so anything below that guard never runs there.
shell_env_files() {
    if [[ "${SHELL:-}" == *zsh ]] || [[ -e "$HOME/.zshenv" ]] || [[ -e "$HOME/.zshrc" ]]; then
        echo "$HOME/.zshenv"
    fi
    if [[ "${SHELL:-}" == *bash ]] || [[ -e "$HOME/.bashrc" ]]; then
        echo "$HOME/.bashrc"
    fi
}

ENV_BLOCK_BEGIN="# >>> tom binaries (managed by tom_build_kit/bootstrap_binaries.sh) >>>"
ENV_BLOCK_END="# <<< tom binaries <<<"

# shell_env_block <tom-binary-path> <platform>
shell_env_block() {
    printf '%s\n' "$ENV_BLOCK_BEGIN"
    printf 'export TOM_BINARY_PATH="%s"\n' "$1"
    printf 'case ":$PATH:" in *":$TOM_BINARY_PATH/%s:"*) ;; *) export PATH="$TOM_BINARY_PATH/%s:$PATH" ;; esac\n' "$2" "$2"
    printf '%s\n' "$ENV_BLOCK_END"
}

# write_shell_env_block <file> <block>
#
# Puts <block> at the top of <file>, replacing a block written earlier, and
# leaves every other line as it was.
write_shell_env_block() {
    local file="$1" block="$2" rest
    touch "$file"
    rest="$(awk -v b="$ENV_BLOCK_BEGIN" -v e="$ENV_BLOCK_END" '
        $0 == b { skip = 1; next }
        skip && $0 == e { skip = 0; next }
        !skip { print }' "$file")"
    { printf '%s\n' "$block"; [[ -n "$rest" ]] && printf '%s\n' "$rest"; } > "$file.tom_bootstrap.tmp"
    mv "$file.tom_bootstrap.tmp" "$file"
    echo "  Wrote the Tom binaries block to the top of $file"
    CHANGED_PROFILE=1
}

# Sourced (by test/bootstrap_binaries_test.dart): define the functions above,
# run nothing.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

PLATFORM_ARG=""
SETUP_SHELL=""
for arg in "$@"; do
    case "$arg" in
        --setup-shell) SETUP_SHELL=y ;;
        --no-setup-shell) SETUP_SHELL=n ;;
        -*) echo "Unknown option: $arg"; echo "Usage: $0 [--setup-shell|--no-setup-shell] [platform]"; exit 2 ;;
        *) PLATFORM_ARG="$arg" ;;
    esac
done

PLATFORM="$(detect_platform "$PLATFORM_ARG")"
if [[ "$PLATFORM" == "unsupported" ]]; then
    echo "Unsupported platform '$OSTYPE'. Use bootstrap_binaries.ps1 on Windows."
    exit 1
fi

echo "=== Bootstrap tom_build_kit binaries ($PLATFORM) ==="

TAC_LINK="$HOME/tac"
WORKSPACE_HINT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -e "$TAC_LINK" ]]; then
    warn "No $TAC_LINK symlink exists."
    TAC_TARGET=""
    # Only prompt when interactive; non-interactively accept the workspace hint
    # (and never let read's EOF non-zero status trip `set -e`).
    if [[ -t 0 ]]; then
        read -r -p "Enter workspace directory for $TAC_LINK [$WORKSPACE_HINT]: " TAC_TARGET || true
    fi
    TAC_TARGET="${TAC_TARGET:-$WORKSPACE_HINT}"
    ln -s "$TAC_TARGET" "$TAC_LINK"
    echo "Created symlink: $TAC_LINK -> $TAC_TARGET"
fi

if [[ ! -d "$TAC_LINK/tom_binaries" ]]; then
    warn "No tom_binaries directory found in $TAC_LINK"
    # Required for the build → auto-yes when non-interactive.
    if ask_yes_no "Clone tom_binaries into $TAC_LINK/tom_binaries?" y; then
        "$SYSTEM_GIT" clone https://github.com/al-the-bear/tom_binaries.git "$TAC_LINK/tom_binaries"
    else
        echo "Aborted: tom_binaries repository is required."
        exit 1
    fi
fi

DEFAULT_TOM_BINARY_PATH="$TAC_LINK/tom_binaries/tom"
if [[ -z "${TOM_BINARY_PATH:-}" ]]; then
    warn "TOM_BINARY_PATH is not defined; using $DEFAULT_TOM_BINARY_PATH."
    export TOM_BINARY_PATH="$DEFAULT_TOM_BINARY_PATH"
    CHANGED_ENV=1
fi

EXPECTED_PLATFORM_DIR="$TOM_BINARY_PATH/$PLATFORM"
if [[ ! -d "$EXPECTED_PLATFORM_DIR" ]]; then
    warn "Missing platform directory: $EXPECTED_PLATFORM_DIR"
    # Required output dir → auto-yes when non-interactive.
    if ask_yes_no "Create $EXPECTED_PLATFORM_DIR?" y; then
        mkdir -p "$EXPECTED_PLATFORM_DIR"
    else
        echo "Aborted: platform output directory is required."
        exit 1
    fi
fi

# TOM_BINARY_PATH and the platform directory on PATH, for every shell: the
# tools (testkit, buildkit, dcli, ...) are run by scripts and agents in
# non-interactive shells as much as by hand. The build itself addresses the
# binaries through TOM_BINARY_PATH and does not need this, so a non-interactive
# run (the fleet build over SSH) leaves the startup files alone unless it is
# given --setup-shell.
ENV_BLOCK="$(shell_env_block "$TOM_BINARY_PATH" "$PLATFORM")"
for env_file in $(shell_env_files); do
    if [[ "$(head -n 4 "$env_file" 2>/dev/null)" == "$ENV_BLOCK" ]]; then
        continue
    fi
    case "$SETUP_SHELL" in
        y) write_shell_env_block "$env_file" "$ENV_BLOCK" ;;
        n) warn "$env_file does not put the Tom binaries on PATH (--no-setup-shell)" ;;
        *)
            if ask_yes_no "Put TOM_BINARY_PATH and $EXPECTED_PLATFORM_DIR on PATH in $env_file (read by every shell)?" n; then
                write_shell_env_block "$env_file" "$ENV_BLOCK"
            else
                warn "$env_file does not put the Tom binaries on PATH; rerun with --setup-shell"
            fi
            ;;
    esac
done
if [[ ":$PATH:" != *":$EXPECTED_PLATFORM_DIR:"* ]]; then
    export PATH="$EXPECTED_PLATFORM_DIR:$PATH"
    CHANGED_PATH=1
fi

OUTPUT_DIR="$EXPECTED_PLATFORM_DIR"
echo "Output directory: $OUTPUT_DIR"

# --- Resolve dependencies ------------------------------------------------
# Clear stale Dart tool cache to avoid errors from old package resolutions.
if [[ -d .dart_tool ]]; then
    echo "Clearing stale .dart_tool cache..."
    rm -rf .dart_tool
fi

echo "Resolving dependencies..."
if ! dart pub get; then
    echo "Error: dart pub get failed. Check pubspec.yaml and network connectivity."
    exit 1
fi

if [[ ! -f lib/src/version.versioner.dart ]]; then
    cat > lib/src/version.versioner.dart <<'EOF'
// GENERATED FILE - DO NOT EDIT
// Bootstrap stub - will be regenerated

class BuildkitVersionInfo {
    BuildkitVersionInfo._();
    static const String version = '0.0.0';
    static const String buildTime = '1970-01-01T00:00:00.000000Z';
    static const String gitCommit = 'bootstrap';
    static const int buildNumber = 0;
    static const String dartSdkVersion = 'unknown';
    static String get versionShort => '$version+$buildNumber';
    static String get versionMedium =>
        '$version+$buildNumber.$gitCommit ($buildTime)';
    static String get versionLong =>
        '$version+$buildNumber.$gitCommit ($buildTime) [Dart $dartSdkVersion]';
}
EOF
fi

echo "Running versioner..."
if ! TOM_BOOTSTRAP_ALLOW_MISSING_SETUP=1 \
    dart run bin/buildkit.dart --scan . --no-recursive :versioner --variable-prefix buildkit; then
    warn "Versioner step failed during bootstrap; continuing with existing version file."
fi

TOOLS=(buildkit findproject)
COMPILED=0
FAILED=0
echo "Compiling tools..."
for tool in "${TOOLS[@]}"; do
    if [[ ! -f "bin/$tool.dart" ]]; then
        warn "bin/$tool.dart not found, skipping"
        continue
    fi
    echo "  Compiling $tool"
    if dart compile exe "bin/$tool.dart" -o "$OUTPUT_DIR/$tool"; then
        COMPILED=$((COMPILED + 1))
    else
        warn "Failed to compile $tool"
        FAILED=$((FAILED + 1))
    fi
done

# Create 'bk' convenience symlink for buildkit
if [[ -f "$OUTPUT_DIR/buildkit" && ! -e "$OUTPUT_DIR/bk" ]]; then
    ln -s buildkit "$OUTPUT_DIR/bk"
    echo "  Created symlink: bk -> buildkit"
fi

echo ""
if (( FAILED > 0 )); then
    echo "=== Bootstrap INCOMPLETE: $COMPILED compiled, $FAILED failed ==="
    echo "Check the errors above and retry."
    exit 1
fi
echo "=== Bootstrap complete ==="
echo "Compiled $COMPILED tools to $OUTPUT_DIR"

if (( CHANGED_PROFILE || CHANGED_ENV || CHANGED_PATH )); then
    echo ""
    echo "############################################################"
    echo "# ALERT: Shell/environment settings were changed.          #"
    echo "# Restart terminals and apps to ensure setup is available. #"
    echo "############################################################"
fi
