# mdr

English | [한국어](README.ko.md)

A Markdown reader for macOS. It opens `.md` files as a rendered preview, and lets you edit and save only when you need to.

- Each file opens in its own window.
- The preview reloads automatically when another program changes the file.
- Pressing the space bar in Finder (Quick Look) also shows the rendered Markdown.
- Supports GitHub Flavored Markdown: tables, task lists, syntax highlighting.
- Follows the system light and dark appearance.

Requires macOS 14 or later. Runs on both Apple silicon and Intel Macs.

The app's menus and messages are in Korean.

## Install

### Option 1. One line in the terminal

```bash
curl -fsSL https://raw.githubusercontent.com/hisumin46/mdr/main/install.sh | bash
```

This downloads the latest version, installs it as `/Applications/mdr.app`, and links the `mdr` command into `~/.local/bin`. Run the same command again to update.

If `~/.local/bin` is not on your `PATH`, the installer prints the line to add. To put the command somewhere else:

```bash
curl -fsSL https://raw.githubusercontent.com/hisumin46/mdr/main/install.sh | MDR_BIN_DIR=/usr/local/bin bash
```

### Option 2. The dmg file

1. Download [mdr.dmg](https://github.com/hisumin46/mdr/releases/latest/download/mdr.dmg) and open it.
2. Drag `mdr` into the `Applications` folder.
3. Run this once in the terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/mdr.app
   ```

   mdr is not notarized by Apple, so macOS blocks it when the dmg was downloaded with a browser. Instead of the terminal, you can also try to open the app once and then click `Open Anyway` in `System Settings > Privacy & Security`.

4. To use the `mdr` command as well, link it:

   ```bash
   mkdir -p ~/.local/bin
   ln -sf /Applications/mdr.app/Contents/Resources/mdr ~/.local/bin/mdr
   ```

### Option 3. Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/hisumin46/mdr.git
cd mdr
./build.sh install
```

## Usage

```bash
mdr README.md        # open a file
mdr a.md b.md        # open several files, each in a new window
mdr                  # show the file picker
```

To open `.md` files with mdr from Finder, right-click a file, choose `Get Info`, pick mdr under `Open with`, and click `Change All…`.

| Action | Shortcut |
| --- | --- |
| Switch between preview and edit | `⌘E` |
| Save | `⌘S` |
| Back to preview from the editor | `esc` |
| Find, next, previous | `⌘F`, `⌘G`, `⇧⌘G` |
| Reload from disk | `⌘R` |
| Show in Finder | `⇧⌘R` |
| Zoom in, zoom out, actual size | `⌘=`, `⌘-`, `⌘0` |
| Magnify the page, like a web page | Pinch on the trackpad |
| Open the current file in another window | `⌘N` |
| Open a file | `⌘O` |

The buttons at the top right of the window do the same: `수정` (edit), `저장` (save), and `미리보기` (preview).

## Good to know

- Quick Look (space bar) is read-only. Open the file in an mdr window to edit it.
- Images with relative paths do not show in Quick Look. They do show in an mdr window.
- LaTeX math and mermaid diagrams are not supported.

## Uninstall

```bash
rm -rf /Applications/mdr.app ~/.local/bin/mdr
```

## Development

mdr is built with `swiftc`, without an Xcode project.

```bash
./build.sh            # build/mdr.app
./build.sh install    # build, then install into /Applications
./build.sh dmg        # build/mdr.dmg for distribution (Apple silicon + Intel)
```

| Path | Contents |
| --- | --- |
| `Sources/main.swift` | The app (AppKit + WKWebView) |
| `Resources/web/` | Preview and editor UI (HTML, CSS, JS) |
| `QuickLook/` | Finder Quick Look extension |
| `bin/mdr` | The terminal command |
| `scripts/make-icon.swift` | Generates the app icon |

Markdown rendering uses [marked](https://github.com/markedjs/marked), [DOMPurify](https://github.com/cure53/DOMPurify), and [highlight.js](https://github.com/highlightjs/highlight.js).
