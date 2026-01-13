#!/usr/bin/env bash
#
# Dexicon CLI Installer
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/Dexicon-AI/get-dexicon-cli/main/install.sh | sh
#
# Environment variables:
#   DEXICON_VERSION - Install a specific version (e.g., "v0.2.1"). Default: latest
#   DEXICON_INSTALL_DIR - Installation directory. Default: /usr/local/bin
#

set -euo pipefail

REPO="Dexicon-AI/get-dexicon-cli"
BINARY_NAME="dexicon"
TMP_DIR=""

# Determine install directories based on write permissions
if [ -w "/usr/local/lib" ] && [ -w "/usr/local/bin" ]; then
    LIB_DIR="${DEXICON_LIB_DIR:-/usr/local/lib/dexicon-cli}"
    BIN_DIR="${DEXICON_INSTALL_DIR:-/usr/local/bin}"
else
    LIB_DIR="${DEXICON_LIB_DIR:-$HOME/.local/lib/dexicon-cli}"
    BIN_DIR="${DEXICON_INSTALL_DIR:-$HOME/.local/bin}"
fi

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

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
    local os arch version archive_name download_url

    os=$(detect_os)
    arch=$(detect_arch)

    # Check for arm64 on Linux (not supported yet)
    if [ "$os" = "linux" ] && [ "$arch" = "arm64" ]; then
        error "Linux ARM64 is not currently supported. Please use Linux AMD64 or macOS."
    fi

    # Get version
    if [ -n "${DEXICON_VERSION:-}" ]; then
        version="$DEXICON_VERSION"
    else
        info "Fetching latest version..."
        version=$(get_latest_version)
    fi
    info "Installing Dexicon CLI $version..."

    archive_name="dexicon-cli-${os}-${arch}.tar.gz"
    download_url="https://github.com/${REPO}/releases/download/${version}/${archive_name}"

    info "Detected: $os/$arch"
    info "Downloading from: $download_url"

    # Create temp directory
    TMP_DIR=$(mktemp -d)

    # Download archive
    if ! curl -sSL --fail -o "${TMP_DIR}/${archive_name}" "$download_url"; then
        error "Failed to download archive. Please check if version '$version' exists."
    fi

    # Extract archive
    info "Extracting archive..."
    tar -xzf "${TMP_DIR}/${archive_name}" -C "${TMP_DIR}"

    # Verify extraction
    if [ ! -f "${TMP_DIR}/dexicon-cli/${BINARY_NAME}" ]; then
        error "Failed to extract binary. Archive may be corrupted."
    fi

    # Make executable
    chmod +x "${TMP_DIR}/dexicon-cli/${BINARY_NAME}"

    # Create directories if needed
    mkdir -p "$(dirname "$LIB_DIR")" "$BIN_DIR"

    # Remove existing installation
    if [ -d "$LIB_DIR" ]; then
        info "Removing existing installation..."
        rm -rf "$LIB_DIR"
    fi
    if [ -L "${BIN_DIR}/${BINARY_NAME}" ]; then
        rm -f "${BIN_DIR}/${BINARY_NAME}"
    fi

    # Install the full dexicon-cli directory
    info "Installing to ${LIB_DIR}..."
    mv "${TMP_DIR}/dexicon-cli" "$LIB_DIR"

    # Remove macOS quarantine attribute
    if [ "$os" = "darwin" ]; then
        xattr -dr com.apple.quarantine "$LIB_DIR" 2>/dev/null || true
    fi

    # Create symlink in bin directory
    info "Creating symlink in ${BIN_DIR}..."
    ln -sf "${LIB_DIR}/${BINARY_NAME}" "${BIN_DIR}/${BINARY_NAME}"

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
