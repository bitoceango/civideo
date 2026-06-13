import SwiftUI

enum Route: Equatable {
    case loading
    case activation
    case library          // 主壳（底部 Tab：首页/听书/我的）
    case player(Video)    // 全屏视频
    case parent
    case blocked(BlockReason)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: Route = .loading
    @Published var library: [Video] = []
    @Published var audiobooks: [Audiobook] = []
    @Published var progress: [String: Int] = [:]   // videoId / "<bookId>#<chIdx>" -> 已观看秒
    @Published var rules: Rules = Rules(dailyLimitMin: nil, allowedStart: nil, allowedEnd: nil)
    @Published var todayWatchedSec: Int = 0
    @Published var loadError: String?
    @Published var favorites: Set<String> = []   // 收藏的 videoId（存本地）

    private(set) var api: APIClient
    let audio = AudioController()          // 全局音频播放器（跨 Tab 不中断）
    private let kFavorites = "cv.favorites"

    init() {
        let server = UserDefaults.standard.string(forKey: Config.kServer) ?? Config.defaultServer
        api = APIClient(baseURL: server, token: TokenStore.load())
        todayWatchedSec = UserDefaults.standard.integer(forKey: Config.kWatchedPrefix + Config.todayKey())
        favorites = Set(UserDefaults.standard.stringArray(forKey: kFavorites) ?? [])
        configureAudio()
    }

    // 把全局播放器接到本 model（媒体地址/进度上报/章节导航/拦截）
    private func configureAudio() {
        audio.mediaURL = { [weak self] rel in self?.api.mediaURL(rel) }
        audio.authHeaders = { [weak self] in self?.api.authHeaders ?? [:] }
        audio.startPosition = { [weak self] b, c in self?.position(of: b, chapter: c) ?? 0 }
        audio.nextChapterOf = { [weak self] b, c in self?.nextChapter(in: b, after: c) }
        audio.prevChapterOf = { [weak self] b, c in self?.prevChapter(in: b, before: c) }
        audio.report = { [weak self] b, c, pos, delta in
            await self?.reportAudioProgress(book: b, chapter: c, positionSec: pos, deltaSec: delta)
        }
        audio.onBlocked = { [weak self] reason in self?.route = .blocked(reason) }
    }

    func isFavorite(_ v: Video) -> Bool { favorites.contains(v.id) }
    func toggleFavorite(_ v: Video) { toggleFavorite(id: v.id) }
    var favoriteVideos: [Video] { library.filter { favorites.contains($0.id) } }

