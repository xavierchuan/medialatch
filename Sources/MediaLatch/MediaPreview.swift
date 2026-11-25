import SwiftUI
import AVKit
import UniformTypeIdentifiers
import ImageIO

struct MediaPreview: View {
    let media: MediaInfo
    let directory: URL
    let downloadBackup: () -> Void
    @State private var showPlayer = false
    @State private var message = ""
    @State private var saving = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if media.isGallery {
                AsyncImage(url: media.gallery.first) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: 112, height: 76).clipped().cornerRadius(8)
            } else {
                Button { showPlayer = true } label: {
                    ZStack {
                        AsyncImage(url: media.thumbnailURL.flatMap(URL.init(string:))) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { Color.secondary.opacity(0.15) }
                        Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    .frame(width: 112, height: 76).clipped().cornerRadius(8)
                }.buttonStyle(.plain).accessibilityLabel("播放有声预览")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(media.title).font(.headline).lineLimit(2)
                Text(media.isGallery ? "\(media.creator) · \(media.gallery.count) 张图片" : "\(media.creator) · \(media.durationText) · \(media.bestQualityText)")
                    .font(.caption).foregroundStyle(.secondary)
                if !media.descriptionText.isEmpty {
                    Text(media.descriptionText).lineLimit(2).textSelection(.enabled).font(.caption)
                }
                HStack {
                    Button("复制文案") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(media.copyText, forType: .string)
                        message = "已复制文案"
                    }
                    if media.isGallery {
                        Button("下载全部图片") { Task { await saveGallery() } }.disabled(saving)
                    }
                    if media.thumbnailURL != nil {
                        Button("下载封面") { Task { await saveCover() } }.disabled(saving)
                    }
                    if media.backupInfo != nil { Button("备用源下载", action: downloadBackup) }
                }.controlSize(.small)
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showPlayer) { PreviewPlayer(media: media) }
    }

    @MainActor private func saveGallery() async {
        guard !saving else { return }
        saving = true
        message = "正在下载图集…"
        defer { saving = false }
        do {
            let folder = try await GalleryDownload.save(media, in: directory)
            message = "已保存 \(media.gallery.count) 张图片到 " + folder.lastPathComponent
        } catch { message = error.localizedDescription }
    }

    @MainActor private func saveCover() async {
        guard !saving, let raw = media.thumbnailURL, let url = URL(string: raw) else { return }
        saving = true
        defer { saving = false }
        do {
            var request = URLRequest(url: url)
            request.setValue(media.sourceURL, forHTTPHeaderField: "Referer")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw MediaLatchError.process("未能取得封面图片。")
            }
            let name = String(media.title.prefix(40)).replacingOccurrences(of: "/", with: "-")
            let base = directory.appendingPathComponent(name + " 封面")
            var index = 1
            while true {
                let stem = index == 1 ? base : directory.appendingPathComponent(name + " 封面 (\(index))")
                let output = stem.appendingPathExtension(ext)
                do {
                    try data.write(to: output, options: .withoutOverwriting)
                    message = "已保存 " + output.lastPathComponent
                    break
                } catch let error as CocoaError where error.code == .fileWriteFileExists { index += 1 }
            }
        } catch { message = error.localizedDescription }
    }
}

private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

private struct PreviewPlayer: View {
    let media: MediaInfo
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = PreviewSession()

    var body: some View {
        VStack(spacing: 12) {
            HStack { Text(media.title).font(.headline); Spacer(); Button("关闭") { dismiss() } }
            if let player = session.player {
                NativePlayerView(player: player)
            } else if let message = session.error {
                Text(message).textSelection(.enabled).frame(maxHeight: .infinity)
            } else {
                VStack { ProgressView(); Text("正在准备有声预览…") }.frame(maxHeight: .infinity)
            }
        }.padding().frame(width: 620, height: 420)
        .task { await session.start(media) }
        .onDisappear { session.stop() }
    }
}

@MainActor private final class PreviewSession: ObservableObject {
    @Published var player: AVPlayer?
    @Published var error: String?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var process: Process?
    private var closed = false

    func start(_ media: MediaInfo) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let height = media.availableHeights.filter { $0 <= 480 }.max() ?? media.availableHeights.min() ?? 0
            let audioOnly = media.availableHeights.isEmpty
            let request = DownloadRequest(kind: audioOnly ? .audio : .video, format: audioOnly ? "m4a" : "mp4", videoHeight: height,
                                          audioQuality: "原始质量", outputDirectory: directory)
            let task = try await YTDLPService().startDownload(media: media, request: request, eventHandler: { _ in }) { result in
                Task { @MainActor in self.finished(result) }
            }
            process = task
            if closed && task.isRunning { task.terminate() }
        } catch { self.error = error.localizedDescription; clean() }
    }

    private func finished(_ result: Result<URL?, Error>) {
        process = nil
        guard !closed else { clean(); return }
        do {
            guard let file = try result.get() else { throw MediaLatchError.process("预览文件生成失败。") }
            let player = AVPlayer(url: file)
            self.player = player
            player.play()
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        closed = true
        player?.pause()
        player = nil
        if let process, process.isRunning { process.terminate() } else { clean() }
    }

    private func clean() { try? FileManager.default.removeItem(at: directory) }
}
