#!/bin/bash
set -e

# Install zigup and automatically add to PATH
echo "Installing zigup to ~/.local/bin..."

# Create directory and copy binary
mkdir -p ~/.local/bin
cp zig-out/bin/zigup ~/.local/bin/zigup
chmod +x ~/.local/bin/zigup

echo "zigup installed to ~/.local/bin/zigup"

# Check if already in PATH
if echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "~/.local/bin is already in your PATH"
    exit 0
fi

# Detect shell and add to appropriate config file
detect_and_add_to_path() {
    local shell_name=$(basename "$SHELL")
    local config_file=""
    local path_line=""
    
    case "$shell_name" in
        bash)
            config_file="$HOME/.bashrc"
            path_line='export PATH="$HOME/.local/bin:$PATH"'
            ;;
        zsh)
            config_file="$HOME/.zshrc"
            path_line='export PATH="$HOME/.local/bin:$PATH"'
            ;;
        fish)
            config_file="$HOME/.config/fish/config.fish"
            path_line='set -gx PATH $HOME/.local/bin $PATH'
            mkdir -p "$(dirname "$config_file")"
            ;;
        *)
            echo "Unknown shell: $shell_name"
            echo "Please manually add ~/.local/bin to your PATH"
            return 1
            ;;
    esac
    
    # Check if PATH line already exists in config file
    if [ -f "$config_file" ] && grep -q "\.local/bin" "$config_file"; then
        echo "~/.local/bin already configured in $config_file"
        return 0
    fi
    
    # Add to config file
    echo "Adding ~/.local/bin to PATH in $config_file"
    echo "$path_line" >> "$config_file"
    echo "PATH updated! Please restart your terminal or run: source $config_file"
}

detect_and_add_to_path