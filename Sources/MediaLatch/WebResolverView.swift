import SwiftUI
import WebKit

struct WebResolverLink: Identifiable {
    let source: URL
    var id: URL { source }

    init?(_ source: URL) {
        guard let host = source.host?.lowercased(),
              RednoteGallery.matches(source) || host == "douyin.com" || host.hasSuffix(".douyin.com") else { return nil }
        self.source = source
    }

    var page: URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "dyxhsdownloader.com"
        parts.path = "/"
        parts.queryItems = [URLQueryItem(name: "url", value: source.absoluteString)]
        return parts.url!
    }
}

struct WebResolverView: View {
    let link: WebResolverLink
    let directory: URL

    @Environment(\.dismiss) private var dismiss
    @State private var controller: ResolverBrowser?
    @State private var message: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("网页解析 · dyxhsdownloader.com").font(.headline)
                    Text("继续后，当前分享链接将发送给该网站。下载保存到「\(directory.lastPathComponent)」。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding()
            Divider()
            if let controller {
                ResolverWebView(webView: controller.webView)
                if !message.isEmpty {
                    Divider()
                    Text(message).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                }
            } else {
                VStack(spacing: 16) {
                    Text(link.source.absoluteString).textSelection(.enabled).lineLimit(3)
                    Button("发送此链接并打开网站") {
                        controller = ResolverBrowser(url: link.page, directory: directory) { message = $0 }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 840, minHeight: 630)
    }
}

private struct ResolverWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

@MainActor
private final class ResolverBrowser: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    let webView: WKWebView
    private let directory: URL
    private let update: (String) -> Void
    private var transfers: [ObjectIdentifier: (temp: URL, name: String)] = [:]
    private let allowedExtensions: Set<String> = ["mp4", "mov", "m4a", "jpg", "jpeg", "png", "webp", "heic", "zip"]

    init(url: URL, directory: URL, update: @escaping (String) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.directory = directory
        self.update = update
        super.init()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.targetFrame?.isMainFrame == false { return .allow }
        guard let url = action.request.url else { return .cancel }
        if url.scheme == "blob", action.shouldPerformDownload { return .download }
        guard url.scheme == "https", url.host == "dyxhsdownloader.com" else { return .cancel }
        return action.shouldPerformDownload ? .download : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard response.isForMainFrame else { return .allow }
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        if disposition?.lowercased().hasPrefix("attachment") == true || !response.canShowMIMEType { return .download }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let name = (suggestedFilename as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            update("网站没有返回可保存的视频、图片或 ZIP 文件。")
            return nil
        }
        let temp = directory.appendingPathComponent(".medialatch-web-" + UUID().uuidString)
        transfers[ObjectIdentifier(download)] = (temp, name)
        update("正在保存 " + name)
        return temp
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        defer { try? FileManager.default.removeItem(at: transfer.temp) }
        do {
            let size = try transfer.temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 else { throw MediaLatchError.process("网站返回了空文件。") }
            let url = try move(transfer.temp, named: transfer.name)
            update("已保存 " + url.lastPathComponent)
        } catch {
            update(error.localizedDescription)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: transfer.temp)
        }
        update(error.localizedDescription)
    }

    private func move(_ temp: URL, named name: String) throws -> URL {
        let fm = FileManager.default
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 1...Int.max {
            let file = directory.appendingPathComponent(index == 1 ? name : "\(stem) (\(index)).\(ext)")
            do {
                try fm.moveItem(at: temp, to: file)
                return file
            } catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
        }
        throw MediaLatchError.process("无法创建下载文件。")
    }
}
