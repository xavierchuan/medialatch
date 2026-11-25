import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 220)

            Divider()

            VStack(spacing: 0) {
                LinkBar(model: model)

                Divider()

                DownloadWorkspace(model: model)
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            if model.showsInspector {
                Divider()
                SettingsInspector(model: model)
                    .frame(width: 294)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .animation(.snappy(duration: 0.24), value: model.showsInspector)
        .tint(.blue)
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.blue.gradient)
                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MediaLatch")
                        .font(.system(size: 15, weight: .semibold))
                    Text("媒体下载器")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 17)
            .padding(.bottom, 24)

            Text("下载")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 7)

            ForEach(SidebarFilter.allCases) { filter in
                Button {
                    model.selectedFilter = filter
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: filter.symbol)
                            .frame(width: 18)
                        Text(filter.label)
                        Spacer()
                        if filter == .active, model.activeCount > 0 {
                            Text("\(model.activeCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.14), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.system(size: 13, weight: model.selectedFilter == filter ? .semibold : .regular))
                    .contentShape(Rectangle())
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background {
                        if model.selectedFilter == filter {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.primary.opacity(0.075))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("仅下载你有权保存的内容", systemImage: "lock.shield")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("公开链接 · 本地处理")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }
}

private struct LinkBar: View {
    @ObservedObject var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("粘贴链接或整段分享文案", text: $model.sourceURL)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(model.analyze)

                if !model.sourceURL.isEmpty {
                    Button {
                        model.sourceURL = ""
                        model.media = nil
                        model.analysisMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isFocused ? Color.blue.opacity(0.75) : .primary.opacity(0.07), lineWidth: 1)
            }

            Button {
                model.pasteAndAnalyze()
            } label: {
                Label("粘贴并解析", systemImage: "doc.on.clipboard")
                    .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isAnalyzing)

            Button {
                model.showsInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(model.showsInspector ? "隐藏下载设置" : "显示下载设置")
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .background(.bar)
        .overlay(alignment: .bottom) {
            if model.isAnalyzing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.isAnalyzing)
    }
}

private struct DownloadWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var webRequest: WebResolverLink?

    var body: some View {
        VStack(spacing: 0) {
            if let media = model.media {
                MediaPreview(media: media, directory: model.outputDirectory) { model.enqueue(useBackup: true) }
                    .id(media.sourceURL)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let message = model.analysisMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 12))
                        .lineLimit(2)
                    Spacer()
                    if let link = model.webFallbackURL, link.source.absoluteString == model.sourceURL {
                        Button("用网页解析") { webRequest = link }
                            .help("将此链接发送给 dyxhsdownloader.com")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(.orange.opacity(0.08))
                .transition(.opacity)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedFilter.label)
                        .font(.system(size: 22, weight: .bold))
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.downloads.contains(where: { $0.status == .completed || $0.status == .cancelled }) {
                    Button("清理记录", action: model.clearCompleted)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, model.media == nil ? 25 : 19)
            .padding(.bottom, 14)

            if model.filteredDownloads.isEmpty {
                EmptyDownloadsView(hasParsedMedia: model.media != nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredDownloads) { item in
                            DownloadRow(
                                item: item,
                                onCancel: { model.cancel(item.id) },
                                onRetry: { model.retry(item.id) },
                                onReveal: { model.reveal(item) }
                            )
                            Divider()
                                .padding(.leading, 92)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: model.media)
        .sheet(item: $webRequest) { link in
            WebResolverView(link: link, directory: model.outputDirectory)
        }
    }

    private var summaryText: String {
        let count = model.filteredDownloads.count
        if count == 0 { return "下载任务会显示在这里" }
        return "\(count) 个任务 · \(model.activeCount) 个正在进行"
    }
}

private struct EmptyDownloadsView: View {
    let hasParsedMedia: Bool

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.09))
                Image(systemName: hasParsedMedia ? "arrow.right" : "arrow.down.to.line.compact")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 62, height: 62)

            Text(hasParsedMedia ? "选择右侧设置，然后开始下载" : "粘贴链接或分享文案开始")
                .font(.system(size: 15, weight: .semibold))
            Text(hasParsedMedia ? "视频与音频会保存到你选择的文件夹" : "支持公开视频、直播回放与单个媒体链接")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 44)
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: item.media.thumbnailURL.flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .frame(width: 60, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.media.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(item.status.label, systemImage: item.status.symbol)
                        .foregroundStyle(statusColor)
                    Text("·")
                    Text(item.detailText)
                    if case .failed(let message) = item.status {
                        Text("· \(message)")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

                if item.status == .processing {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                } else if item.status == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }

            Spacer()

            actionButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.status {
        case .queued, .downloading, .processing:
            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("取消")
        case .failed, .cancelled:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重试")
        case .completed:
            Button(action: onReveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在访达中显示")
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        default: .blue
        }
    }
}

private struct SettingsInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("下载设置")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    model.showsInspector = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    inspectorSection("类型") {
                        Picker("类型", selection: $model.kind) {
                            ForEach(MediaKind.allCases) { kind in
                                Label(kind.label, systemImage: kind.symbol).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    inspectorSection("格式") {
                        Picker("格式", selection: $model.format) {
                            ForEach(model.availableFormats, id: \.self) { format in
                                Text(format.uppercased()).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if model.kind == .video {
                        inspectorSection("画质") {
                            Picker("画质", selection: $model.videoHeight) {
                                Text("最佳可用质量").tag(0)
                                ForEach(model.videoHeights, id: \.self) { height in
                                    Text("\(height)p").tag(height)
                                }
                            }
                            .labelsHidden()
                        }
                    } else {
                        inspectorSection("音质") {
                            Picker("音质", selection: $model.audioQuality) {
                                ForEach(model.audioQualityOptions, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    inspectorSection("保存到") {
                        Button(action: model.chooseOutputDirectory) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.outputDirectory.lastPathComponent)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(model.outputDirectory.deletingLastPathComponent().path)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }

            Divider()

            VStack(spacing: 10) {
                Button(action: model.addDownload) {
                    Label(model.kind == .audio ? "下载音频" : "下载视频", systemImage: "arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.media == nil || model.media?.isGallery == true)

                if model.media?.isGallery == true {
                    Text("在解析卡中下载图集")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else if model.media == nil {
                    Text("解析链接后即可下载")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
