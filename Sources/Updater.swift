import Cocoa

/// GitHub 의 최신 릴리스로 새 버전을 확인하고, 사용자가 고르면 install.sh 로 설치한 뒤 다시 연다.
final class Updater {
    struct Release {
        let version: String
        let notes: [String]
    }

    static let repo = "hisumin46/mdr"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func isNewer(_ version: String) -> Bool {
        version.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    /// 알림을 붙일 창 (맨 앞 문서 창)
    var frontWindow: (() -> NSWindow?)?
    /// "지금 업데이트"를 고르면 불린다. 앱은 종료를 시작하고, 종료가 확정되면 launchInstaller 를 부른다.
    var onInstall: (() -> Void)?

    private let feedURL: URL
    private let installScript: String

    init() {
        // 자동 검증용: MDR_UPDATE_FEED, MDR_INSTALL_SCRIPT 로 확인 주소와 설치 스크립트를 바꿀 수 있다.
        let env = ProcessInfo.processInfo.environment
        feedURL = URL(string: env["MDR_UPDATE_FEED"]
                      ?? "https://api.github.com/repos/\(Updater.repo)/releases/latest")!
        installScript = env["MDR_INSTALL_SCRIPT"]
            ?? "https://raw.githubusercontent.com/\(Updater.repo)/main/install.sh"
    }

    // MARK: 확인

    /// 앱을 켠 직후: 하루에 한 번만 확인하고, 새 버전이 있을 때만 묻는다.
    func checkOnLaunch() {
        let last = UserDefaults.standard.double(forKey: Updater.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > Updater.checkInterval else { return }
        fetchLatest { [weak self] result in
            guard let self, case .success(let release) = result else { return }
            if Updater.isNewer(release.version) {
                // 문서 창이 없으면(열기 창만 떠 있는 등) 이번엔 묻지 않고 다음 실행 때 다시 확인한다.
                guard let window = self.frontWindow?(), window.attachedSheet == nil else { return }
                self.offer(release)
            }
            self.markChecked()
        }
    }

    /// 메뉴의 "업데이트 확인…": 최신이어도, 확인에 실패해도 알려 준다.
    func checkFromMenu() {
        fetchLatest { [weak self] result in
            guard let self else { return }
            let alert = NSAlert()
            switch result {
            case .success(let release) where Updater.isNewer(release.version):
                self.markChecked()
                return self.offer(release)
            case .success:
                self.markChecked()
                alert.messageText = "최신 버전입니다"
                alert.informativeText = "지금 쓰는 버전(\(Updater.currentVersion))이 최신입니다."
            case .failure(let error):
                alert.messageText = "업데이트를 확인하지 못했습니다"
                alert.informativeText = error.localizedDescription
            }
            self.show(alert)
        }
    }

    private func markChecked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Updater.lastCheckKey)
    }

    private struct Payload: Decodable {
        let tagName: String
        let body: String?
    }

    private struct StatusError: LocalizedError {
        let code: Int
        var errorDescription: String? { "GitHub 응답 코드 \(code)" }
    }

    private func fetchLatest(_ done: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: feedURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Result<Release, Error> {
                if let error { throw error }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw StatusError(code: http.statusCode)
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let payload = try decoder.decode(Payload.self, from: data ?? Data())
                let tag = payload.tagName
                // 릴리스 노트의 "- " 목록만 보여 준다 (설치 안내 같은 나머지는 뺀다).
                let notes = (payload.body ?? "").components(separatedBy: .newlines)
                    .filter { $0.hasPrefix("- ") }
                    .prefix(8)
                    .map { "• " + $0.dropFirst(2).replacingOccurrences(of: "`", with: "") }
                return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, notes: notes)
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    // MARK: 알림

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "mdr \(release.version) 버전이 나왔습니다"
        var info = "지금 쓰는 버전은 \(Updater.currentVersion)입니다."
        if !release.notes.isEmpty { info += "\n\n" + release.notes.joined(separator: "\n") }
        info += "\n\n업데이트하면 mdr을 닫고 새 버전을 설치한 뒤, 열려 있던 파일과 함께 다시 엽니다."
        alert.informativeText = info
        alert.addButton(withTitle: "지금 업데이트")
        alert.addButton(withTitle: "나중에")
        show(alert) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.onInstall?() }
        }
    }

    private func show(_ alert: NSAlert, _ handler: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        if let window = frontWindow?(), window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    // MARK: 설치

    /// 앱이 종료되는 중에 부른다. 앱 프로세스가 끝나길 기다렸다가 install.sh 로 설치하고, 열려 있던 파일과 함께 다시 연다.
    /// 진행 기록은 ~/Library/Logs/mdr-update.log 에 남는다.
    func launchInstaller(reopen files: [URL]) {
        let script = """
            exec >>"$HOME/Library/Logs/mdr-update.log" 2>&1
            echo "--- $(date "+%Y-%m-%d %H:%M:%S")"
            pid=$1 script=$2 app=$3
            shift 3
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            curl -fsSL "$script" | bash
            open -a "$app" "$@"
            """
        spawnDetached(["/bin/bash", "-c", script, "mdr-update",
                       String(getpid()), installScript, Bundle.main.bundlePath] + files.map(\.path))
    }

    /// 앱이 끝나도 같이 정리되지 않도록 새 세션(setsid)으로 띄운다.
    private func spawnDetached(_ arguments: [String]) {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        let argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        posix_spawn(&pid, arguments[0], nil, &attributes, argv, environ)
    }
}
