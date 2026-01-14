#!/usr/bin/env bash
#
# Dexicon CLI Installer
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/Dexicon-AI/get-dexicon-cli/main/install.sh | sh
#
# Environment variables:
#   DEXICON_VERSION - Install a specific version (e.g., "v0.2.1"). Default: latest
#   DEXICON_INSTALL_DIR - Directory for symlink (BIN_DIR). Default: /usr/local/bin or ~/.local/bin
#   DEXICON_LIB_DIR - Directory for binary (LIB_DIR). Default: /usr/local/lib or ~/.local/lib
#

set -euo pipefail

REPO="Dexicon-AI/get-dexicon-cli"
BINARY_NAME="dexicon"

# Determine if a path is writable or can be created
# Returns 0 if path is writable, or if path doesn't exist but its parent is writable
is_path_usable() {
    local path="$1"
    if [ -d "$path" ] && [ -w "$path" ]; then
        return 0
    elif [ ! -e "$path" ]; then
        local parent
        parent="$(dirname "$path")"
        if [ -d "$parent" ] && [ -w "$parent" ]; then
            return 0
        fi
    fi
    return 1
}

# Set LIB_DIR: where the binary will be installed
if [ -n "${DEXICON_LIB_DIR:-}" ]; then
    LIB_DIR="$DEXICON_LIB_DIR"
elif is_path_usable "/usr/local/lib"; then
    LIB_DIR="/usr/local/lib"
else
    LIB_DIR="${HOME}/.local/lib"
fi

# Set BIN_DIR: where the symlink will be created
if [ -n "${DEXICON_INSTALL_DIR:-}" ]; then
    BIN_DIR="$DEXICON_INSTALL_DIR"
elif is_path_usable "/usr/local/bin"; then
    BIN_DIR="/usr/local/bin"
else
    BIN_DIR="${HOME}/.local/bin"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}==>${NC} $1"
}

success() {
    echo -e "${GREEN}==>${NC} $1"
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

# Detect OS
detect_os() {
    local os
    os="$(uname -s)"
    case "$os" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        *) error "Unsupported operating system: $os" ;;
    esac
}

# Detect architecture
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) error "Unsupported architecture: $arch" ;;
    esac
}

# Get the latest version from GitHub releases
get_latest_version() {
    local latest
    latest=$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$latest" ]; then
        error "Failed to fetch latest version. Please check your internet connection or specify DEXICON_VERSION."
    fi
    echo "$latest"
}

# Download and install
install() {
    local os arch version binary_name download_url tmp_dir

    os=$(detect_os)
    arch=$(detect_arch)

    # Check for arm64 on Linux (not supported yet)
    if [ "$os" = "linux" ] && [ "$arch" = "arm64" ]; then
        error "Linux ARM64 is not currently supported. Please use Linux AMD64 or macOS."
    fi

    # Get version
    if [ -n "${DEXICON_VERSION:-}" ]; then
        version="$DEXICON_VERSION"
        info "Installing Dexicon CLI $version..."
    else
        info "Fetching latest version..."
        version=$(get_latest_version)
        info "Installing Dexicon CLI $version..."
    fi

    binary_name="dexicon-cli-${os}-${arch}"
    download_url="https://github.com/${REPO}/releases/download/${version}/${binary_name}"

    info "Detected: $os/$arch"
    info "Downloading from: $download_url"

    # Create temp directory
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    # Download binary
    if ! curl -sSL --fail -o "${tmp_dir}/${BINARY_NAME}" "$download_url"; then
        error "Failed to download binary. Please check if version '$version' exists."
    fi

    # Make executable
    chmod +x "${tmp_dir}/${BINARY_NAME}"

    # Install binary to LIB_DIR
    info "Installing binary to ${LIB_DIR}/${BINARY_NAME}..."

    # Create LIB_DIR if it doesn't exist
    if [ ! -d "$LIB_DIR" ]; then
        if [ -w "$(dirname "$LIB_DIR")" ]; then
            mkdir -p "$LIB_DIR"
        else
            info "Requesting sudo access to create $LIB_DIR..."
            sudo mkdir -p "$LIB_DIR"
        fi
    fi

    if [ -w "$LIB_DIR" ]; then
        mv "${tmp_dir}/${BINARY_NAME}" "${LIB_DIR}/${BINARY_NAME}"
        # Remove macOS quarantine attribute
        if [ "$(uname -s)" = "Darwin" ]; then
            xattr -d com.apple.quarantine "${LIB_DIR}/${BINARY_NAME}" 2>/dev/null || true
        fi
    else
        info "Requesting sudo access to install to $LIB_DIR..."
        sudo mv "${tmp_dir}/${BINARY_NAME}" "${LIB_DIR}/${BINARY_NAME}"
        # Remove macOS quarantine attribute (needs sudo)
        if [ "$(uname -s)" = "Darwin" ]; then
            sudo xattr -d com.apple.quarantine "${LIB_DIR}/${BINARY_NAME}" 2>/dev/null || true
        fi
    fi

    # Create symlink in BIN_DIR
    info "Creating symlink in ${BIN_DIR}/${BINARY_NAME}..."

    # Create BIN_DIR if it doesn't exist
    if [ ! -d "$BIN_DIR" ]; then
        if [ -w "$(dirname "$BIN_DIR")" ]; then
            mkdir -p "$BIN_DIR"
        else
            info "Requesting sudo access to create $BIN_DIR..."
            sudo mkdir -p "$BIN_DIR"
        fi
    fi

    # Remove any existing file or symlink at the target path
    if [ -e "${BIN_DIR}/${BINARY_NAME}" ] || [ -L "${BIN_DIR}/${BINARY_NAME}" ]; then
        if [ -w "$BIN_DIR" ]; then
            rm -f "${BIN_DIR}/${BINARY_NAME}"
        else
            sudo rm -f "${BIN_DIR}/${BINARY_NAME}"
        fi
    fi

    # Create the symlink
    if [ -w "$BIN_DIR" ]; then
        ln -sf "${LIB_DIR}/${BINARY_NAME}" "${BIN_DIR}/${BINARY_NAME}"
    else
        info "Requesting sudo access to create symlink in $BIN_DIR..."
        sudo ln -sf "${LIB_DIR}/${BINARY_NAME}" "${BIN_DIR}/${BINARY_NAME}"
    fi

    # Verify installation
    if command -v "$BINARY_NAME" &> /dev/null; then
        success "Dexicon CLI installed successfully!"
        echo ""
        "$BINARY_NAME" --version 2>/dev/null || "$BINARY_NAME" version
        echo ""
        success "Get started with: dexicon init"
    else
        warn "Installation complete, but '${BINARY_NAME}' is not in your PATH."
        echo "Add ${BIN_DIR} to your PATH, or run:"
        echo "  ${BIN_DIR}/${BINARY_NAME} --version"
    fi
}

# Run installer
install
