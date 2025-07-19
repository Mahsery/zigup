#!/bin/bash
set -e

# ZigUp Installation Script
# Builds and installs ZigUp Zig version manager

echo "Installing ZigUp..."

# Function to detect platform
detect_platform() {
    local arch=$(uname -m)
    local os=$(uname -s)
    
    case $arch in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) echo "Unsupported architecture: $arch"; exit 1 ;;
    esac
    
    case $os in
        Linux) os="linux" ;;
        Darwin) os="macos" ;;
        *) echo "Unsupported OS: $os"; exit 1 ;;
    esac
    
    echo "${arch}-${os}"
}

# Function to download and setup temporary Zig
setup_temp_zig() {
    local platform=$(detect_platform)
    local temp_dir=$(mktemp -d)
    
    echo "Downloading Zig for $platform..."
    
    # Get latest stable version info
    local index_url="https://ziglang.org/download/index.json"
    local zig_info=$(curl -s "$index_url" | grep -A 20 '"0\.14\.1"' | head -30)
    local tarball_url=$(echo "$zig_info" | grep -A 5 "\"$platform\"" | grep '"tarball"' | cut -d'"' -f4)
    
    if [ -z "$tarball_url" ]; then
        echo "Error: Could not find Zig download for $platform"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo "Downloading from: $tarball_url"
    curl -L "$tarball_url" | tar -xJ -C "$temp_dir" --strip-components=1
    
    export PATH="$temp_dir:$PATH"
    echo "Temporary Zig installed to: $temp_dir"
    echo "$temp_dir"
}

# Check if zig is installed
TEMP_ZIG_DIR=""
if ! command -v zig &> /dev/null; then
    echo "Zig compiler not found."
    read -p "Would you like to download Zig temporarily to build ZigUp? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        TEMP_ZIG_DIR=$(setup_temp_zig)
    else
        echo "Please install Zig first: https://ziglang.org/download/"
        exit 1
    fi
fi

# Check Zig version
ZIG_VERSION=$(zig version)
echo "Using Zig version: $ZIG_VERSION"

# Create ~/.local/bin if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Build ZigUp
echo "Building ZigUp..."
zig build -Doptimize=ReleaseFast

# Install to ~/.local/bin
echo "Installing to ~/.local/bin..."
cp zig-out/bin/zigup "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/zigup"

# Clean up temporary Zig if it was downloaded
if [ -n "$TEMP_ZIG_DIR" ]; then
    echo "Cleaning up temporary Zig installation..."
    rm -rf "$TEMP_ZIG_DIR"
fi

echo ""
echo "✓ ZigUp installed successfully!"
echo ""
echo "Make sure ~/.local/bin is in your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "Add this line to your shell profile (.bashrc, .zshrc, etc.)"
echo ""
echo "Quick start:"
echo "  zigup update          # Fetch available versions"
echo "  zigup default nightly # Install and set nightly as default"
echo "  zigup list            # Show installed versions"