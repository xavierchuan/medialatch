import Foundation

enum MediaKind: String, CaseIterable, Identifiable {
    case video
    case audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .video: "视频"
        case .audio: "音频"
        }
    }

    var symbol: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        }
    }
}

struct MediaInfo: Identifiable, Equatable {
    let id: String
    let sourceURL: String
    let title: String
    let creator: String
    let thumbnailURL: String?
    let duration: TimeInterval
    let availableHeights: [Int]

    var descriptionText = ""
    var backupInfo: Data?
    var downloadInfo: Data?
    var parsedAt = Date()
    var gallery: [URL] = []

    var isGallery: Bool { !gallery.isEmpty }

    var copyText: String {
        descriptionText.isEmpty || descriptionText == title ? title : title + "\n\n" + descriptionText
    }

    var durationText: String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var bestQualityText: String {
        guard let height = availableHeights.first else { return "自动" }
        return "\(height)p"
    }
}

struct DownloadRequest: Equatable {
    let kind: MediaKind
    let format: String
    let videoHeight: Int
    let audioQuality: String
    let outputDirectory: URL
    var useBackup = false
}

enum DownloadStatus: Equatable {
    case queued
    case downloading
    case processing
    case completed
    case cancelled
    case failed(String)

    var label: String {
        switch self {
        case .queued: "等待中"
        case .downloading: "下载中"
        case .processing: "正在处理"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .failed: "失败"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .downloading: "arrow.down.circle.fill"
        case .processing: "wand.and.stars"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    let media: MediaInfo
    let request: DownloadRequest
    var status: DownloadStatus
    var progress: Double
    var outputURL: URL?
    var createdAt: Date

    var detailText: String {
        let type = request.kind == .audio ? request.audioQuality : (request.videoHeight == 0 ? "最佳质量" : "\(request.videoHeight)p")
        return "\(request.format.uppercased()) · \(type)"
    }
}

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部下载"
        case .active: "进行中"
        case .completed: "已完成"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .active: "arrow.down.circle"
        case .completed: "checkmark.circle"
        }
    }
}

enum MediaLatchError: LocalizedError {
    case invalidURL
    case dependency(String)
    case process(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "分享文案里没有找到 HTTP 或 HTTPS 链接。"
        case .dependency(let message):
            message
        case .process(let message):
            message
        case .invalidResponse:
            "没有读到可下载的媒体信息，请检查链接后重试。"
        }
    }
}
