#!/usr/bin/env bash
#
# Banc d'essai du moteur de stylage, sans XCTest ni Xcode : on instancie un
# NSTextStorage, on lui applique le highlighter, et on vérifie les attributs
# effectivement posés sur le texte.
#
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -O -o "$OUT/check" \
	Tests/main.swift \
	Sources/MDViewer/MarkdownHighlighter.swift \
	Sources/MDViewer/Theme.swift \
	Sources/MDViewer/MarkerVisibility.swift

"$OUT/check"
