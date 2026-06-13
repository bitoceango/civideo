import SwiftUI

@main
struct ChildVideoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
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

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.route {
            case .loading:
                ProgressView().tint(Theme.accent)
            case .activation:
                ActivationView()
            case .library:
                RootTabView()
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
        }
        .animation(.easeInOut(duration: 0.25), value: model.route)
    }
}

// 时间格式化
func clockString(_ sec: Int) -> String {
    let m = sec / 60, s = sec % 60
    return String(format: "%d:%02d", m, s)
}
func runtimeString(_ sec: Int) -> String { "\(Int((Double(sec) / 60).rounded())) 分钟" }
