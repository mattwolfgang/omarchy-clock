#!/usr/bin/env bash
# Copy the plugin into the Omarchy shell's plugin folder and enable it, which
# replaces the built-in clock in the bar. Re-run after editing to update the
# installed copy. Undo with: omarchy plugin enable omarchy.clock
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="io.github.mattwolfgang.clock"
dest="$HOME/.config/omarchy/plugins/$id"

omarchy plugin validate "$src"

mkdir -p "$dest/i18n"
cp "$src"/manifest.json "$src"/LICENSE "$src"/*.qml "$src"/*.js "$dest/"
cp "$src"/i18n/*.json "$dest/i18n/"
mkdir -p "$dest/sounds"
cp "$src"/sounds/* "$dest/sounds/"

# A first install is a new folder the shell may not have scanned yet.
omarchy-shell shell rescanPlugins >/dev/null

enabled="$(omarchy plugin list --json | jq -r --arg id "$id" 'any(.[]; .id == $id and .enabled)')"
if [[ $enabled != true ]]; then
  omarchy plugin enable "$id"
fi

echo "Installed $id to $dest"
echo "If this was an update, run omarchy-restart-shell to load the new QML."
