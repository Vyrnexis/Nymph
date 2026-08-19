# Nymph 🧚‍♀️

Hey everyone! Nymph is a little terminal fetch tool I've been working on. 

I wrote it in Nim because I wanted something stupidly fast that starts up instantly, but I also really wanted it to support displaying actual PNG logos right in the terminal (via the Kitty graphics protocol). It falls back to some cool ASCII art if your terminal doesn't support Kitty graphics, so it won't break on you.

![Nymph Screenshot](Nymph.png)

## Why I made this
Honestly, I just wanted a fetch tool that was easy to tweak without diving into a massive codebase. 
- **It's fast.** Like, really fast. Minimal dependencies.
- **Image support:** Renders high-res PNGs if you use Kitty, WezTerm, Ghostty, etc.
- **Themes & Icons:** Comes with a few built-in palettes (Catppuccin, Nord, Gruvbox) and Nerd Font support.
- **JSON mode:** You can pipe it into your status bars (Waybar, Polybar) easily.

## How to build it

You'll need Nim installed (at least v2.0.0).

Clone the repo and run:
```bash
nimble release
```
That'll compile everything and drop a binary at `./bin/nymph`.

If you just want to run it straight from the source to test things out:
```bash
nim c -r src/nymph.nim
```

## Quick Start

Just run `./bin/nymph` and you're good to go. 

If you want to play around with the look without editing config files, try passing some flags:
```bash
./bin/nymph --theme nord --icon-pack ascii --layout compact
```

Want to only see specific things?
```bash
./bin/nymph --modules os,kernel,packages,memory
```

## The Config File

On the first run, Nymph will generate a config file at `~/.config/nymph/config.conf`. I recently moved this to use standard INI-style parsing, which means you can leave `# comments` in the file!

Here's what it looks like and what you can tweak:

```conf
# Drop your own logo path here if you want!
customlogo = ""

# Layout stuff
theme = catppuccin
iconpack = nerd
layout = full

# Important: make sure your modules list is wrapped in quotes!
modules = "os,kernel,desktop,packages,shell,uptime,memory,colours"

# You can change the colored blocks at the bottom of the fetch
footericons = "●,■,◆"
footerpadding = 3

# Advanced tweaks
maxwidth = 200
statsoffset = 22
json = false
nocolor = false
```

### A note on the footer icons
The `colours` module at the bottom of the fetch is fully customizable. You can give it a single icon (like `footericons = "▃▃▃"`) and it'll repeat it 7 times with different colors. Or you can pass it a comma-separated list of symbols and it will cycle through them. Use `footerpadding` to shift them left or right until they line up perfectly with your text.

## Modules you can use
Right now it tracks:
- `os`
- `kernel`
- `desktop` (DE/WM)
- `packages` (Counts pacman, dpkg, flatpak, apk, snap, portage, etc)
- `shell`
- `uptime`
- `memory` (Shows a neat little RAM bar)
- `colours` (The colored footer blocks)

## Scripting (JSON Mode)
If you're a ricing nerd and want to use Nymph's data in your own scripts or status bars, just run:
```bash
./bin/nymph --json
```
It spits out a clean JSON object with everything it found. 

## Troubleshooting
If something looks weird or your logo isn't loading, run `./bin/nymph --doctor`. It'll print out exactly where it's looking for config files and logos, and whether it thinks your terminal supports graphics.

## Contributing
Since I'm just doing this as a hobby, there are probably bugs or edge cases on distros I haven't tested. Feel free to open a PR or issue!

License is MIT. See [LICENSE](LICENSE).
