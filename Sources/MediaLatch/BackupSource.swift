import Foundation

enum BackupSource {
    // yt-dlp's normalized formats omit the mirrors returned in Bilibili's DASH manifest.
    static func info(metadata: Data, directory: URL) -> Data? {
        guard let document = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let formats = document["formats"] as? [[String: Any]],
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return nil }
        var mirrors: [String: String] = [:]
        for file in files where file.lastPathComponent.contains("playurl") && file.pathExtension == "dump" {
            guard let data = try? Data(contentsOf: file),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = body["data"] as? [String: Any],
                  let dash = response["dash"] as? [String: Any] else { continue }
            for track in (dash["video"] as? [[String: Any]] ?? []) + (dash["audio"] as? [[String: Any]] ?? []) {
                guard let primary = track["baseUrl"] as? String,
                      let backups = track["backupUrl"] as? [String],
                      let url = backups.first(where: { $0 != primary && $0.hasPrefix("https://") }) else { continue }
                mirrors[primary] = url
            }
        }
        let alternate = formats.compactMap { format -> [String: Any]? in
            guard let url = format["url"] as? String, let backup = mirrors[url] else { return nil }
            var copy = format
            copy["url"] = backup
            return copy
        }
        guard alternate.contains(where: { ($0["vcodec"] as? String ?? "none") != "none" }),
              alternate.contains(where: { ($0["acodec"] as? String ?? "none") != "none" }) else { return nil }
        var info = document.filter { ["id", "title", "extractor", "extractor_key", "webpage_url", "duration", "description", "uploader", "http_headers"].contains($0.key) }
        info["formats"] = alternate
        return try? JSONSerialization.data(withJSONObject: info)
    }
}
