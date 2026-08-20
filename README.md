# Nymph

Nymph is a fast, lightweight terminal fetch tool written in Nim. It supports displaying PNG logos directly in your terminal using the Kitty graphics protocol, falling back to ASCII art if your terminal doesn't support images.

![Nymph Screenshot](Nymph.png)

## Features

- **Fast:** Minimal dependencies, pure sysfs/procfs inspection, and instant startup.
- **Image support:** Renders high-res PNGs via Kitty Graphics and iTerm2 (OSC 1337) protocols in Kitty, WezTerm, Ghostty, Foot, VS Code terminal, and iTerm2.
- **Colorized Fallback:** Styled ASCII artwork with theme palette colors when running in basic terminals.
- **Customizable:** Built-in themes (Catppuccin, Nord, Gruvbox, Plain), Nerd Font icon packs, and tweakable layouts.
- **JSON mode:** Pipe system data into status bars (Waybar, Polybar) easily.

## Installation

You'll need Nim `>= 2.0.0` installed.

```bash
# Build the release binary to ./bin/nymph
nimble release

# Or run directly from source
nim c -r src/nymph.nim
```

## Quick Start

Run with defaults:
```bash
./bin/nymph
```

Override theme and layout without editing the config:
```bash
./bin/nymph --theme nord --icon-pack ascii --layout compact
```

Show only specific modules:
```bash
./bin/nymph --modules title,os,cpu,gpu,memory,disk
```

See all options and available themes from the terminal:
```bash
./bin/nymph --help
./bin/nymph --list-themes
./bin/nymph --list-icon-packs
```

## Configuration

On the first run, Nymph generates an INI-style config file at `~/.config/nymph/config.conf` (respecting `$XDG_CONFIG_HOME`).

```conf
# Drop your own logo path here
customlogo = ""

# Layout & Themes
theme = catppuccin
iconpack = nerd
layout = full
json = false
nocolor = false

# Modules to display (must be wrapped in quotes)
modules = "title,os,host,kernel,cpu,gpu,resolution,desktop,audio,terminal,shell,packages,uptime,localip,memory,disk,battery,footer"

# Customize the colored blocks at the bottom of the fetch (leave empty for random)
footericons = ""
footerpadding = 7

# Advanced tweaks
maxwidth = 200
statsoffset = 22
```

### Custom Logos
By default, Nymph attempts to detect your OS and automatically loads the matching logo from `~/.config/nymph/logos/` (e.g., `arch.png` or `debian.png`). If no image is found, it falls back to built-in graphics or ASCII. 

To add your own logo for a specific distro, just drop a `.png` (for high-res graphics) or `.txt` (for ASCII art) into `~/.config/nymph/logos/` and name it after your distro's ID!

Alternatively, you can forcefully override the logo detection by setting `customlogo = "/absolute/path/to/logo.png"` in your config file.

### Footer Icons (`footer` module)
You can customize the colored footer. Pass a single icon (like `footericons = "▃▃▃"`) to repeat it, or a comma-separated list of symbols to cycle through them. Use `footerpadding` to align the block left or right relative to your stats.

## Available Modules
- **Identity & System**: `title` (`user@host` + header rule), `os`, `kernel`, `desktop` (DE/WM), `shell`, `terminal`, `uptime`
- **Hardware**: `host` (Machine Model), `cpu`, `gpu` (PCI graphics devices), `resolution` (DRM displays), `disk`, `battery`
- **Network & Media**: `localip` (Active IPv4), `audio` (PipeWire / PulseAudio / ALSA)
- `packages`: Counts packages across pacman, dpkg, flatpak, apk, snap, portage, eopkg, xbps, homebrew, rpm.
- `memory`: RAM usage with a compact visual bar.
- `footer`: Colored footer blocks.

## Scripting (JSON)
Need raw data for a script? Run `./bin/nymph --json` to get a clean JSON object containing all system metrics.

## Diagnostics
If your logo isn't loading or something looks wrong, run `./bin/nymph --doctor` to see exactly where Nymph is looking for files and whether it detected graphics support.

## Contributing
This is a hobby project! There might be edge cases on untested distros. Feel free to open a PR or issue. 

License: MIT. See [LICENSE](LICENSE).
