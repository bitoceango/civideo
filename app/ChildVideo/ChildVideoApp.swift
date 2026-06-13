import SwiftUI

@main
struct ChildVideoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.audio)
                .task { await model.bootstrap() }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var audio: AudioController

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.route {
            case .loading:
                ProgressView().tint(Theme.accent)
            case .activation:
                ActivationView()
            case .library:
                MainTabShell()
            case .player(let video):
                PlayerView(video: video)
                    .transition(.opacity)
            case .parent:
                ParentView()
                    .transition(.opacity)
            case .blocked(let reason):
                BreakView(reason: reason)
                    .transition(.opacity)
            }

            // 全局全屏听书播放器：仅在主壳态展开时覆盖（收起≠停播）
            if case .library = model.route, audio.isExpanded {
                AudioPlayerView()
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.route)
        .animation(.easeInOut(duration: 0.3), value: audio.isExpanded)
    }
}

// 时间格式化
func clockString(_ sec: Int) -> String {
    let m = sec / 60, s = sec % 60
    return String(format: "%d:%02d", m, s)
}
func runtimeString(_ sec: Int) -> String { "\(Int((Double(sec) / 60).rounded())) 分钟" }
