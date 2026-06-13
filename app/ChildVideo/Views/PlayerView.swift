import SwiftUI
import AVFoundation
import Combine

@MainActor
final class PlayerEngine: ObservableObject {
    let player = AVPlayer()
    @Published var current: Double = 0      // 当前秒
    @Published var duration: Double = 0
    @Published var buffered: Double = 0
    @Published var isPlaying = false
    @Published var ended = false
    @Published var rate: Float = 1
    @Published var volume: Float = 1 { didSet { player.volume = volume } }
    @Published var muted = false { didSet { player.isMuted = muted } }
    @Published var subtitleOn = false
    @Published var hasSubtitles = false

    private var subtitleGroup: AVMediaSelectionGroup?
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var meta: (title: String, series: String?) = ("", nil)
    var onReachEnd: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?

    func load(url: URL, headers: [String: String], startAt: Double, title: String, series: String?) {
        meta = (title, series)
        let item = makeAuthedPlayerItem(url: url, headers: headers)
        player.replaceCurrentItem(with: item)
        player.volume = volume
        player.isMuted = muted
        ended = false

        statusCancellable = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .failed {
                    print("[Player] item failed:", item.error?.localizedDescription ?? "unknown")
                    return
                }
                guard status == .readyToPlay else { return }
                self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                if startAt > 1 { self.seek(to: startAt) }
                self.play()
                self.loadSubtitles(item)
            }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            self.current = t.seconds
            if let ranges = self.player.currentItem?.loadedTimeRanges,
               let r = ranges.first?.timeRangeValue {
                self.buffered = (r.start.seconds + r.duration.seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.ended = true
                self.updateNowPlaying()
                self.onReachEnd?()
            }
        }

        NowPlaying.activateAudioSession()
        NowPlaying.setupCommands(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            skip: { [weak self] d in self?.skip(d) },
            seek: { [weak self] s in self?.seek(to: s) },
            next: { [weak self] in self?.onNext?() },
            prev: { [weak self] in self?.onPrev?() })
    }

    private func loadSubtitles(_ item: AVPlayerItem) {
        Task { [weak self] in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            await MainActor.run {
                self?.subtitleGroup = group
                self?.hasSubtitles = !group.options.isEmpty
            }
        }
    }

    func toggleSubtitles() {
        guard let group = subtitleGroup, let item = player.currentItem else { return }
        if subtitleOn {
            item.select(nil, in: group)
            subtitleOn = false
        } else if let opt = group.options.first {
            item.select(opt, in: group)
            subtitleOn = true
        }
    }

    func play() { player.rate = rate; isPlaying = true; ended = false; updateNowPlaying() }
    func pause() { player.pause(); isPlaying = false; updateNowPlaying() }
    func togglePlay() { isPlaying ? pause() : play() }
    func replay() { seek(to: 0); play() }
    func setRate(_ r: Float) { rate = r; if isPlaying { player.rate = r }; updateNowPlaying() }
    func toggleMute() { muted.toggle() }
    func seek(to sec: Double) {
        let clamped = max(0, min(sec, duration > 0 ? duration : sec))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        current = clamped
        updateNowPlaying()
    }
    func skip(_ delta: Double) { seek(to: current + delta) }

    private func updateNowPlaying() {
        NowPlaying.update(title: meta.title, series: meta.series,
                          duration: duration, elapsed: current, rate: isPlaying ? rate : 0)
    }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        statusCancellable?.cancel()
        NowPlaying.teardownCommands()
        NowPlaying.clear()
    }
}

struct PlayerView: View {
    @EnvironmentObject var model: AppModel
    let video: Video

    @StateObject private var engine = PlayerEngine()
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var lastReported = 0
    @State private var heartbeat: Timer?
    @State private var showEpisodes = false
    @State private var locked = false
    @State private var showLockHint = false
    @State private var lockHintTask: Task<Void, Never>?

    private let speeds: [Float] = [0.75, 1, 1.25, 1.5]   // 儿童向克制档位，不上 2x

    private var seriesEpisodes: [Video] {
        guard let s = video.series else { return [] }
        return model.seriesGroups.first(where: { $0.id == s })?.videos ?? []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(player: engine.player).ignoresSafeArea()

            // 画面无图时的占位（item 未就绪）
            if engine.duration == 0 {
                VStack(spacing: 8) {
                    ProgressView().tint(.white.opacity(0.6))
                    Text("加载中…").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                }
            }

            if locked {
                lockedOverlay
            } else {
                controlsOverlay.opacity(showControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: showControls)

                if nearEnd, let next = model.nextEpisode(after: video) {
                    nextCard(next).transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
        .contentShape(Rectangle())
        .onTapGesture { locked ? flashLockHint() : poke() }
        .onAppear { start() }
        .onDisappear { stop() }
        .sheet(isPresented: $showEpisodes) { episodeListSheet }
    }

    // 防误触锁定层：长按解锁，避免孩子误触退出/拖动
    private var lockedOverlay: some View {
        ZStack {
            if showLockHint {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                    Text("已锁定").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("长按下面的按钮解锁").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "lock.open.fill").font(.system(size: 22)).foregroundStyle(Theme.onAccent)
                        .frame(width: 70, height: 70).background(Theme.accent, in: Circle())
                        .onLongPressGesture(minimumDuration: 0.6) {
                            locked = false; showLockHint = false; poke()
                        }
                }
                .padding(28)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLockHint)
    }

    private func flashLockHint() {
        showLockHint = true
        lockHintTask?.cancel()
        lockHintTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showLockHint = false
        }
    }

