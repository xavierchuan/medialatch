import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceURL = ""
    @Published var media: MediaInfo?
    @Published var isAnalyzing = false
    @Published var webFallbackURL: WebResolverLink?
    @Published var analysisMessage: String?
    @Published var kind: MediaKind = .video {
        didSet {
            format = kind == .video ? "mp4" : "m4a"
        }
    }
    @Published var format = "mp4" {
        didSet {
            guard kind == .audio else { return }
            switch format {
            case "mp3":
                if audioQuality == "原始质量" { audioQuality = "320kbps" }
            case "wav", "flac":
                audioQuality = "原始质量"
            case "m4a":
                if audioQuality == "320kbps" { audioQuality = "原始质量" }
            default:
                break
            }
        }
    }
    @Published var videoHeight = 0
    @Published var audioQuality = "原始质量"
    @Published var outputDirectory: URL
    @Published var downloads: [DownloadItem] = []
    @Published var selectedFilter: SidebarFilter = .all
    @Published var showsInspector = true
    @Published var dependencyMessage: String?

    private let service = YTDLPService()
    private var activeProcesses: [UUID: Process] = [:]

    init() {
        outputDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var availableFormats: [String] {
        kind == .video ? ["mp4", "mkv"] : ["m4a", "mp3", "wav", "flac"]
    }

    var audioQualityOptions: [String] {
        switch format {
        case "mp3":
            ["320kbps", "256kbps", "192kbps", "128kbps"]
        case "wav", "flac":
            ["原始质量"]
        default:
            ["原始质量", "256kbps", "192kbps", "128kbps"]
        }
    }

    var videoHeights: [Int] {
        media?.availableHeights ?? []
    }

    var filteredDownloads: [DownloadItem] {
        downloads.filter { item in
            switch selectedFilter {
            case .all:
                true
            case .active:
                [.queued, .downloading, .processing].contains(item.status)
            case .completed:
                item.status == .completed
            }
        }
    }

    var activeCount: Int {
        downloads.filter { [.queued, .downloading, .processing].contains($0.status) }.count
    }

    func pasteAndAnalyze() {
        if let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty {
            sourceURL = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        analyze()
    }

    func analyze() {
        guard !isAnalyzing else { return }
        media = nil
        webFallbackURL = nil
        guard let value = ShareLink.extract(from: sourceURL) else {
            analysisMessage = MediaLatchError.invalidURL.localizedDescription
            return
        }

        sourceURL = value
        isAnalyzing = true
        analysisMessage = nil

        Task {
            do {
                let result = try await service.analyze(value)
                media = result
                videoHeight = 0
                showsInspector = true
            } catch {
                analysisMessage = error.localizedDescription
                webFallbackURL = URL(string: value).flatMap(WebResolverLink.init)
            }
            isAnalyzing = false
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择下载位置"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    func addDownload() { enqueue(useBackup: false) }

    func enqueue(useBackup: Bool) {
        guard let media, !media.isGallery else { return }
        let request = DownloadRequest(
            kind: kind,
            format: format,
            videoHeight: videoHeight,
            audioQuality: audioQuality,
            outputDirectory: outputDirectory,
            useBackup: useBackup
        )
        let item = DownloadItem(
            id: UUID(),
            media: media,
            request: request,
            status: .queued,
            progress: 0,
            outputURL: nil,
            createdAt: Date()
        )
        downloads.insert(item, at: 0)
        start(itemID: item.id, media: media, request: request)
    }

    func cancel(_ id: UUID) {
        update(id) { item in
            item.status = .cancelled
        }
        activeProcesses[id]?.terminate()
        activeProcesses[id] = nil
    }

    func retry(_ id: UUID) {
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        update(id) { current in
            current.status = .queued
            current.progress = 0
            current.outputURL = nil
        }
        start(itemID: id, media: item.media, request: item.request, reuseAnalysis: false)
    }

    func reveal(_ item: DownloadItem) {
        if let outputURL = item.outputURL {
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } else {
            NSWorkspace.shared.open(item.request.outputDirectory)
        }
    }

    func clearCompleted() {
        downloads.removeAll { $0.status == .completed || $0.status == .cancelled }
    }

    private func start(itemID: UUID, media: MediaInfo, request: DownloadRequest, reuseAnalysis: Bool = true) {
        Task {
            do {
                try await service.prepare()
                guard let current = downloads.first(where: { $0.id == itemID }), current.status != .cancelled else {
                    return
                }
                update(itemID) { $0.status = .downloading }

                let process = try await service.startDownload(
                    media: media,
                    request: request,
                    reuseAnalysis: reuseAnalysis,
                    eventHandler: { [weak self] event in
                        Task { @MainActor in
                            self?.handle(event, for: itemID)
                        }
                    },
                    completion: { [weak self] result in
                        Task { @MainActor in
                            self?.finish(result, for: itemID)
                        }
                    }
                )
                if downloads.first(where: { $0.id == itemID })?.status == .cancelled {
                    process.terminate()
                } else {
                    activeProcesses[itemID] = process
                }
            } catch {
                if downloads.first(where: { $0.id == itemID })?.status != .cancelled {
                    update(itemID) { $0.status = .failed(error.localizedDescription) }
                }
            }
        }
    }

    private func handle(_ event: YTDLPService.Event, for id: UUID) {
        switch event {
        case .progress(let value):
            update(id) { item in
                item.progress = value
                item.status = value >= 0.999 ? .processing : .downloading
            }
        case .processing:
            update(id) { $0.status = .processing }
        case .file(let url):
            update(id) { $0.outputURL = url }
        case .log:
            break
        }
    }

    private func finish(_ result: Result<URL?, Error>, for id: UUID) {
        activeProcesses[id] = nil
        guard let current = downloads.first(where: { $0.id == id }), current.status != .cancelled else { return }

        switch result {
        case .success(let url):
            update(id) { item in
                item.status = .completed
                item.progress = 1
                if let url { item.outputURL = url }
            }
        case .failure(let error):
            update(id) { $0.status = .failed(error.localizedDescription) }
        }
    }

    private func update(_ id: UUID, mutation: (inout DownloadItem) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutation(&downloads[index])
    }
}
