# mdr

macOS용 마크다운 리더입니다. `.md` 파일을 렌더링된 미리보기로 열고, 필요할 때만 수정해서 저장합니다.

- 파일마다 별도 창으로 열립니다.
- 다른 프로그램이 파일을 바꾸면 자동으로 다시 읽습니다.
- Finder에서 스페이스바(훑어보기)를 눌러도 렌더링된 모습으로 보입니다.
- 표, 체크리스트, 코드 하이라이트 등 GitHub 방식 마크다운을 지원합니다.
- 라이트/다크 모드를 따라갑니다.

macOS 14 이상에서 동작하며, 애플 실리콘과 인텔 맥을 모두 지원합니다.

## 설치

### 방법 1. 터미널 한 줄

```bash
curl -fsSL https://raw.githubusercontent.com/hisumin46/mdr/main/install.sh | bash
```

최신 버전을 내려받아 `/Applications/mdr.app`으로 설치하고, 터미널 명령어 `mdr`을 `~/.local/bin`에 연결합니다. 업데이트할 때도 같은 명령을 다시 실행하면 됩니다.

`~/.local/bin`이 `PATH`에 없으면 설치가 끝날 때 추가할 줄을 알려 줍니다. 다른 폴더에 두려면 이렇게 실행합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/hisumin46/mdr/main/install.sh | MDR_BIN_DIR=/usr/local/bin bash
```

### 방법 2. dmg 파일

1. [mdr.dmg](https://github.com/hisumin46/mdr/releases/latest/download/mdr.dmg)를 내려받아 엽니다.
2. `mdr`을 `Applications` 폴더로 끌어다 놓습니다.
3. 터미널에서 아래 명령을 한 번 실행합니다.

   ```bash
   xattr -dr com.apple.quarantine /Applications/mdr.app
   ```

   mdr은 Apple 공증을 받지 않은 앱이라, 브라우저로 받은 경우 이 명령 없이는 macOS가 실행을 막습니다. 터미널 대신 앱을 한 번 열어 본 뒤 `시스템 설정 > 개인정보 보호 및 보안`에서 `그래도 열기`를 눌러도 됩니다.

4. 터미널 명령어 `mdr`도 쓰려면 연결해 줍니다.

   ```bash
   mkdir -p ~/.local/bin
   ln -sf /Applications/mdr.app/Contents/Resources/mdr ~/.local/bin/mdr
   ```

### 방법 3. 소스에서 빌드

Xcode 명령어 도구(`xcode-select --install`)가 필요합니다.

```bash
git clone https://github.com/hisumin46/mdr.git
cd mdr
./build.sh install
```

## 사용법

```bash
mdr README.md        # 파일 열기
mdr a.md b.md        # 여러 파일을 각각 새 창으로
mdr                  # 파일 선택 창
```

Finder에서 `.md` 파일을 mdr로 열려면 파일을 우클릭해 `정보 가져오기 > 다음으로 열기`에서 mdr을 고르고 `모두 변경`을 누릅니다.

| 동작 | 단축키 |
| --- | --- |
| 미리보기 / 수정 전환 | `⌘E` |
| 저장 | `⌘S` |
| 수정 화면에서 미리보기로 | `esc` |
| 찾기, 다음, 이전 | `⌘F`, `⌘G`, `⇧⌘G` |
| 디스크에서 다시 읽기 | `⌘R` |
| Finder에서 보기 | `⇧⌘R` |
| 확대, 축소, 원래 크기 | `⌘=`, `⌘-`, `⌘0` |
| 파일 열기 | `⌘O` |

창 오른쪽 위의 `수정`, `저장`, `미리보기` 버튼으로도 같은 동작을 할 수 있습니다.

## 알아 둘 점

- 훑어보기(스페이스바)는 읽기 전용입니다. 수정하려면 mdr 창으로 여세요.
- 훑어보기에서는 상대 경로 이미지가 보이지 않습니다. mdr 창에서는 보입니다.
- LaTeX 수식과 mermaid 다이어그램은 지원하지 않습니다.

## 삭제

```bash
rm -rf /Applications/mdr.app ~/.local/bin/mdr
```

## 개발

Xcode 프로젝트 없이 `swiftc`로 빌드합니다.

```bash
./build.sh            # build/mdr.app
./build.sh install    # 빌드 후 /Applications 에 설치
./build.sh dmg        # 배포용 build/mdr.dmg (인텔·애플 실리콘 겸용)
```

| 경로 | 내용 |
| --- | --- |
| `Sources/main.swift` | 앱 본체 (AppKit + WKWebView) |
| `Resources/web/` | 미리보기·수정 화면 (HTML, CSS, JS) |
| `QuickLook/` | Finder 훑어보기 확장 |
| `bin/mdr` | 터미널 명령어 |
| `scripts/make-icon.swift` | 앱 아이콘 생성 |

마크다운 렌더링에는 [marked](https://github.com/markedjs/marked), [DOMPurify](https://github.com/cure53/DOMPurify), [highlight.js](https://github.com/highlightjs/highlight.js)를 사용합니다.
