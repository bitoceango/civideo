import SwiftUI

// 底部模块：首页 / 分类 / 听书 / 我的（听书=需求 004；其余=001 三大模块）
struct RootTabView: View {
    @EnvironmentObject var audio: AudioController
    @State private var tab: Int = {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "cv.debugTab")  // 测试用：指定初始 Tab
        #else
        return 0
        #endif
    }()

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            CategoryView()
                .tabItem { Label("分类", systemImage: "square.grid.2x2.fill") }.tag(1)
            ListenTabView()
                .tabItem { Label("听书", systemImage: "headphones") }.tag(2)
            MineView()
                .tabItem { Label("我的", systemImage: "person.fill") }.tag(3)
        }
        .tint(Theme.accent)
        // 听书在播时，迷你条跨 Tab 常驻（贴在 Tab 栏之上）
        .safeAreaInset(edge: .bottom) {
            if audio.book != nil { MiniPlayerBar() }
        }
    }
}

// 迷你播放条：听书在播时常驻，点开 = 全屏播放器（收起≠停播）
struct MiniPlayerBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var audio: AudioController

    var body: some View {
        if let book = audio.book, let ch = audio.chapter {
            Button { audio.isExpanded = true } label: {
                ZStack(alignment: .bottom) {
                    HStack(spacing: 11) {
                        RemoteImage(url: model.api.mediaURL(book.coverUrl ?? ""), headers: model.api.authHeaders) {
                            LinearGradient.poster(seed: book.id)
                        }
                        .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(book.title) · \(ch.title)").font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(Theme.text).lineLimit(1)
                            Text("🎧 听书中").font(.system(size: 11)).foregroundStyle(Theme.faint)
                        }
                        Spacer(minLength: 6)
                        Button { audio.prev() } label: { mc("backward.end.fill") }
                            .buttonStyle(.plain).disabled(!audio.hasPrev).opacity(audio.hasPrev ? 1 : 0.35)
                        Button { audio.toggle() } label: {
                            Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15)).foregroundStyle(Theme.onAccent)
                                .frame(width: 36, height: 36).background(Theme.accent, in: Circle())
                        }.buttonStyle(.plain)
                        Button { audio.next() } label: { mc("forward.end.fill") }
                            .buttonStyle(.plain).disabled(!audio.hasNext).opacity(audio.hasNext ? 1 : 0.35)
                    }
                    .padding(8)

                    GeometryReader { geo in
                        Rectangle().fill(Theme.accentHi)
                            .frame(width: geo.size.width * audio.progressFraction, height: 2)
                    }
                    .frame(height: 2)
                }
                .background(Theme.cardHi)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 10).padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func mc(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.text)
            .frame(width: 34, height: 34)
    }
}
