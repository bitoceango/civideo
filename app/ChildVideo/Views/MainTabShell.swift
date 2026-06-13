import SwiftUI

enum MainTab { case home, listen }   // 内容 Tab；「我的」走全屏 route，「分类」由 001 接入

// 主壳：底部 Tab（首页/听书/我的）+ 常驻迷你播放条。
struct MainTabShell: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var audio: AudioController
    @State private var tab: MainTab = .home

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tab {
                case .home:   LibraryView()
                case .listen: ListenTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if audio.book != nil {
                MiniPlayerBar()
            }
            TabBar(tab: $tab)
        }
        .background(Theme.bg)
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "cv.debugListen") { tab = .listen } }
        #endif
    }
}

private struct TabBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var tab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "house.fill", "首页")
            item(.listen, "headphones", "听书")
            // 「分类」由 001 接入：首页/分类/听书/我的
            Button { model.route = .parent } label: {
                tabLabel("person.fill", "我的", active: false)
            }.buttonStyle(.plain)
        }
        .padding(.top, 6)
        .background(Theme.bg2)
        .overlay(Divider().background(Theme.line), alignment: .top)
    }

    private func item(_ t: MainTab, _ icon: String, _ title: String) -> some View {
        Button { tab = t } label: { tabLabel(icon, title, active: tab == t) }
            .buttonStyle(.plain)
    }

    private func tabLabel(_ icon: String, _ title: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 19))
            Text(title).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(active ? Theme.accentHi : Theme.faint)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
    }
}

// 迷你播放条：听书在播时常驻（Tab 之上），点开 = 全屏播放器。
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
                .padding(.horizontal, 10).padding(.bottom, 8)
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
