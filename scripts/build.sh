#!/usr/bin/env bash
# Builds build/BEO.app (Apple silicon or Intel via ARCH=arm64|x86_64, default: host arch).
# Shown as BEO.
# Without RELEASE=1 it is a dev build: "BEO Dev", bundle id com.wquguru.cicada.dev (its own
# settings, permissions and meeting records), stamped with the branch and commit, which show in the
# menu bar and panel; its icon is the plain beo bird (no DEV band — the DEV marking is the app
# name plus the stamp). RELEASE=1 builds the real com.wquguru.cicada.
# The bundle id stays com.wquguru.cicada on purpose: BEO is a fork of Cicada, and keeping the id
# carries the system-audio and microphone permissions over from the Cicada install.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${ARCH:-$(uname -m)}"
swift build -c release --arch "$ARCH" --product BEO
BIN=$(swift build -c release --arch "$ARCH" --show-bin-path)

APP=build/BEO.app
ICONSET=build/AppIcon.iconset
rm -rf "$APP" "$ICONSET" build/LiveSubs.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/BEO" "$APP/Contents/MacOS/BEO"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/sample/sample.m4a "$APP/Contents/Resources/"
# The experimental voiceprint model; the app compiles it on first use (no coremlcompiler in the CLT).
cp -R Resources/models/SpeakerEmbedding.mlpackage "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Traditional Chinese systems get the Chinese UI rather than English (there is no zh-Hant translation).
cp -R Resources/zh-Hans.lproj "$APP/Contents/Resources/zh-Hant.lproj"

PLIST="$APP/Contents/Info.plist"
# One version for every platform, in VERSION at the repo root (the committed Info.plist value is unused).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(tr -d '[:space:]' < VERSION)" "$PLIST"
if [[ "${RELEASE:-}" != 1 ]]; then
  STAMP="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo local) @ $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]] && STAMP+="+"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.wquguru.cicada.dev" \
    -c "Set :CFBundleName BEO Dev" -c "Set :CFBundleDisplayName BEO Dev" \
    -c "Add :LiveSubsDev string $STAMP" "$PLIST"
  # Only the two name lines change: the usage descriptions in the same files stay.
  sed -i '' -E 's/^(CFBundle(Display)?Name = ")([^"]*)";/\1\3 Dev";/' \
    "$APP"/Contents/Resources/*.lproj/InfoPlist.strings
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
fi

# The app icon is Patria's beo artwork (Resources/AppIcon-BEO.png, 1971x1721, transparent
# corners): fitted onto a transparent 1024 square, aspect kept, never cropped, then every
# iconset size is downscaled from it. The old BEOIcon renderer is not used anymore.
# sips pads with transparency by default; --padColor must not be given (it rejects an
# 8-digit hex alpha color).
ICON_SRC=Resources/AppIcon-BEO.png
ICON_FIT=build/AppIcon-1024-fit.png
ICON_MASTER=build/AppIcon-1024.png
mkdir -p "$ICONSET"
sips -Z 1024 "$ICON_SRC" --out "$ICON_FIT" >/dev/null
sips --padToHeightWidth 1024 1024 "$ICON_FIT" --out "$ICON_MASTER" >/dev/null
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  size="${spec%%:*}"; name="${spec#*:}"
  sips -z "$size" "$size" "$ICON_MASTER" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# The in-app mark and menu-bar glyph use the same fitted square image.
cp "$ICON_MASTER" "$APP/Contents/Resources/AppIcon-1024.png"

# A fixed designated requirement (the bundle id alone), so rebuilding keeps the system-audio and
# microphone permissions instead of asking again after every build. A Developer ID signature
# (SIGN_IDENTITY, set for releases) keeps the same requirement: permissions granted to the earlier
# ad-hoc builds carry over. It adds the hardened runtime and a timestamp, which notarization needs.
ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$PLIST")
SIGN_FLAGS=(--sign -)
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  SIGN_FLAGS=(--sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements Resources/BEO.entitlements)
fi
codesign --force "${SIGN_FLAGS[@]}" --requirements "=designated => identifier \"$ID\"" "$APP" >/dev/null
echo "Built $APP ($ID, signed by ${SIGN_IDENTITY:-ad hoc})"
