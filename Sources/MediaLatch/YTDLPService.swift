import Foundation

actor ToolManager {
    private var cachedYTDLP: URL?

    func ytDLP() async throws -> URL {
        if let cachedYTDLP, FileManager.default.isExecutableFile(atPath: cachedYTDLP.path) {
            return cachedYTDLP
        }

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("bin/yt-dlp"),
            URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"),
            URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            installedToolURL
        ].compactMap { $0 }

        if let existing = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            cachedYTDLP = existing
            return existing
        }

        return try await installYTDLP()
    }

    nonisolated var ffmpegURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("bin/ffmpeg"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/bin/ffmpeg")
        ].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    nonisolated var nodeURL: URL? {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
            URL(fileURLWithPath: "/usr/bin/node")
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private var installedToolURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MediaLatch/bin/yt-dlp")
    }

    private func installYTDLP() async throws -> URL {
        guard let remoteURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
            throw MediaLatchError.dependency("无法创建下载组件地址。")
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw MediaLatchError.dependency("下载组件安装失败（HTTP \(http.statusCode)）。")
            }

            let destination = installedToolURL
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            cachedYTDLP = destination
            return destination
        } catch let error as MediaLatchError {
            throw error
        } catch {
            throw MediaLatchError.dependency("首次运行需要安装下载组件：\(error.localizedDescription)")
        }
    }
}

final class YTDLPService: @unchecked Sendable {
    static let downloadProgressArguments = [
        "--newline",
        "--progress",
        "--no-colors"
    ]

    enum Event {
        case progress(Double)
        case processing
        case file(URL)
        case log(String)
    }

    private let tools = ToolManager()

    func prepare() async throws {
        _ = try await tools.ytDLP()
        guard tools.ffmpegURL != nil else {
            throw MediaLatchError.dependency("缺少 FFmpeg。请先安装 FFmpeg 后重试。")
        }
    }

    func analyze(_ source: String) async throws -> MediaInfo {
        guard let url = URL(string: source), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw MediaLatchError.invalidURL
        }

        if RednoteGallery.matches(url), let gallery = try await RednoteGallery.fetch(url) {
            return gallery
        }

        let executable = try await tools.ytDLP()
        var arguments = commonArguments()
        arguments += [
            "--no-playlist",
            "--dump-single-json",
            "--no-warnings",
            source
        ]

