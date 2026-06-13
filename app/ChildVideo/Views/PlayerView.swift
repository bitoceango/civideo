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
    @Published var rate: Float = 1

    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    var onReachEnd: (() -> Void)?

    func load(url: URL, headers: [String: String], startAt: Double) {
        let item = makeAuthedPlayerItem(url: url, headers: headers)
        player.replaceCurrentItem(with: item)

        statusCancellable = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self, status == .readyToPlay else { return }
                self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                if startAt > 1 { self.seek(to: startAt) }
                self.play()
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
            Task { @MainActor in self?.onReachEnd?() }
        }
    }

    func play() { player.rate = rate; isPlaying = true }
    func pause() { player.pause(); isPlaying = false }
    func togglePlay() { isPlaying ? pause() : play() }
    func setRate(_ r: Float) { rate = r; if isPlaying { player.rate = r } }
    func seek(to sec: Double) {
        let clamped = max(0, min(sec, duration > 0 ? duration : sec))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        current = clamped
    }
    func skip(_ delta: Double) { seek(to: current + delta) }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        statusCancellable?.cancel()
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

    private let speeds: [Float] = [1, 1.25, 1.5]

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

            controlsOverlay.opacity(showControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: showControls)

            if nearEnd, let next = model.nextEpisode(after: video) {
                nextCard(next).transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
        .contentShape(Rectangle())
        .onTapGesture { poke() }
        .onAppear { start() }
        .onDisappear { stop() }
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
        }
    }

    private var centerControls: some View {
        HStack(spacing: 60) {
            circleButton("gobackward.10", size: 60) { engine.skip(-10); poke() }
            circleButton(engine.isPlaying ? "pause.fill" : "play.fill", size: 84) {
                engine.togglePlay(); poke()
            }
            circleButton("goforward.10", size: 60) { engine.skip(10); poke() }
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
            HStack {
                HStack(spacing: 10) {
                    ForEach(speeds, id: \.self) { s in
                        Button { engine.setRate(s); poke() } label: {
                            Text(speedLabel(s)).font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(engine.rate == s ? Theme.accent : .clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(engine.rate == s ? 0 : 0.18), lineWidth: 1))
                                .foregroundStyle(engine.rate == s ? Theme.onAccent : .white.opacity(0.9))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
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
        s == 1 ? "1×" : (s == 1.25 ? "1.25×" : "1.5×")
    }

    // MARK: 生命周期

    private func start() {
        guard let url = model.api.mediaURL(video.videoUrl) else { return }
        engine.onReachEnd = { autoNext() }
        engine.load(url: url, headers: model.api.authHeaders, startAt: Double(model.position(of: video)))
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
            stop(); model.route = .library
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
