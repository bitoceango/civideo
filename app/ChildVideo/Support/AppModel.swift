import SwiftUI

enum Route: Equatable {
    case loading
    case activation
    case library
    case player(Video)
    case parent
    case blocked(BlockReason)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: Route = .loading
    @Published var library: [Video] = []
    @Published var progress: [String: Int] = [:]   // videoId -> 已观看秒
    @Published var rules: Rules = Rules(dailyLimitMin: nil, allowedStart: nil, allowedEnd: nil)
    @Published var todayWatchedSec: Int = 0
    @Published var loadError: String?
    @Published var favorites: Set<String> = []   // 收藏的 videoId（存本地）

    private(set) var api: APIClient
    private let kFavorites = "cv.favorites"

    init() {
        let server = UserDefaults.standard.string(forKey: Config.kServer) ?? Config.defaultServer
        api = APIClient(baseURL: server, token: TokenStore.load())
        todayWatchedSec = UserDefaults.standard.integer(forKey: Config.kWatchedPrefix + Config.todayKey())
        favorites = Set(UserDefaults.standard.stringArray(forKey: kFavorites) ?? [])
    }

    func isFavorite(_ v: Video) -> Bool { favorites.contains(v.id) }
    func toggleFavorite(_ v: Video) {
        if favorites.contains(v.id) { favorites.remove(v.id) } else { favorites.insert(v.id) }
        UserDefaults.standard.set(Array(favorites), forKey: kFavorites)
    }
    var favoriteVideos: [Video] { library.filter { favorites.contains($0.id) } }

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
            progress = p.progress
            rules = p.rules
            if let w = p.watchedSec {
                todayWatchedSec = w
                UserDefaults.standard.set(w, forKey: Config.kWatchedPrefix + Config.todayKey())
            }
            evaluateGateOnEntry()
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
        progress = [:]
        route = .activation
    }
}
