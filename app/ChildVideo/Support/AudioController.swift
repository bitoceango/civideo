import SwiftUI
import Combine

// 全局音频播放器：由 AppModel 持有，跨页面/跨 Tab 不中断。
// 迷你条与全屏播放器都只是它的视图。复用 PlayerView 里的 PlayerEngine。
@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var book: Audiobook?
    @Published private(set) var chapter: Chapter?
    @Published var isExpanded = false           // 全屏播放器是否展开
    @Published var sleepRemainingSec: Int?      // 睡眠定时剩余（秒），nil=未设
    @Published var sleepEndOfChapter = false     // 睡眠定时=本章结束

    let engine = PlayerEngine()

    // 由 AppModel 注入（每次调用都读最新 api）
    var mediaURL: ((String) -> URL?)?
    var authHeaders: () -> [String: String] = { [:] }
    var startPosition: ((Audiobook, Chapter) -> Int)?
    var nextChapterOf: ((Audiobook, Chapter) -> Chapter?)?
    var prevChapterOf: ((Audiobook, Chapter) -> Chapter?)?
    var report: ((Audiobook, Chapter, Int, Int) async -> BlockReason?)?
    var onBlocked: ((BlockReason) -> Void)?

    private var bag = Set<AnyCancellable>()
    private var heartbeat: Timer?
    private var sleepTimer: Timer?
    private var lastReported = 0

    init() {
        // 转发 engine 的变更，让观察 AudioController 的视图能刷新
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var isPlaying: Bool { engine.isPlaying }
    var current: Double { engine.current }
    var duration: Double { engine.duration > 0 ? engine.duration : Double(chapter?.durationSec ?? 0) }
    var progressFraction: Double { duration > 0 ? min(1, max(0, current / duration)) : 0 }

    func play(book: Audiobook, chapter: Chapter, expand: Bool = true) {
        self.book = book
        self.chapter = chapter
        if expand { isExpanded = true }
        guard let url = mediaURL?(chapter.audioUrl) else { return }
        engine.teardown()      // 清掉上一章的观察者，避免重复回调
        engine.onReachEnd = { [weak self] in self?.autoNext() }
        engine.onNext = { [weak self] in self?.next() }
        engine.onPrev = { [weak self] in self?.prev() }
        engine.load(url: url, headers: authHeaders(),
                    startAt: Double(startPosition?(book, chapter) ?? 0),
                    title: chapter.title, series: book.title)
        lastReported = startPosition?(book, chapter) ?? 0
        startHeartbeat()
    }

    func toggle() { engine.togglePlay() }
    func skip(_ d: Double) { engine.skip(d) }
    func seek(_ s: Double) { engine.seek(to: s) }
    var hasNext: Bool { guard let b = book, let c = chapter else { return false }; return nextChapterOf?(b, c) != nil }
    var hasPrev: Bool { guard let b = book, let c = chapter else { return false }; return prevChapterOf?(b, c) != nil }

    func next() {
        guard let b = book, let c = chapter, let n = nextChapterOf?(b, c) else { return }
        Task { await reportTick() }
        play(book: b, chapter: n, expand: isExpanded)
    }
    func prev() {
        guard let b = book, let c = chapter else { return }
        if let p = prevChapterOf?(b, c) { Task { await reportTick() }; play(book: b, chapter: p, expand: isExpanded) }
        else { engine.seek(to: 0) }
    }
    private func autoNext() {
        guard let b = book, let c = chapter else { return }
        Task { await reportTick() }
        if sleepEndOfChapter { stopSleep(); engine.pause(); return }   // 睡眠定时=本章结束
        if let n = nextChapterOf?(b, c) { play(book: b, chapter: n, expand: isExpanded) }
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reportTick() }
        }
    }
    private func reportTick() async {
        guard let b = book, let c = chapter else { return }
        let pos = Int(engine.current)
        let delta = engine.isPlaying ? max(0, pos - lastReported) : 0
        lastReported = pos
        if let reason = await report?(b, c, pos, delta) {
            engine.pause()
            onBlocked?(reason)
        }
    }

    // 睡眠定时
    func setSleep(minutes: Int) {
        sleepEndOfChapter = false
        sleepRemainingSec = minutes * 60
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let r = self.sleepRemainingSec else { return }
                let n = r - 1
                self.sleepRemainingSec = n
                if n <= 0 { self.stopSleep(); self.engine.pause() }
            }
        }
    }
    func setSleepEndOfChapter() { sleepEndOfChapter = true; sleepRemainingSec = nil; sleepTimer?.invalidate() }
    func stopSleep() { sleepRemainingSec = nil; sleepEndOfChapter = false; sleepTimer?.invalidate(); sleepTimer = nil }

    // 彻底停止并清空（如退出登录）
    func close() {
        heartbeat?.invalidate(); heartbeat = nil
        stopSleep()
        Task { await reportTick() }
        engine.teardown()
        book = nil; chapter = nil; isExpanded = false
    }
}
