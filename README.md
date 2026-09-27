# Fish Wallpaper

An interactive aquarium desktop for macOS, Windows, and Linux X11. The aquascape video has a blended, continuous loop. Neon tetras, honey gouramis, silver angelfish, and guppies swim over it and scatter from your cursor. The app sits behind desktop icons and closes when you press **Control-C** in the terminal that launched it.

## One-command setup

**macOS and Linux X11** — paste into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/wakeupbrk/fish-wallpaper/main/install.sh | sh
```

**Windows x64** — paste into PowerShell:

```powershell
irm https://raw.githubusercontent.com/wakeupbrk/fish-wallpaper/main/install.ps1 | iex
```

Open a new terminal after installation and run `aquarium-fish`. The installer also creates a `fish` shortcut when that name is unused, so it will not replace the fish shell. Press **Control-C** to stop and reveal your normal wallpaper.

The macOS app supports Apple Silicon and Intel. The Windows app supports x64. The Linux app supports x64 on X11 desktops; Wayland compositors currently do not provide a portable way for this app to sit behind desktop icons. The Linux release was built on Ubuntu 22.04 and needs a glibc-based distribution with X11.

## How it works

- macOS: a native Swift/AppKit desktop-level window plays the video with AVFoundation and draws the interactive fish above it.
- Windows: a Qt window is attached to the desktop's WorkerW layer, under desktop icons.
- Linux X11: a Qt window requests the EWMH desktop window type and is lowered behind desktop icons.
- The video is silent. Its ending dissolves into the opening motion over two seconds, so the 13-second file repeats without a hard cut.

All files stay on your computer. The app does not use a network connection after installation, collect data, request accessibility access, or change your wallpaper setting.

## Build from source

macOS (requires Xcode command line tools):

```sh
swiftc -parse-as-library -O -framework AppKit -framework AVFoundation Aquarium.swift -o aquarium
./aquarium --check
./aquarium
```

Windows/Linux (requires Python 3.12):

```sh
python -m pip install -r requirements.txt
python aquarium_desktop.py --check
python aquarium_desktop.py --preview
python aquarium_desktop.py
```

`--preview` opens a normal window and closes with Escape. The GitHub Actions workflow builds tested release archives for all three operating systems.

## Uninstall

- macOS/Linux: remove `~/.local/share/fish-wallpaper` and the launchers `~/.local/bin/aquarium-fish` and `~/.local/bin/fish` (only if the latter points to this project).
- Windows: remove `%LOCALAPPDATA%\FishWallpaper` and its entry from your user PATH.

The image generation prompts are in [PROMPTS.md](PROMPTS.md). The included video is a processed, audio-free loop of the supplied aquarium animation.
