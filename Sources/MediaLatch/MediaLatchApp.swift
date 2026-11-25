import SwiftUI

@main
struct MediaLatchApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .defaultSize(width: 1_160, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("粘贴链接并解析") {
                    model.pasteAndAnalyze()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("选择下载位置…") {
                    model.chooseOutputDirectory()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
