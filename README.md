# ZigUp - Zig Version Manager

A version manager for the Zig programming language, written in Zig.

## Quick Start

```bash
# Build and install
zig build -Doptimize=ReleaseFast install-zigup

# Fetch versions and install
zigup update
zigup default nightly
```

## Installation

### Quick Install (Recommended)

Download and run the installer for your platform:

**Windows:**
```powershell
# Download and run installer
curl -L -o zigup-installer.exe "https://github.com/Mahsery/zigup/releases/download/v0.2.0-dev.44%2Bg02f8679/zigup-installer.exe"
.\zigup-installer.exe
```

**Linux:**
```bash
# Download and run installer
curl -L -o zigup-installer "https://github.com/Mahsery/zigup/releases/download/v0.2.0-dev.44%2Bg02f8679/zigup-installer-linux"
chmod +x zigup-installer
./zigup-installer
```

**macOS:**
```bash
# Intel Macs
curl -L -o zigup-installer "https://github.com/Mahsery/zigup/releases/download/v0.2.0-dev.44%2Bg02f8679/zigup-installer-macos"
chmod +x zigup-installer
./zigup-installer

# Apple Silicon Macs
curl -L -o zigup-installer "https://github.com/Mahsery/zigup/releases/download/v0.2.0-dev.44%2Bg02f8679/zigup-installer-macos-arm64"
chmod +x zigup-installer
./zigup-installer
```

The installer automatically:
- Downloads the latest zigup binary
- Installs it to `~/.local/bin` (Unix) or `%USERPROFILE%\.local\bin` (Windows)
- Sets up your PATH (Windows automatic, Unix provides instructions)

### Manual Install

Download the zigup binary directly from [releases](https://github.com/Mahsery/zigup/releases) and add it to your PATH manually.

### Build from Source

If you have Zig installed:
```bash
git clone https://github.com/Mahsery/zigup.git
cd zigup
zig build -Doptimize=ReleaseFast install-zigup
```

## Commands

| Command | Description |
|---------|-------------|
| `zigup update` | Fetch version information |
| `zigup list` | Show installed versions |
| `zigup install <version>` | Install a version |
| `zigup default <version>` | Set default version |
| `zigup remove <version>` | Remove a version |
| `zigup update list` | Show available versions |

## Examples

```bash
# Install latest nightly
zigup default nightly

# Install specific version
zigup install 0.14.1
zigup default 0.14.1

# Remove old version
zigup remove 0.13.0
```

## Version Formats

- Release versions: `0.14.1`, `0.13.0`
- Nightly builds: `nightly` or `master`
- Development versions: `0.15.0-dev.1145+3ae0ba096`

## Directory Structure

- Installations: `~/bin/<version>/`
- Active symlink: `~/.local/bin/zig`
- Cache: `~/.cache/zigup/`

## Security

All downloads are verified using minisign cryptographic signatures from ziglang.org.

## Troubleshooting

### PATH Issues
```bash
# Check PATH
echo $PATH | grep -q "$HOME/.local/bin" && echo "OK" || echo "Add ~/.local/bin to PATH"

# Fix PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

### Permission Issues
```bash
# Fix ownership
sudo chown -R $USER:$USER ~/bin
```

### Network Issues
```bash
# Clear cache
rm -rf ~/.cache/zigup
zigup update
```

## License

MIT License

Copyright (c) 2025 Mehmet Muhammet Koseoglu