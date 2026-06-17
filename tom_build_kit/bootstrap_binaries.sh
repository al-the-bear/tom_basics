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

ask_yes_no() {
    local prompt="$1"
    local response
    while true; do
        read -r -p "$prompt [y/n]: " response
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

detect_rc_file() {
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "${SHELL:-}" == *"zsh" ]]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.bashrc"
    fi
}

append_if_missing() {
    local file="$1"
    local line="$2"
    touch "$file"
    if ! grep -Fq "$line" "$file"; then
        echo "$line" >> "$file"
        CHANGED_PROFILE=1
    fi
}

PLATFORM="$(detect_platform "${1:-}")"
if [[ "$PLATFORM" == "unsupported" ]]; then
    echo "Unsupported platform '$OSTYPE'. Use bootstrap_binaries.ps1 on Windows."
    exit 1
fi

echo "=== Bootstrap tom_build_kit binaries ($PLATFORM) ==="

TAC_LINK="$HOME/tac"
WORKSPACE_HINT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -e "$TAC_LINK" ]]; then
    warn "No $TAC_LINK symlink exists."
    read -r -p "Enter workspace directory for $TAC_LINK [$WORKSPACE_HINT]: " TAC_TARGET
    TAC_TARGET="${TAC_TARGET:-$WORKSPACE_HINT}"
    ln -s "$TAC_TARGET" "$TAC_LINK"
    echo "Created symlink: $TAC_LINK -> $TAC_TARGET"
fi

if [[ ! -d "$TAC_LINK/tom_binaries" ]]; then
    warn "No tom_binaries directory found in $TAC_LINK"
    if ask_yes_no "Clone tom_binaries into $TAC_LINK/tom_binaries?"; then
        "$SYSTEM_GIT" clone https://github.com/al-the-bear/tom_binaries.git "$TAC_LINK/tom_binaries"
    else
        echo "Aborted: tom_binaries repository is required."
        exit 1
    fi
fi

DEFAULT_TOM_BINARY_PATH="$TAC_LINK/tom_binaries/tom"
if [[ -z "${TOM_BINARY_PATH:-}" ]]; then
    warn "TOM_BINARY_PATH is not defined."
    RC_FILE="$(detect_rc_file)"
    if ask_yes_no "Add TOM_BINARY_PATH=$DEFAULT_TOM_BINARY_PATH to $RC_FILE?"; then
        append_if_missing "$RC_FILE" "export TOM_BINARY_PATH=$DEFAULT_TOM_BINARY_PATH"
        export TOM_BINARY_PATH="$DEFAULT_TOM_BINARY_PATH"
        CHANGED_ENV=1
        # shellcheck disable=SC1090
        source "$RC_FILE" || true
    else
        echo "Aborted: TOM_BINARY_PATH is required."
        exit 1
    fi
fi

EXPECTED_PLATFORM_DIR="$TOM_BINARY_PATH/$PLATFORM"
if [[ ! -d "$EXPECTED_PLATFORM_DIR" ]]; then
    warn "Missing platform directory: $EXPECTED_PLATFORM_DIR"
    if ask_yes_no "Create $EXPECTED_PLATFORM_DIR?"; then
        mkdir -p "$EXPECTED_PLATFORM_DIR"
    else
        echo "Aborted: platform output directory is required."
        exit 1
    fi
fi

if [[ ":$PATH:" != *":$EXPECTED_PLATFORM_DIR:"* ]]; then
    warn "$EXPECTED_PLATFORM_DIR is not in PATH"
    RC_FILE="$(detect_rc_file)"
    if ask_yes_no "Add $EXPECTED_PLATFORM_DIR to PATH in $RC_FILE?"; then
        append_if_missing "$RC_FILE" "export PATH=\"\$PATH:$EXPECTED_PLATFORM_DIR\""
        export PATH="$PATH:$EXPECTED_PLATFORM_DIR"
        CHANGED_PATH=1
        # shellcheck disable=SC1090
        source "$RC_FILE" || true
    fi
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
    static String get versionMedium => '$version+$buildNumber.$gitCommit ($buildTime)';
    static String get versionLong => '$version+$buildNumber.$gitCommit ($buildTime) [Dart $dartSdkVersion]';
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
