import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    case invalidPIN
    case unauthorized
    case decoding

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址无效"
        case .http(let c): return "网络错误（\(c)）"
        case .invalidPIN: return "密码不正确"
        case .unauthorized: return "设备未授权，请重新激活"
        case .decoding: return "数据解析失败"
        }
    }
}

struct APIClient {
    let baseURL: String
    var token: String?

    private func url(_ path: String) throws -> URL {
        guard let u = URL(string: baseURL + path) else { throw APIError.badURL }
        return u
    }

    private func authed(_ req: inout URLRequest) {
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    // 媒体绝对地址（视频/封面），客户端拼接 baseURL + 相对路径
    func mediaURL(_ relative: String) -> URL? { URL(string: baseURL + relative) }

    // 给 AVURLAsset / 图片加载用的鉴权头
    var authHeaders: [String: String] {
        token.map { ["Authorization": "Bearer \($0)"] } ?? [:]
    }

    func activate(pin: String, name: String) async throws -> ActivateResponse {
        var req = URLRequest(url: try url("/api/activate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["pin": pin, "name": name])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 { throw APIError.invalidPIN }
        guard code == 200 else { throw APIError.http(code) }
        guard let out = try? JSONDecoder().decode(ActivateResponse.self, from: data) else { throw APIError.decoding }
        return out
    }

    func fetchLibrary() async throws -> Library {
        var req = URLRequest(url: try url("/api/library"))
        authed(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.http(code) }
        guard let lib = try? JSONDecoder().decode(Library.self, from: data) else { throw APIError.decoding }
        return lib
    }

    func fetchProgress(day: String) async throws -> ProgressResponse {
        var req = URLRequest(url: try url("/api/progress?day=\(day)"))
        authed(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.http(code) }
        guard let p = try? JSONDecoder().decode(ProgressResponse.self, from: data) else { throw APIError.decoding }
        return p
    }

    @discardableResult
    func postProgress(videoId: String, positionSec: Int, day: String, deltaSec: Int, minuteOfDay: Int) async throws -> ProgressPostResponse {
        var req = URLRequest(url: try url("/api/progress"))
        req.httpMethod = "POST"
        authed(&req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "videoId": videoId, "positionSec": positionSec,
            "day": day, "deltaSec": deltaSec, "minuteOfDay": minuteOfDay,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.http(code) }
        return (try? JSONDecoder().decode(ProgressPostResponse.self, from: data))
            ?? ProgressPostResponse(ok: true, blocked: nil, watchedSec: nil)
    }

    // 家长修改本设备规则（需 PIN 校验，防孩子用设备令牌绕过）
    func saveRules(pin: String, dailyLimitMin: Int?, allowedStart: Int?, allowedEnd: Int?) async throws {
        var req = URLRequest(url: try url("/api/rules"))
        req.httpMethod = "POST"
        authed(&req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["pin": pin]
        body["dailyLimitMin"] = dailyLimitMin as Any? ?? NSNull()
        body["allowedStart"] = allowedStart as Any? ?? NSNull()
        body["allowedEnd"] = allowedEnd as Any? ?? NSNull()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 { throw APIError.invalidPIN }
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.http(code) }
    }
}
