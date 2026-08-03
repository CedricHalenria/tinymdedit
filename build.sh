#!/usr/bin/env bash
#
# Fabrique TinyMDEdit.app sans Xcode : SwiftPM compile le binaire, on assemble
# le bundle à la main, puis on le signe en ad-hoc pour que macOS l'accepte.
#
# Usage :
#   ./build.sh            # build release
#   ./build.sh --debug    # build debug
#   ./build.sh --run      # build puis lance l'app
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TinyMDEdit"
CONFIG="release"
RUN=0

for arg in "$@"; do
	case "$arg" in
		--debug) CONFIG="debug" ;;
		--release) CONFIG="release" ;;
		--run) RUN=1 ;;
		*) echo "Option inconnue : $arg" >&2; exit 1 ;;
	esac
done

echo "▸ Compilation ($CONFIG)…"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/${APP_NAME}.app"
echo "▸ Assemblage du bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signature ad-hoc…"
codesign --force --sign - "$APP"

# Sans ça, Launch Services garde en cache une version antérieure du bundle
# et les fichiers .md ne s'associent pas à la bonne app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-f "$(pwd)/$APP" 2>/dev/null || true

echo "✓ $APP"

if [ "$RUN" -eq 1 ]; then
	open "$APP"
fi
