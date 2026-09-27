#!/bin/sh
set -eu

repo='wakeupbrk/fish-wallpaper'
base="https://github.com/$repo/releases/latest/download"
platform=$(uname -s)
arch=$(uname -m)
case "$platform:$arch" in
  Darwin:arm64|Darwin:x86_64) archive='fish-wallpaper-macos-universal.tar.gz'; binary='aquarium' ;;
  Linux:x86_64) archive='fish-wallpaper-linux-x64.tar.gz'; binary='aquarium-fish/aquarium-fish' ;;
  *) printf 'Unsupported system: %s %s\n' "$platform" "$arch" >&2; exit 1 ;;
esac

if [ "$platform" = Linux ] && [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
  printf 'This release supports Linux X11 desktops. Select an X11 session before running it.\n' >&2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
curl -fsSL "$base/$archive" -o "$tmp/$archive"
curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS"
expected=$(awk -v name="$archive" '$2 == name {print $1}' "$tmp/SHA256SUMS")
[ -n "$expected" ] || { printf 'Checksum entry missing.\n' >&2; exit 1; }
if [ "$platform" = Darwin ]; then
  actual=$(shasum -a 256 "$tmp/$archive" | awk '{print $1}')
else
  actual=$(sha256sum "$tmp/$archive" | awk '{print $1}')
fi
[ "$actual" = "$expected" ] || { printf 'Download checksum mismatch.\n' >&2; exit 1; }

install_dir="$HOME/.local/share/fish-wallpaper"
bin_dir="$HOME/.local/bin"
mkdir -p "$install_dir" "$bin_dir"
tar -xzf "$tmp/$archive" -C "$install_dir"
[ -x "$install_dir/$binary" ] || chmod 755 "$install_dir/$binary"
printf '#!/bin/sh\nexec "$HOME/.local/share/fish-wallpaper/%s" "$@"\n' "$binary" > "$bin_dir/aquarium-fish"
chmod 755 "$bin_dir/aquarium-fish"
if ! command -v fish >/dev/null 2>&1 && [ ! -e "$bin_dir/fish" ]; then
  ln -s aquarium-fish "$bin_dir/fish"
fi

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    case "${SHELL##*/}" in
      zsh) rc="$HOME/.zshrc" ;;
      bash) rc="$HOME/.bashrc" ;;
      *) rc='' ;;
    esac
    if [ -n "$rc" ] && ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$rc" 2>/dev/null; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi
    ;;
esac
printf 'Installed aquarium-fish. Open a new terminal, run aquarium-fish, and press Control-C to stop.\n'
if [ -L "$bin_dir/fish" ]; then printf 'The fish shortcut is available too.\n'; fi
