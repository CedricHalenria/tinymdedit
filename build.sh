#!/usr/bin/env bash
#
# Fabrique TinyMDEdit.app sans Xcode : SwiftPM compile le binaire, on assemble
# le bundle à la main, puis on le signe en ad-hoc pour que macOS l'accepte.
#
# Usage :
#   ./build.sh            # build release
#   ./build.sh --debug    # build debug
#   ./build.sh --run      # build puis lance l'app
#   ./build.sh --register # inscrit cette copie comme app par défaut des .md
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TinyMDEdit"
CONFIG="release"
RUN=0
REGISTER=0
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

for arg in "$@"; do
	case "$arg" in
		--debug) CONFIG="debug" ;;
		--release) CONFIG="release" ;;
		--run) RUN=1 ;;
		--register) REGISTER=1 ;;
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

# La version publiée vient du tag Git lors d'une publication ; en local, on garde
# celle inscrite dans Resources/Info.plist.
if [ -n "${TINYMDEDIT_VERSION:-}" ]; then
	/usr/libexec/PlistBuddy -c \
		"Set :CFBundleShortVersionString $TINYMDEDIT_VERSION" "$APP/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c \
		"Set :CFBundleVersion ${TINYMDEDIT_BUILD:-1}" "$APP/Contents/Info.plist"
	echo "▸ Version $TINYMDEDIT_VERSION"
fi

# Signature. « - » est une signature ad-hoc : elle suffit sur la machine qui
# compile, mais macOS met en quarantaine une app ainsi signée téléchargée depuis
# Internet. Le jour où un certificat Developer ID est disponible, il suffit de
# renseigner TINYMDEDIT_SIGN_IDENTITY pour signer pour de bon — la notarisation
# se greffe alors après cette étape.
SIGN_IDENTITY="${TINYMDEDIT_SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
	echo "▸ Signature ad-hoc…"
	codesign --force --sign - "$APP"
else
	echo "▸ Signature avec « $SIGN_IDENTITY »…"
	codesign --force --options runtime --timestamp \
		--sign "$SIGN_IDENTITY" "$APP"
fi

# On n'inscrit délibérément PAS cette copie auprès de Launch Services. Sans quoi
# le binaire de développement disputerait l'ouverture des .md à l'exemplaire
# installé dans /Applications — deux bundles de même identifiant, et macOS choisit
# seul lequel répond au double-clic.
# Utiliser --register quand la copie locale doit devenir celle qui répond.
if [ "$REGISTER" -eq 1 ]; then
	echo "▸ Inscription auprès de Launch Services…"
	"$LSREGISTER" -f "$(pwd)/$APP" 2>/dev/null || true
fi

echo "✓ $APP"

if [ "$RUN" -eq 1 ]; then
	open "$APP"
fi
