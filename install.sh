#!/bin/bash
# mdr 설치 스크립트: 최신 릴리스의 mdr.dmg 를 받아 /Applications 에 설치하고
# 터미널 명령어 mdr 을 연결한다.
#
#   curl -fsSL https://raw.githubusercontent.com/hisumin46/mdr/main/install.sh | bash
#
# 명령어를 둘 폴더를 바꾸려면: MDR_BIN_DIR=/usr/local/bin 을 앞에 붙인다.
set -euo pipefail

DMG_URL="https://github.com/hisumin46/mdr/releases/latest/download/mdr.dmg"
DEST="/Applications/mdr.app"
BIN_DIR="${MDR_BIN_DIR:-$HOME/.local/bin}"

fail() {
  echo "mdr 설치 실패: $1" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "macOS 에서만 설치할 수 있습니다."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "macOS 14 이상이 필요합니다."

# 열려 있는 mdr 은 정상 종료시킨다. 저장하지 않은 문서가 있으면 앱이 먼저 묻는다.
if pgrep -x mdr >/dev/null; then
  echo "› 실행 중인 mdr 종료"
  osascript -e 'tell application id "app.mdr.reader" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x mdr >/dev/null || break
    sleep 1
  done
  pgrep -x mdr >/dev/null && fail "mdr 을 종료한 뒤 다시 실행해 주세요."
fi

WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "› 내려받기"
curl -fsSL "$DMG_URL" -o "$WORK/mdr.dmg" || fail "내려받지 못했습니다: $DMG_URL"

echo "› 설치"
mkdir "$MOUNT"
hdiutil attach "$WORK/mdr.dmg" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
[ -d "$MOUNT/mdr.app" ] || fail "dmg 안에 mdr.app 이 없습니다."
rm -rf "$DEST"
ditto "$MOUNT/mdr.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# 파일 연결과 훑어보기(스페이스바) 확장 등록
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/MdrQuickLook.appex" 2>/dev/null || true
pluginkit -e use -i app.mdr.reader.quicklook 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true

mkdir -p "$BIN_DIR"
ln -sf "$DEST/Contents/Resources/mdr" "$BIN_DIR/mdr"

echo "✓ 설치: $DEST"
echo "✓ 명령어: $BIN_DIR/mdr"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR 이(가) PATH 에 없습니다. 아래 줄을 ~/.zshrc 에 추가하세요:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
