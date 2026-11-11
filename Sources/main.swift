import Cocoa
import WebKit

let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx"]
let frameName = "mdr.window"

struct DiskStamp: Equatable {
    let modified: Date
    let size: Int
}

// MARK: - 문서 창 하나

final class DocumentWindow: NSObject, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let url: URL
    let window: NSWindow
    let webView: WKWebView
    var onClose: (() -> Void)?
    var openOther: ((URL) -> Void)?
    private(set) var dirty = false

    private var encoding: String.Encoding = .utf8
    private var ready = false
    private var stamp: DiskStamp?
    private var timer: Timer?
    private let indexURL: URL

    init(url: URL) {
        self.url = url
        indexURL = Bundle.main.resourceURL!.appendingPathComponent("web/index.html")

        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = DocumentWindow.savedZoom

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 960),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .textBackgroundColor
        window.title = url.lastPathComponent
        window.representedURL = url
        window.tabbingMode = .disallowed  // 파일마다 항상 별도 창 (탭으로 합치지 않음)
        window.minSize = NSSize(width: 420, height: 320)
        window.contentView = webView
        window.initialFirstResponder = webView

        super.init()

        config.userContentController.add(self, name: "mdr")
        webView.navigationDelegate = self
        window.delegate = self
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkDisk()
        }
    }

    // MARK: 파일 읽기/쓰기

    private static var koreanEncoding: String.Encoding {
        let cf = CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private func readFile() -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            encoding = .utf8
            return text
        }
        if let text = String(data: data, encoding: DocumentWindow.koreanEncoding) {
            encoding = DocumentWindow.koreanEncoding
            return text
        }
        encoding = .utf8
        return String(decoding: data, as: UTF8.self)
    }

    private func currentStamp() -> DiskStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int else { return nil }
        return DiskStamp(modified: modified, size: size)
    }

    private func write(_ text: String) -> Bool {
        do {
            let data = text.data(using: encoding) ?? Data(text.utf8)
            try data.write(to: url, options: .atomic)
            stamp = currentStamp()
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "저장하지 못했습니다"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
            return false
        }
    }

    private func js(_ body: String, _ arguments: [String: Any] = [:]) {
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { _ in }
    }

    private func loadFromDisk(keepScroll: Bool) {
        guard let text = readFile() else {
            js("mdr.notice(message)", ["message": "파일을 읽을 수 없습니다"])
            return
        }
        stamp = currentStamp()
        js("mdr.load(text, base, keepScroll)", [
            "text": text,
            "base": url.deletingLastPathComponent().absoluteString,
            "keepScroll": keepScroll,
        ])
    }

    private func checkDisk() {
        guard ready, let now = currentStamp(), now != stamp else { return }
        stamp = now
        if dirty {
            js("mdr.notice(message)", ["message": "디스크의 파일이 바뀌었습니다 · 저장하면 덮어씁니다"])
        } else {
            loadFromDisk(keepScroll: true)
        }
    }

    // MARK: 웹뷰 → 앱 메시지

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            loadFromDisk(keepScroll: false)
            // 자동 검증용: MDR_EVAL 환경변수의 JS 를 로드 직후 실행한다.
            if let script = ProcessInfo.processInfo.environment["MDR_EVAL"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.js(script) }
            }
        case "dirty":
            dirty = body["value"] as? Bool ?? false
            window.isDocumentEdited = dirty
        case "save":
            guard let text = body["text"] as? String else { return }
            if write(text) { js("mdr.saved(text)", ["text": text]) }
        case "link":
            if let href = body["href"] as? String, let target = URL(string: href) { follow(target) }
        default:
            break
        }
    }

    private func follow(_ target: URL) {
        guard target.isFileURL else {
            if ["http", "https", "mailto"].contains(target.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(target)
            }
            return
        }
        let file = URL(fileURLWithPath: target.path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            js("mdr.notice(message)", ["message": "파일이 없습니다: \(file.lastPathComponent)"])
            return
        }
        if markdownExtensions.contains(file.pathExtension.lowercased()) {
            openOther?(file)
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { return decisionHandler(.cancel) }
        if target.isFileURL && target.path == indexURL.path {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            follow(target)
        }
    }

    // MARK: 메뉴 동작 (창 delegate 는 responder chain 에 포함된다)

    /// 키 입력이 웹뷰(편집기)로 가도록 한다. 창을 클릭하지 않고 단축키만 쓴 경우에 필요하다.
    func focusContent() { window.makeFirstResponder(webView) }

    @objc func toggleEdit(_ sender: Any?) {
        focusContent()
        js("mdr.toggle()")
    }
    @objc func saveDocument(_ sender: Any?) { js("mdr.save()") }
    @objc func findInPage(_ sender: Any?) { js("mdr.find()") }
    @objc func findNext(_ sender: Any?) { js("mdr.findStep(1)") }
    @objc func findPrevious(_ sender: Any?) { js("mdr.findStep(-1)") }

    @objc func reloadDocument(_ sender: Any?) {
        guard dirty else { return loadFromDisk(keepScroll: true) }
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 변경을 버리고 다시 불러올까요?"
        alert.addButton(withTitle: "다시 불러오기")
        alert.addButton(withTitle: "취소")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.loadFromDisk(keepScroll: true) }
        }
    }

    @objc func revealInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static var savedZoom: CGFloat {
        let value = UserDefaults.standard.double(forKey: "zoom")
        return value > 0 ? CGFloat(value) : 1
    }

    private func setZoom(_ value: CGFloat) {
        let clamped = min(max(value, 0.5), 3)
        webView.pageZoom = clamped
        UserDefaults.standard.set(Double(clamped), forKey: "zoom")
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { setZoom(1) }

    // MARK: 닫기

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent)의 변경 내용을 저장할까요?"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "저장 안 함")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.webView.evaluateJavaScript("mdr.text()") { result, _ in
                    if let text = result as? String, self.write(text) { self.window.close() }
                }
            case .alertThirdButtonReturn:
                self.window.close()
            default:
                break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        window.saveFrame(usingName: frameName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mdr")
        onClose?()
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var documents: [URL: DocumentWindow] = [:]
    private var cascadePoint = NSPoint.zero

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 실행 파일을 직접 부른 경우(mdr.app/Contents/MacOS/mdr a.md)의 인자
        for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
            open(URL(fileURLWithPath: argument))
        }
        // 파일과 함께 실행되면 open(urls) 가 곧바로 온다. 아무것도 안 열렸을 때만 열기 창을 띄운다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.documents.isEmpty else { return }
            self.openDocument(nil)
            if self.documents.isEmpty { NSApp.terminate(nil) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsaved = documents.values.filter(\.dirty)
        guard !unsaved.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 문서가 \(unsaved.count)개 있습니다"
        alert.informativeText = unsaved.map(\.url.lastPathComponent).sorted().joined(separator: ", ")
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "버리고 종료")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func open(_ raw: URL) {
        let url = raw.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = documents[url] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return }

        let document = DocumentWindow(url: url)
        document.onClose = { [weak self] in self?.documents[url] = nil }
        document.openOther = { [weak self] other in self?.open(other) }
        documents[url] = document

        if !document.window.setFrameUsingName(frameName) { document.window.center() }
        cascadePoint = document.window.cascadeTopLeft(from: cascadePoint)
        document.window.makeKeyAndOrderFront(nil)
        document.focusContent()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "마크다운 파일을 선택하세요"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach(open) }
    }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            build(menu)
            item.submenu = menu
            main.addItem(item)
        }
        @discardableResult
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                 _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }

        submenu("mdr") { menu in
            add(menu, "mdr 가리기", #selector(NSApplication.hide(_:)), "h")
            add(menu, "기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            menu.addItem(.separator())
            add(menu, "mdr 종료", #selector(NSApplication.terminate(_:)), "q")
        }
        submenu("파일") { menu in
            add(menu, "열기…", #selector(AppDelegate.openDocument(_:)), "o")
            menu.addItem(.separator())
            add(menu, "저장", #selector(DocumentWindow.saveDocument(_:)), "s")
            add(menu, "다시 불러오기", #selector(DocumentWindow.reloadDocument(_:)), "r")
            add(menu, "Finder에서 보기", #selector(DocumentWindow.revealInFinder(_:)), "r", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "닫기", #selector(NSWindow.performClose(_:)), "w")
        }
        submenu("편집") { menu in
            add(menu, "실행 취소", Selector(("undo:")), "z")
            add(menu, "실행 복귀", Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "오려두기", #selector(NSText.cut(_:)), "x")
            add(menu, "복사", #selector(NSText.copy(_:)), "c")
            add(menu, "붙여넣기", #selector(NSText.paste(_:)), "v")
            add(menu, "전체 선택", #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())
            add(menu, "찾기…", #selector(DocumentWindow.findInPage(_:)), "f")
            add(menu, "다음 찾기", #selector(DocumentWindow.findNext(_:)), "g")
            add(menu, "이전 찾기", #selector(DocumentWindow.findPrevious(_:)), "g", [.command, .shift])
        }
        submenu("보기") { menu in
            add(menu, "미리보기 / 수정 전환", #selector(DocumentWindow.toggleEdit(_:)), "e")
            menu.addItem(.separator())
            add(menu, "확대", #selector(DocumentWindow.zoomIn(_:)), "=")
            add(menu, "축소", #selector(DocumentWindow.zoomOut(_:)), "-")
            add(menu, "실제 크기", #selector(DocumentWindow.zoomReset(_:)), "0")
        }
        submenu("윈도우") { menu in
            add(menu, "최소화", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(menu, "확대/축소", #selector(NSWindow.performZoom(_:)))
            NSApp.windowsMenu = menu
        }
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
