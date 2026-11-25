import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GalleryDownload {
    static func save(_ media: MediaInfo, in directory: URL) async throws -> URL {
        let manager = FileManager.default
        let staging = directory.appendingPathComponent(".medialatch-" + UUID().uuidString)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let images = Array(media.gallery.enumerated())
        for start in stride(from: 0, to: images.count, by: 4) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, url) in images[start..<min(start + 4, images.count)] {
                    group.addTask {
                        var request = URLRequest(url: url, timeoutInterval: 20)
                        request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                              let source = CGImageSourceCreateWithData(data as CFData, nil),
                              let type = CGImageSourceGetType(source),
                              let ext = UTType(type as String)?.preferredFilenameExtension,
                              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                            throw MediaLatchError.process("第 \(index + 1) 张图片下载失败。")
                        }
                        let file = staging.appendingPathComponent(String(format: "%02d", index + 1)).appendingPathExtension(ext)
                        try data.write(to: file)
                    }
                }
                try await group.waitForAll()
            }
        }
        let name = String(media.title.prefix(40)).replacingOccurrences(of: "/", with: "-")
        let base = "\(name) [\(media.id)]"
        for index in 1...Int.max {
            let folder = directory.appendingPathComponent(index == 1 ? base : "\(base) (\(index))")
            do {
                try manager.moveItem(at: staging, to: folder)
                return folder
            } catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
        }
        throw MediaLatchError.process("无法创建图集文件夹。")
    }
}
