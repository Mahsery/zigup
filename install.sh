#!/bin/bash
set -e

# ZigUp Installation Script
# Builds and installs ZigUp Zig version manager

echo "Installing ZigUp..."

# Check if zig is installed
if ! command -v zig &> /dev/null; then
    echo "Error: Zig compiler not found. Please install Zig first."
    echo "Visit: https://ziglang.org/download/"
    exit 1
fi

# Check Zig version
ZIG_VERSION=$(zig version)
echo "Found Zig version: $ZIG_VERSION"

# Create ~/.local/bin if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Build ZigUp
echo "Building ZigUp..."
zig build -Doptimize=ReleaseFast

# Install to ~/.local/bin
echo "Installing to ~/.local/bin..."
cp zig-out/bin/zigup "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/zigup"

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