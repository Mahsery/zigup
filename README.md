# ZigUp - Zig Version Manager

A fast, simple version manager for the Zig programming language, written in Zig itself.

## Features

- 🚀 **Fast downloads** - Direct from ziglang.org with HTTP/2 support
- 🔧 **No sudo required** - Installs to user directories (`~/.local/bin`, `~/bin`)
- 🗂️ **Multiple versions** - Install and switch between any Zig version
- 💾 **Persistent cache** - Offline version listing after initial fetch
- 🎯 **Auto-install** - `zigup default nightly` installs if not present
- 🛡️ **Error recovery** - Clear error messages, no cryptic stack traces

## Quick Start

```bash
# Build and install zigup
zig build -Doptimize=ReleaseFast install-zigup

# Make sure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"

# Fetch available versions
zigup update

# Install and set nightly as default
zigup default nightly

# Install a specific version without setting as default
zigup install 0.14.1

# List installed versions
zigup list

# Show available versions (cached)
zigup update list
```

## Installation

### Prerequisites
- Zig 0.14.1 or later
- Internet connection for downloads
- `tar` command (for extraction)

### Build from Source
```bash
git clone <this-repo>
cd zigup
zig build -Doptimize=ReleaseFast install-zigup
```

Make sure `~/.local/bin` is in your PATH:
```bash
# Add to your shell profile (.bashrc, .zshrc, etc.)
export PATH="$HOME/.local/bin:$PATH"
```

## Commands

| Command | Description |
|---------|-------------|
| `zigup update` | Fetch and cache version information from ziglang.org |
| `zigup list` | Show installed Zig versions |
| `zigup install <version>` | Download and install a Zig version |
| `zigup default <version>` | Set default Zig version (auto-installs if needed) |
| `zigup update list` | Show cached available versions |
| `zigup --help` | Show help message |
| `zigup --version` | Show zigup version |

## Examples

```bash
# Install latest nightly build
zigup default nightly

# Install specific release
zigup install 0.14.1
zigup default 0.14.1

# Check what's available
zigup update list

# See what you have installed
zigup list
```

## Version Formats

ZigUp supports these version formats:

- **Release versions**: `0.14.1`, `0.13.0`, etc.
- **Nightly builds**: `nightly` or `master`
- **Development versions**: Full version strings like `0.15.0-dev.1145+3ae0ba096`

## Configuration

ZigUp uses standard directories:
- **Cache**: `~/.cache/zigup/` (XDG cache directory)
- **Installations**: `~/bin/<version>/` (user bin directory)  
- **Active symlink**: `~/.local/bin/zig` (user local bin)

No configuration file is needed for basic usage.

## Error Handling

ZigUp provides clear error messages instead of stack traces:

```bash
# Permission error
Error: Permission denied creating directory: /home/user/bin/nightly
Please fix directory permissions or run: sudo chown -R $USER:$USER ~/bin

# Missing cache
Error: Version cache not found. Run 'zigup update' first.

# Invalid version
Error: Version 'invalid' not found
```

## Troubleshooting

### PATH Issues
If `zig` command is not found after installation:
```bash
# Check if ~/.local/bin is in PATH
echo $PATH | grep -q "$HOME/.local/bin" && echo "✓ PATH OK" || echo "✗ Add ~/.local/bin to PATH"

# Add to shell profile
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Permission Issues
If you get permission errors:
```bash
# Fix ~/bin ownership
sudo chown -R $USER:$USER ~/bin

# Or create it with correct permissions
mkdir -p ~/bin
```

### Network Issues
If downloads fail:
```bash
# Test connectivity
curl -I https://ziglang.org/download/index.json

# Clear cache and retry
rm -rf ~/.cache/zigup
zigup update
```

## Development

### Dependencies
- **zig-clap**: Command line argument parsing
- **zimdjson**: High-performance JSON parsing  
- **zap**: HTTP networking (currently minimal usage)

### Building
```bash
# Debug build
zig build

# Release build  
zig build -Doptimize=ReleaseFast

# Install to system
zig build -Doptimize=ReleaseFast install-zigup

# Run tests
zig build test
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Mehmet Muhammet Koseoglu <mehmet.kn94@gmail.com>

## Acknowledgments

- Zig Software Foundation for the amazing language
- ziglang.org for providing version APIs
- Community for feedback and testing

---

**Made with ❤️ and Zig**