    // 收藏（视频与听书共用一个集合，id 前缀天然区分 v.../a...）
    func isFavorite(book: Audiobook) -> Bool { favorites.contains(book.id) }
    func toggleFavorite(book: Audiobook) { toggleFavorite(id: book.id) }
    var favoriteAudiobooks: [Audiobook] { audiobooks.filter { favorites.contains($0.id) } }
    private func toggleFavorite(id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: kFavorites)
    }

    // MARK: 听书进度 / 续听 / 章节导航

    func chapterKey(_ book: Audiobook, _ ch: Chapter) -> String { "\(book.id)#\(ch.idx)" }
    func position(of book: Audiobook, chapter ch: Chapter) -> Int { progress[chapterKey(book, ch)] ?? 0 }

    // 上次在听、且未听完的章节（用于「继续收听」）
    func lastChapter(of book: Audiobook) -> Chapter? {
        book.chapters
            .filter { let p = position(of: book, chapter: $0); return p > 5 && p < $0.durationSec - 5 }
            .max(by: { position(of: book, chapter: $0) < position(of: book, chapter: $1) })
    }
    var continueListening: [Audiobook] { audiobooks.filter { lastChapter(of: $0) != nil } }

    func nextChapter(in book: Audiobook, after ch: Chapter) -> Chapter? {
        guard let i = book.chapters.firstIndex(of: ch), i + 1 < book.chapters.count else { return nil }
        return book.chapters[i + 1]
    }
    func prevChapter(in book: Audiobook, before ch: Chapter) -> Chapter? {
        guard let i = book.chapters.firstIndex(of: ch), i - 1 >= 0 else { return nil }
        return book.chapters[i - 1]
    }

    // 听书播放心跳：复用 watch_progress / watch_daily / 时段时长拦截（videoId 用章节复合键）
    func reportAudioProgress(book: Audiobook, chapter: Chapter, positionSec: Int, deltaSec: Int) async -> BlockReason? {
        let key = chapterKey(book, chapter)
        progress[key] = positionSec
        do {
            let res = try await api.postProgress(
                videoId: key, positionSec: positionSec,
                day: Config.todayKey(), deltaSec: max(0, deltaSec), minuteOfDay: Config.minuteOfDay())
            if let w = res.watchedSec {
                todayWatchedSec = w
                UserDefaults.standard.set(w, forKey: Config.kWatchedPrefix + Config.todayKey())
            }
            return BlockReason(apiString: res.blocked)
        } catch {
            return nil
        }
    }

    var server: String { api.baseURL }

    // 启动：有令牌就进库，否则去激活
    func bootstrap() async {
        #if DEBUG
        // 测试用种子：通过 UserDefaults 注入令牌/深链，仅 DEBUG 构建生效（release 编译移除）
        if let t = UserDefaults.standard.string(forKey: "cv.debugToken"), !t.isEmpty {
            api = APIClient(baseURL: server, token: t)
        }
        #endif
        if api.token == nil {
            route = .activation
            return
        }
        await reload()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "cv.debugAutoplay"), let v = library.first {
            route = .player(v)
        } else if UserDefaults.standard.string(forKey: "cv.debugRoute") == "parent" {
            route = .parent
        }
        #endif
    }

    func reload() async {
        do {
            async let lib = api.fetchLibrary()
            async let prog = api.fetchProgress(day: Config.todayKey())
            let (l, p) = try await (lib, prog)
            library = l.videos
            audiobooks = l.audiobooks ?? []
            progress = p.progress
            rules = p.rules
            if let w = p.watchedSec {
                todayWatchedSec = w
                UserDefaults.standard.set(w, forKey: Config.kWatchedPrefix + Config.todayKey())
            }
            evaluateGateOnEntry()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "cv.debugPlay"),
               let b = audiobooks.first, let c = b.chapters.first {
                audio.play(book: b, chapter: c)
            }
            #endif
        } catch APIError.unauthorized {
            TokenStore.clear()
            api.token = nil
            route = .activation
        } catch {
            loadError = error.localizedDescription
            route = .library   // 仍进库，显示错误
        }
    }

    // 进入库时先判断是否在禁播状态（超时段/超时长）
    private func evaluateGateOnEntry() {
        if let r = currentBlock() {
            route = .blocked(r)
        } else if case .loading = route {
            route = .library
        } else if case .activation = route {
            route = .library
        } else {
            route = .library
        }
    }

    func currentBlock() -> BlockReason? {
        // 超时段
        if let s = rules.allowedStart, let e = rules.allowedEnd {
            let m = Config.minuteOfDay()
            let inWindow = s <= e ? (m >= s && m < e) : (m >= s || m < e)
            if !inWindow { return .hours }
        }
        // 超时长
        if let limit = rules.dailyLimitMin, todayWatchedSec >= limit * 60 {
            return .limit
        }
        return nil
    }

    var remainingMin: Int? {
        guard let limit = rules.dailyLimitMin else { return nil }
        return max(0, limit - todayWatchedSec / 60)
    }

    // 按系列分组（manifest 的 series 字段）
    var seriesGroups: [SeriesGroup] {
        var order: [String] = []
        var map: [String: [Video]] = [:]
        for v in library {
            let key = v.series ?? "未分组"
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(v)
        }
        return order.map { SeriesGroup(id: $0, title: $0, videos: map[$0] ?? []) }
    }

    // 继续观看：有进度、未看完
    var continueWatching: [Video] {
        library.filter { v in
            let pos = progress[v.id] ?? 0
            return pos > 5 && pos < v.durationSec - 5
        }
    }

    func position(of v: Video) -> Int { progress[v.id] ?? 0 }

    // 同系列下一集
    func nextEpisode(after v: Video) -> Video? {
        guard let group = seriesGroups.first(where: { $0.id == (v.series ?? "未分组") }),
              let idx = group.videos.firstIndex(of: v), idx + 1 < group.videos.count
        else { return nil }
        return group.videos[idx + 1]
    }

    // 同系列上一集
    func prevEpisode(before v: Video) -> Video? {
        guard let group = seriesGroups.first(where: { $0.id == (v.series ?? "未分组") }),
              let idx = group.videos.firstIndex(of: v), idx - 1 >= 0
        else { return nil }
        return group.videos[idx - 1]
    }

    // 播放心跳上报，返回是否被拦截。即使 deltaSec=0 也上报，
    // 以便服务端每次心跳都做时段判断（暂停/边界时也能拦截）。
    func reportProgress(video: Video, positionSec: Int, deltaSec: Int) async -> BlockReason? {
        progress[video.id] = positionSec
        do {
            let res = try await api.postProgress(
                videoId: video.id, positionSec: positionSec,
                day: Config.todayKey(), deltaSec: max(0, deltaSec), minuteOfDay: Config.minuteOfDay())
            if let w = res.watchedSec {
                todayWatchedSec = w
                UserDefaults.standard.set(w, forKey: Config.kWatchedPrefix + Config.todayKey())
            }
            return BlockReason(apiString: res.blocked)
        } catch {
            return nil   // 网络抖动不打断播放
        }
    }

    func activate(server: String, pin: String, deviceName: String) async throws {
        var client = APIClient(baseURL: server, token: nil)
        let res = try await client.activate(pin: pin, name: deviceName)
        TokenStore.save(res.token)
        client.token = res.token
        api = client
        UserDefaults.standard.set(server, forKey: Config.kServer)
        UserDefaults.standard.set(deviceName, forKey: Config.kDeviceName)
        await reload()
    }

    func saveRules(pin: String, dailyLimitMin: Int?, allowedStart: Int?, allowedEnd: Int?) async throws {
        try await api.saveRules(pin: pin, dailyLimitMin: dailyLimitMin,
                                allowedStart: allowedStart, allowedEnd: allowedEnd)
        rules = Rules(dailyLimitMin: dailyLimitMin, allowedStart: allowedStart, allowedEnd: allowedEnd)
    }

    func deactivate() {
        TokenStore.clear()
        api.token = nil
        library = []
        audiobooks = []
        audio.close()
        progress = [:]
        route = .activation
    }
}