        let host = url.host?.lowercased() ?? ""
        let isBili = host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "b23.tv"
        let scratch = isBili ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) : nil
        if let scratch {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            arguments.insert("--write-pages", at: 0)
        }
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        let data: Data
        do {
            data = try await runCapture(executable: executable, arguments: arguments, directory: scratch)
        } catch {
            let message = error.localizedDescription
            if message.contains("Fresh cookies") {
                throw MediaLatchError.process("抖音拒绝了当前访客请求，未返回视频。")
            }
            if RednoteGallery.matches(url), message.contains("No video formats found") {
                throw MediaLatchError.process("小红书未向当前访客返回可下载的视频或图片。")
            }
            if message.contains("IP address is blocked") {
                throw MediaLatchError.process("TikTok 拒绝当前网络访问这条视频。")
            }
            throw error
        }
        let metadata: Metadata
        do {
            metadata = try JSONDecoder().decode(Metadata.self, from: data)
        } catch {
            throw MediaLatchError.invalidResponse
        }

        guard let id = metadata.id, let title = metadata.title else {
            throw MediaLatchError.invalidResponse
        }

        let heights = Array(Set((metadata.formats ?? []).compactMap(\.height)))
            .filter { $0 >= 144 }
            .sorted(by: >)

        var thumbnail = metadata.thumbnail ?? metadata.thumbnails?.last?.url
        if isBili, let value = thumbnail, value.hasPrefix("http://") { thumbnail = "https://" + value.dropFirst(7) }
        return MediaInfo(
            id: id,
            sourceURL: source,
            title: title,
            creator: metadata.uploader ?? metadata.channel ?? "未知创作者",
            thumbnailURL: thumbnail,
            duration: metadata.duration ?? 0,
            availableHeights: heights,
            descriptionText: metadata.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            backupInfo: scratch.flatMap { BackupSource.info(metadata: data, directory: $0) },
            downloadInfo: metadata.formats?.isEmpty == false ? data : nil
        )
    }

    func startDownload(
        media: MediaInfo,
        request: DownloadRequest,
        reuseAnalysis: Bool = true,
        eventHandler: @escaping @Sendable (Event) -> Void,
        completion: @escaping @Sendable (Result<URL?, Error>) -> Void
    ) async throws -> Process {
        let executable = try await tools.ytDLP()
        guard let ffmpeg = tools.ffmpegURL else {
            throw MediaLatchError.dependency("找不到 FFmpeg，无法合并或转换媒体。")
        }

        var arguments = commonArguments()
        arguments += [
            "--no-playlist",
        ]
        // Bilibili media servers may reject a whole-file GET while serving byte ranges.
        if let host = URL(string: media.sourceURL)?.host?.lowercased(),
           host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "b23.tv" || host.hasSuffix(".b23.tv") {
            arguments += ["--http-chunk-size", "4M"]
        }
        arguments += Self.downloadProgressArguments
        arguments += [
            "--continue",
            "--no-overwrites",
            "--embed-metadata",
            "--ffmpeg-location", ffmpeg.path,
            "--progress-template", "download:MEDIALATCH_PROGRESS:%(progress._percent_str)s",
            "--print", "after_move:MEDIALATCH_FILE:%(filepath)s"
        ]

        switch request.kind {
        case .video:
            let heightLimit = request.videoHeight == 0 ? "" : "[height<=\(request.videoHeight)]"
            arguments += [
                "-f", "bestvideo*\(heightLimit)+bestaudio/best\(heightLimit)",
                "--merge-output-format", request.format,
                "--remux-video", request.format
            ]
        case .audio:
            let selector = request.format == "m4a" && request.audioQuality == "原始质量"
                ? "bestaudio[ext=m4a]/bestaudio"
                : "bestaudio/best"
            arguments += [
                "-f", selector,
                "--extract-audio",
                "--audio-format", request.format,
                "--audio-quality", audioQualityArgument(request.audioQuality, format: request.format)
            ]
        }

        let outputTemplate = request.outputDirectory
            .appendingPathComponent(request.useBackup ? "%(title).180B [%(id)s] (备用源).%(ext)s" : "%(title).180B [%(id)s].%(ext)s")
            .path
        arguments += ["--output", outputTemplate]
        // Reuse short-lived stream URLs for an immediate download. Retries resolve them again.
        let fresh = reuseAnalysis && Date().timeIntervalSince(media.parsedAt) < 90
        let info: Data?
        if request.useBackup {
            if fresh, let backup = media.backupInfo {
                info = backup
            } else {
                guard let backup = try await analyze(media.sourceURL).backupInfo else {
                    throw MediaLatchError.process("该视频当前没有可用的备用源。")
                }
                info = backup
            }
        } else {
            info = fresh ? media.downloadInfo : nil
        }
        if let info {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try info.write(to: file, options: .withoutOverwriting)
            arguments += ["--load-info-json", file.path]
            do {
                return try launchStreaming(executable: executable, arguments: arguments, eventHandler: eventHandler) { result in
                    try? FileManager.default.removeItem(at: file)
                    completion(result)
                }
            } catch {
                try? FileManager.default.removeItem(at: file)
                throw error
            }
        }
        arguments.append(media.sourceURL)

        return try launchStreaming(
            executable: executable,
            arguments: arguments,
            eventHandler: eventHandler,
            completion: completion
        )
    }

    private func commonArguments() -> [String] {
        var arguments = ["--socket-timeout", "15", "--extractor-retries", "1"]
        if let node = tools.nodeURL {
            arguments += ["--js-runtimes", "node:\(node.path)", "--remote-components", "ejs:github"]
        }
        return arguments
    }

    private func audioQualityArgument(_ quality: String, format: String) -> String {
        guard format == "mp3" || format == "m4a" else { return "0" }
        return quality == "原始质量" ? "0" : quality.replacingOccurrences(of: "kbps", with: "K")
    }

    private func runCapture(executable: URL, arguments: [String], directory: URL? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = configuredProcess(executable: executable, arguments: arguments)
            process.currentDirectoryURL = directory
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let output = LockedData()
            let errors = LockedData()

            process.standardOutput = outputPipe
            process.standardError = errorPipe
            outputPipe.fileHandleForReading.readabilityHandler = { output.append($0.availableData) }
            errorPipe.fileHandleForReading.readabilityHandler = { errors.append($0.availableData) }

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                errors.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output.value)
                } else {
                    let message = String(data: errors.value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: MediaLatchError.process(message?.isEmpty == false ? message! : "链接解析失败。"))
                }
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: MediaLatchError.process(error.localizedDescription))
            }
        }
    }

    private func launchStreaming(
        executable: URL,
        arguments: [String],
        eventHandler: @escaping @Sendable (Event) -> Void,
        completion: @escaping @Sendable (Result<URL?, Error>) -> Void
    ) throws -> Process {
        let process = configuredProcess(executable: executable, arguments: arguments)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputDecoder = LineDecoder()
        let errorDecoder = LineDecoder()
        let outputFile = LockedURL()
        let errorTail = LockedTextTail()

        func consume(_ lines: [String]) {
            for line in lines where !line.isEmpty {
                if let marker = line.range(of: "MEDIALATCH_PROGRESS:") {
                    let value = line[marker.upperBound...]
                        .replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let progress = Double(value) {
                        eventHandler(.progress(min(max(progress / 100, 0), 1)))
                    }
                } else if let marker = line.range(of: "MEDIALATCH_FILE:") {
                    let path = String(line[marker.upperBound...])
                    let url = URL(fileURLWithPath: path)
                    outputFile.value = url
                    eventHandler(.file(url))
                } else if line.contains("[Merger]") || line.contains("[ExtractAudio]") || line.contains("[VideoRemuxer]") {
                    eventHandler(.processing)
                } else {
                    eventHandler(.log(line))
                }
            }
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(outputDecoder.push(handle.availableData))
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let lines = errorDecoder.push(handle.availableData)
            errorTail.append(lines)
            consume(lines)
        }

        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            consume(outputDecoder.push(outputPipe.fileHandleForReading.readDataToEndOfFile()) + outputDecoder.flush())
            let finalErrors = errorDecoder.push(errorPipe.fileHandleForReading.readDataToEndOfFile()) + errorDecoder.flush()
            errorTail.append(finalErrors)
            consume(finalErrors)

            if process.terminationStatus == 0 {
                completion(.success(outputFile.value))
            } else {
                completion(.failure(MediaLatchError.process(errorTail.text.isEmpty ? "下载未完成。" : errorTail.text)))
            }
        }

        try process.run()
        return process
    }

    private func configuredProcess(executable: URL, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        return process
    }
}

private struct Metadata: Decodable {
    let id: String?
    let title: String?
    let description: String?
    let uploader: String?
    let channel: String?
    let thumbnail: String?
    let thumbnails: [Thumbnail]?
    let duration: Double?
    let formats: [Format]?
}

private struct Thumbnail: Decodable {
    let url: String?
}

private struct Format: Decodable {
    let height: Int?
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LockedURL: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URL?

    var value: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class LockedTextTail: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ additions: [String]) {
        guard !additions.isEmpty else { return }
        lock.lock()
        lines.append(contentsOf: additions)
        lines = Array(lines.suffix(8))
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

private final class LineDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func push(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)

        var lines: [String] = []
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer[..<newline.lowerBound]
            buffer.removeSubrange(...newline.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: .newlines))
            }
        }
        return lines
    }

    func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return [] }
        let line = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll()
        return [line]
    }
}
