import Cocoa
import JavaScriptCore
import QuickLookUI
import UniformTypeIdentifiers

/// Finder 훑어보기(스페이스바)용. 마크다운을 HTML 로 바꿔 시스템에 넘긴다.
/// 웹뷰를 직접 띄우지 않고, 앱과 같은 marked/highlight.js 를 JavaScriptCore 로 돌린다.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 900, height: 1000)
        ) { reply in
            reply.stringEncoding = .utf8
            return Data(PreviewProvider.page(for: url).utf8)
        }
        reply.title = url.lastPathComponent
        return reply
    }

    private static func resource(_ name: String) -> String {
        guard let url = Bundle(for: PreviewProvider.self).url(forResource: name, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    private static func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        if let text = String(data: data, encoding: .utf8) { return text }
        let cf = CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
        let korean = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        return String(data: data, encoding: korean) ?? String(decoding: data, as: UTF8.self)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func render(_ markdown: String) -> String {
        guard let context = JSContext() else { return "<pre>\(escape(markdown))</pre>" }
        for script in ["marked.js", "highlight.js", "render.js"] {
            context.evaluateScript(resource(script))
        }
        let result = context.objectForKeyedSubscript("mdrRender")?.call(withArguments: [markdown])
        if let html = result?.toString(), result?.isString == true, context.exception == nil {
            return html
        }
        return "<pre>\(escape(markdown))</pre>"
    }

    static func page(for url: URL) -> String {
        """
        <!doctype html>
        <html lang="ko">
        <head>
        <meta charset="utf-8">
        <style>\(resource("style.css"))</style>
        </head>
        <body>
        <article class="markdown">\(render(read(url)))</article>
        </body>
        </html>
        """
    }
}
