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
	Sources/TinyMDEdit/MarkdownHighlighter.swift \
	Sources/TinyMDEdit/MarkdownTable.swift \
	Sources/TinyMDEdit/Theme.swift \
	Sources/TinyMDEdit/MarkerVisibility.swift \
	Sources/TinyMDEdit/CodeHighlighter.swift \
	Sources/TinyMDEdit/SemanticVersion.swift

"$OUT/check"
