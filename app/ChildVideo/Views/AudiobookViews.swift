import SwiftUI

// MARK: - 听书详情（章节列表）—— 在「听书」Tab 的 NavigationStack 内 push
struct AudiobookDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    let book: Audiobook

    private var resumeChapter: Chapter? { model.lastChapter(of: book) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                header
                Text("章节").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 26).padding(.top, 18).padding(.bottom, 6)
                ForEach(book.chapters) { ch in chapterRow(ch) }
                Color.clear.frame(height: 30)
            }
        }
        .background(Theme.bg)
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.text)
            }.buttonStyle(.plain)
            Spacer()
            Button { model.toggleFavorite(book: book) } label: {
                Image(systemName: model.isFavorite(book: book) ? "heart.fill" : "heart").font(.system(size: 19))
                    .frame(width: 44, height: 44).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(model.isFavorite(book: book) ? Color(hex: 0xFF6B8A) : Theme.muted)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 18)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            RemoteImage(url: model.api.mediaURL(book.coverUrl ?? ""), headers: model.api.authHeaders) {
                LinearGradient.poster(seed: book.id)
            }
            .frame(width: 130, height: 130 * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text).lineLimit(3)
                if let a = book.author { Text(a).font(.system(size: 14)).foregroundStyle(Theme.muted) }
                Text("\(book.chapters.count) 章 · \(runtimeString(book.totalDurationSec))")
                    .font(.system(size: 13)).foregroundStyle(Theme.faint)
                if let c = book.category {
                    Text(c).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.card, in: Capsule()).foregroundStyle(Theme.accentHi)
                }
                Spacer(minLength: 0)
                Button { playResumeOrFirst() } label: {
                    Label(resumeChapter == nil ? "开始收听" : "继续收听", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.onAccent)
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 12)
    }

    private func playResumeOrFirst() {
        if let ch = resumeChapter ?? book.chapters.first { audio.play(book: book, chapter: ch) }
    }

    private func chapterRow(_ ch: Chapter) -> some View {
        let pos = model.position(of: book, chapter: ch)
        let isCurrent = audio.book?.id == book.id && audio.chapter?.idx == ch.idx
        let started = pos > 5 && pos < ch.durationSec - 5
        let done = ch.durationSec > 0 && pos >= ch.durationSec - 5
        return Button { audio.play(book: book, chapter: ch) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.card).frame(width: 38, height: 38)
                    if done { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.good) }
                    else { Text("\(ch.idx)").font(.system(size: 14, weight: .bold)).foregroundStyle(isCurrent || started ? Theme.accentHi : Theme.muted) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(ch.title).font(.system(size: 15, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? Theme.accentHi : Theme.text).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(runtimeString(ch.durationSec)).font(.system(size: 12)).foregroundStyle(Theme.faint)
                        if started { Text("· 听到 \(clockString(pos))").font(.system(size: 12)).foregroundStyle(Theme.accentHi) }
                    }
                }
                Spacer()
                Image(systemName: isCurrent && audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(Theme.accent.opacity(0.85))
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(isCurrent ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 14)
    }
}

// MARK: - 全屏听书播放器 —— 读全局 AudioController；下滑=收起到迷你条（不停播）
struct AudioPlayerView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var audio: AudioController
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var displayCurrent: Double { scrubbing ? scrubValue : audio.current }
    private let sleepOptions: [(String, Int)] = [("15 分钟", 15), ("30 分钟", 30), ("60 分钟", 60)]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let book = audio.book, let ch = audio.chapter {
                VStack(spacing: 0) {
                    topBar(book)
                    Spacer()
                    cover(book)
                    titles(book, ch)
                    Spacer()
                    scrubber
                    transport
                    sleepControl
                    Spacer().frame(height: 22)
                }
                .padding(.horizontal, 30)
            }
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    private func topBar(_ book: Audiobook) -> some View {
        HStack {
            Button { audio.isExpanded = false } label: {
                Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.text)
            }.buttonStyle(.plain)
            Spacer()
            Text(book.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer()
            AirPlayButton().frame(width: 44, height: 44)
        }
        .padding(.top, 18)
    }

    private func cover(_ book: Audiobook) -> some View {
        RemoteImage(url: model.api.mediaURL(book.coverUrl ?? ""), headers: model.api.authHeaders) {
            ZStack { LinearGradient.poster(seed: book.id); Image(systemName: "headphones").font(.system(size: 56)).foregroundStyle(.white.opacity(0.85)) }
        }
        .frame(width: 256, height: 256).clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.5), radius: 26, y: 14).padding(.bottom, 26)
    }

    private func titles(_ book: Audiobook, _ ch: Chapter) -> some View {
        VStack(spacing: 6) {
            Text(ch.title).font(.system(size: 21, weight: .bold)).foregroundStyle(Theme.text)
                .lineLimit(2).multilineTextAlignment(.center)
            Text("第 \(ch.idx) 章 / 共 \(book.chapters.count) 章 · \(book.title)")
                .font(.system(size: 13.5)).foregroundStyle(Theme.faint).lineLimit(1)
        }.padding(.horizontal, 10)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let dur = max(1, audio.duration)
                let progX = w * CGFloat(min(1, displayCurrent / dur))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line).frame(height: 6)
                    Capsule().fill(Theme.accentHi).frame(width: progX, height: 6)
                    Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 3).offset(x: progX - 8)
                }
                .frame(height: 22).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in scrubbing = true; scrubValue = Double(max(0, min(1, g.location.x / w))) * dur }
                    .onEnded { _ in audio.seek(scrubValue); scrubbing = false })
            }
            .frame(height: 22)
            HStack {
                Text(clockString(Int(displayCurrent))).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.muted)
                Spacer()
                Text(clockString(Int(max(0, audio.duration)))).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }.padding(.bottom, 16)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            tBtn("backward.end.fill", 26, enabled: audio.hasPrev) { audio.prev() }
            tBtn("gobackward.15", 30) { audio.skip(-15) }
            Button { audio.toggle() } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium)).foregroundStyle(Theme.onAccent)
                    .frame(width: 80, height: 80).background(Theme.accent, in: Circle())
            }.buttonStyle(.plain)
            tBtn("goforward.15", 30) { audio.skip(15) }
            tBtn("forward.end.fill", 26, enabled: audio.hasNext) { audio.next() }
        }.padding(.bottom, 14)
    }

    private func tBtn(_ icon: String, _ size: CGFloat, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .medium))
                .foregroundStyle(enabled ? Theme.text : Theme.faint.opacity(0.4)).frame(width: 52, height: 52)
        }.buttonStyle(.plain).disabled(!enabled)
    }

    private var sleepControl: some View {
        Menu {
            ForEach(sleepOptions, id: \.1) { label, min in
                Button(label) { audio.setSleep(minutes: min) }
            }
            Button("本章结束后") { audio.setSleepEndOfChapter() }
            if audio.sleepRemainingSec != nil || audio.sleepEndOfChapter {
                Button("关闭定时", role: .destructive) { audio.stopSleep() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                Text(sleepLabel).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(audio.sleepRemainingSec != nil || audio.sleepEndOfChapter ? Theme.accentHi : Theme.muted)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var sleepLabel: String {
        if let r = audio.sleepRemainingSec { return "睡眠定时 · 剩 \(clockString(r))" }
        if audio.sleepEndOfChapter { return "睡眠定时 · 本章结束" }
        return "睡眠定时"
    }
}
