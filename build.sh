#!/bin/bash
# 사용법:
#   ./build.sh            build/mdr.app 생성
#   ./build.sh install    빌드 후 /Applications 에 설치하고 mdr 명령어를 연결
#   ./build.sh dmg        배포용 build/mdr.dmg 생성 (인텔·애플 실리콘 겸용)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/mdr.app"
CONTENTS="$APP/Contents"

# 빌드할 아키텍처. 기본은 이 맥의 것만, 배포용 dmg 는 둘 다.
if [ "${1:-}" = "dmg" ]; then
  ARCHS="${ARCHS:-arm64 x86_64}"
else
  ARCHS="${ARCHS:-$(uname -m)}"
fi

# compile <출력 파일> <swiftc 인자...> : 아키텍처별로 컴파일해 하나로 합친다
compile() {
  local out="$1"
  shift
  local slices=()
  for arch in $ARCHS; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" "$@" -o "$out.$arch"
    slices+=("$out.$arch")
  done
  lipo -create "${slices[@]}" -output "$out"
  rm -f "${slices[@]}"
}

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "› 컴파일 ($ARCHS)"
compile "$CONTENTS/MacOS/mdr" Sources/*.swift

echo "› 리소스"
cp Info.plist "$CONTENTS/Info.plist"
cp -R Resources/web "$CONTENTS/Resources/web"
cp bin/mdr "$CONTENTS/Resources/mdr"
chmod +x "$CONTENTS/Resources/mdr"

if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "› 아이콘"
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make-icon.swift build/icon-1024.png
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

echo "› 훑어보기 확장"
APPEX="$CONTENTS/PlugIns/MdrQuickLook.appex/Contents"
mkdir -p "$APPEX/MacOS" "$APPEX/Resources"
compile "$APPEX/MacOS/MdrQuickLook" -parse-as-library -application-extension \
  -module-name MdrQuickLook \
  -Xlinker -e -Xlinker _NSExtensionMain \
  QuickLook/PreviewProvider.swift
cp QuickLook/Info.plist "$APPEX/Info.plist"
cp QuickLook/render.js Resources/web/style.css \
  Resources/web/vendor/marked.js Resources/web/vendor/highlight.js "$APPEX/Resources/"

echo "› 서명 (ad-hoc)"
codesign --force --sign - --entitlements QuickLook/entitlements.plist \
  "$CONTENTS/PlugIns/MdrQuickLook.appex" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "✓ $APP"

if [ "${1:-}" = "install" ]; then
  DEST="/Applications/mdr.app"
  BIN_DIR="$HOME/.local/bin"
  pkill -x mdr 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  mkdir -p "$BIN_DIR"
  ln -sf "$DEST/Contents/Resources/mdr" "$BIN_DIR/mdr"
  pluginkit -a "$DEST/Contents/PlugIns/MdrQuickLook.appex" 2>/dev/null || true
  pluginkit -e use -i app.mdr.reader.quicklook 2>/dev/null || true
  qlmanage -r >/dev/null 2>&1 || true
  echo "✓ 설치: $DEST"
  echo "✓ 명령어: $BIN_DIR/mdr"
fi

if [ "${1:-}" = "dmg" ]; then
  DMG="build/mdr.dmg"
  STAGE="build/dmg"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/mdr.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname mdr -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "✓ $DMG"
fi
