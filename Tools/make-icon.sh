#!/usr/bin/env bash
#
# Régénère Resources/AppIcon.icns à partir du générateur Swift.
# À relancer après toute modification de Tools/make-icon/main.swift.
#
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swiftc -O -o "$WORK/make-icon" Tools/make-icon/main.swift
"$WORK/make-icon" "$ICONSET"

iconutil --convert icns --output Resources/AppIcon.icns "$ICONSET"

# Aperçu lisible à l'œil, non versionné.
cp "$ICONSET/icon_512x512.png" "$WORK/apercu.png"
echo "✓ Resources/AppIcon.icns"