    // 选集面板
    private var episodeListSheet: some View {
        let eps = seriesEpisodes
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(video.series ?? "选集").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                Button { showEpisodes = false } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 36).background(Theme.card, in: Circle())
                }.buttonStyle(.plain)
            }
            .padding(20)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(eps.enumerated()), id: \.element.id) { idx, ep in
                        Button {
                            showEpisodes = false
                            if ep.id != video.id { go(to: ep) }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RemoteImage(url: model.api.mediaURL(ep.posterUrl), headers: model.api.authHeaders) {
                                        LinearGradient.poster(seed: ep.series ?? ep.id)
                                    }
                                    .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                                    if ep.id == video.id {
                                        Image(systemName: "play.fill").foregroundStyle(.white)
                                            .frame(width: 96, height: 60).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("第 \(idx + 1) 集").font(.system(size: 12)).foregroundStyle(Theme.faint)
                                    Text(ep.title).font(.system(size: 15, weight: ep.id == video.id ? .bold : .medium))
                                        .foregroundStyle(ep.id == video.id ? Theme.accentHi : Theme.text).lineLimit(1)
                                    Text(runtimeString(ep.durationSec)).font(.system(size: 12)).foregroundStyle(Theme.faint)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(ep.id == video.id ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(Theme.bg)
    }

    // MARK: 控件层

    private var controlsOverlay: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { stop(); model.route = .library } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                if let s = video.series {
                    Text(s + episodeSuffix).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Button { locked = true; showControls = false; flashLockHint() } label: {
                Image(systemName: "lock.open").font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
            Button { model.toggleFavorite(video); poke() } label: {
                Image(systemName: model.isFavorite(video) ? "heart.fill" : "heart")
                    .font(.system(size: 19))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(model.isFavorite(video) ? Color(hex: 0xFF6B8A) : .white)
            }.buttonStyle(.plain)
        }
    }

    private var centerControls: some View {
        HStack(spacing: 60) {
            if engine.ended {
                circleButton("arrow.counterclockwise", size: 84) { engine.replay(); poke() }
            } else {
                circleButton("gobackward.10", size: 60) { engine.skip(-10); poke() }
                circleButton(engine.isPlaying ? "pause.fill" : "play.fill", size: 84) {
                    engine.togglePlay(); poke()
                }
                circleButton("goforward.10", size: 60) { engine.skip(10); poke() }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            // 进度条
            HStack(spacing: 14) {
                Text(clockString(Int(displayCurrent))).font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85)).frame(width: 46, alignment: .leading)
                scrubber
                Text("-" + clockString(Int(max(0, engine.duration - displayCurrent))))
                    .font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85)).frame(width: 50, alignment: .trailing)
            }
            // 工具行
            HStack(spacing: 12) {
                // 倍速菜单
                Menu {
                    ForEach(speeds, id: \.self) { s in
                        Button { engine.setRate(s); poke() } label: {
                            if engine.rate == s { Label(speedLabel(s), systemImage: "checkmark") }
                            else { Text(speedLabel(s)) }
                        }
                    }
                } label: {
                    toolChip(icon: "speedometer", text: speedLabel(engine.rate), active: engine.rate != 1)
                }
                .menuStyle(.borderlessButton).fixedSize()

                // 字幕 CC（视频内嵌字幕时出现）
                if engine.hasSubtitles {
                    toolButton(icon: engine.subtitleOn ? "captions.bubble.fill" : "captions.bubble",
                               active: engine.subtitleOn) { engine.toggleSubtitles(); poke() }
                }

                Spacer()

                // 静音 + 音量
                toolButton(icon: (engine.muted || engine.volume == 0) ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    engine.toggleMute(); poke()
                }
                Slider(value: $engine.volume, in: 0...1) { editing in if editing { poke(persist: true) } else { poke() } }
                    .frame(width: 92).tint(Theme.accentHi)

                // AirPlay 投屏
                AirPlayButton().frame(width: 40, height: 40)

                // 选集
                if seriesEpisodes.count > 1 {
                    toolButton(icon: "list.bullet") { showEpisodes = true; poke(persist: true) }
                }

                // 下一集
                if let next = model.nextEpisode(after: video) {
                    Button { go(to: next) } label: {
                        Label("下一集", systemImage: "forward.end.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18), lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.9))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func toolButton(icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(active ? Theme.accent : .white.opacity(0.001))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(active ? 0 : 0.18), lineWidth: 1))
                .foregroundStyle(active ? Theme.onAccent : .white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func toolChip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14))
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(active ? Theme.accent : .white.opacity(0.001))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(active ? 0 : 0.18), lineWidth: 1))
        .foregroundStyle(active ? Theme.onAccent : .white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var scrubber: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(1, engine.duration)
            let progX = w * CGFloat(displayCurrent / dur)
            let bufX = w * CGFloat(min(1, engine.buffered / dur))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: 6)
                Capsule().fill(.white.opacity(0.32)).frame(width: bufX, height: 6)
                Capsule().fill(Theme.accentHi).frame(width: progX, height: 6)
                Circle().fill(.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .offset(x: progX - 8)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        scrubbing = true
                        scrubValue = Double(max(0, min(1, g.location.x / w))) * dur
                        poke(persist: true)
                    }
                    .onEnded { _ in
                        engine.seek(to: scrubValue)
                        scrubbing = false
                        poke()
                    }
            )
        }
        .frame(height: 22)
    }

    private func nextCard(_ next: Video) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    RemoteImage(url: model.api.mediaURL(next.posterUrl), headers: model.api.authHeaders) {
                        LinearGradient.poster(seed: next.series ?? next.id)
                    }
                    .frame(width: 92, height: 58).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("即将播放 · 同系列").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.accentHi)
                        Text(next.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Button { go(to: next) } label: {
                            Label("立即播放", systemImage: "play.fill").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accentHi)
                        }.buttonStyle(.plain).padding(.top, 2)
                    }
                    .frame(width: 150, alignment: .leading)
                }
                .padding(14)
                .background(Color(hex: 0x16181C).opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            }
            .padding(.trailing, 26).padding(.bottom, 96)
        }
    }

    // MARK: 辅助

    private func circleButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    private var displayCurrent: Double { scrubbing ? scrubValue : engine.current }
    private var nearEnd: Bool { engine.duration > 0 && engine.duration - engine.current < 40 }
    private var episodeSuffix: String {
        guard let series = video.series,
              let group = model.seriesGroups.first(where: { $0.id == series }),
              let idx = group.videos.firstIndex(of: video) else { return "" }
        return " · 第 \(idx + 1) 集"
    }
    private func speedLabel(_ s: Float) -> String {
        (s == s.rounded() ? String(format: "%.0f", s) : String(format: "%g", s)) + "×"
    }

    // MARK: 生命周期

    private func start() {
        guard let url = model.api.mediaURL(video.videoUrl) else { return }
        engine.onReachEnd = { autoNext() }
        engine.onNext = { if let n = model.nextEpisode(after: video) { go(to: n) } }
        engine.onPrev = { if let p = model.prevEpisode(before: video) { go(to: p) } else { engine.seek(to: 0) } }
        engine.load(url: url, headers: model.api.authHeaders,
                    startAt: Double(model.position(of: video)),
                    title: video.title, series: video.series)
        lastReported = model.position(of: video)
        poke()
        // 心跳：每 10 秒上报进度 + 当日时长，并接收拦截信号
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in await reportTick() }
        }
    }

    private func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        hideTask?.cancel()
        Task { await reportTick(force: true) }   // 离开时补一次
        engine.teardown()
    }

    private func reportTick(force: Bool = false) async {
        let pos = Int(engine.current)
        let delta = max(0, pos - lastReported)
        // 仅在真正播放推进时累加时长
        let effectiveDelta = engine.isPlaying ? delta : 0
        lastReported = pos
        if let reason = await model.reportProgress(video: video, positionSec: pos, deltaSec: effectiveDelta) {
            engine.pause()
            stopHeartbeatOnly()
            model.route = .blocked(reason)
        }
    }

    private func stopHeartbeatOnly() { heartbeat?.invalidate(); heartbeat = nil }

    private func autoNext() {
        Task { await reportTick(force: true) }
        if let next = model.nextEpisode(after: video) {
            go(to: next)
        } else {
            // 最后一集：停在结束态，显示重播按钮（不直接退回库）
            stopHeartbeatOnly()
            poke(persist: true)
        }
    }

    private func go(to next: Video) {
        stop()
        model.route = .player(next)
    }

    private func poke(persist: Bool = false) {
        showControls = true
        hideTask?.cancel()
        guard !persist else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if engine.isPlaying && !scrubbing { showControls = false }
        }
    }
}
