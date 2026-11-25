import Foundation

enum RednoteGallery {
    static func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ["xiaohongshu.com", "rednote.com", "xhslink.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    static func fetch(_ url: URL) async throws -> MediaInfo? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        // Video extraction can still succeed when the public-page gallery probe fails.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let page = response.url, matches(page),
              let html = String(data: data, encoding: .utf8) else { return nil }
        if page.path == "/login" || page.path.hasPrefix("/login/") {
            throw MediaLatchError.process("小红书把这条链接导向登录页，当前访客无法读取笔记内容。")
        }
        return parse(html, source: url, page: page)
    }

    static func parse(_ html: String, source: URL, page: URL) -> MediaInfo? {
        guard let id = page.pathComponents.last,
              id.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil,
              let marker = html.range(of: #"window\.__INITIAL_STATE__\s*=\s*"#, options: .regularExpression),
              let end = html.range(of: "</script>", options: .caseInsensitive, range: marker.upperBound..<html.endIndex)
        else { return nil }

        let payload = html[marker.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
        // Replace JavaScript undefined values while preserving quoted strings verbatim.
        let pattern = #""(?:\\.|[^"\\])*"|\bundefined\b"#
        let tokens = try! NSRegularExpression(pattern: pattern)
        let json = NSMutableString(string: payload)
        for match in tokens.matches(in: payload, range: NSRange(payload.startIndex..., in: payload)).reversed()
        where json.substring(with: match.range) == "undefined" {
            json.replaceCharacters(in: match.range, with: "null")
        }
        guard let state = try? JSONSerialization.jsonObject(with: Data((json as String).utf8)) as? [String: Any],
              let noteState = state["note"] as? [String: Any],
              let map = noteState["noteDetailMap"] as? [String: Any],
              let detail = map[id] as? [String: Any],
              let note = detail["note"] as? [String: Any],
              note["type"] as? String == "normal",
              let images = note["imageList"] as? [[String: Any]] else { return nil }
        let urls = images.compactMap { image -> URL? in
            let variants = (image["infoList"] as? [[String: Any]] ?? [])
            return ([image["urlDefault"] as? String] + variants.map { $0["url"] as? String } + [image["urlPre"] as? String])
                .compactMap { $0 }.compactMap(imageURL).first
        }
        guard !urls.isEmpty, urls.count == images.count else { return nil }
        let title = note["title"] as? String ?? ""
        let user = note["user"] as? [String: Any]
        return MediaInfo(id: id, sourceURL: source.absoluteString, title: title.isEmpty ? "小红书图文笔记" : title,
                         creator: user?["nickname"] as? String ?? "小红书",
                         thumbnailURL: urls.first?.absoluteString, duration: 0, availableHeights: [],
                         descriptionText: note["desc"] as? String ?? "", gallery: urls)
    }

    private static func imageURL(_ value: String) -> URL? {
        guard var parts = URLComponents(string: value),
              let host = parts.host?.lowercased(), host == "xhscdn.com" || host.hasSuffix(".xhscdn.com"),
              parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = "https"
        return parts.url
    }
}
