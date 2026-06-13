import Foundation

// 与 Worker /api/library 返回对齐
struct Video: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let series: String?
    let category: String?
    let durationSec: Int
    let width: Int?
    let height: Int?
    let videoUrl: String      // 形如 /media/<id>/video.mp4
    let posterUrl: String     // 形如 /media/<id>/poster.jpg
}

// 听书：一本书的一章（对齐 Worker 的 audiobooks[].chapters[]）
struct Chapter: Codable, Identifiable, Hashable {
    let idx: Int
    let title: String
    let durationSec: Int
    let audioUrl: String      // 形如 /media/audiobooks/<id>/ch-N.mp3
    var id: Int { idx }
}

// 听书：一本书（对齐 Worker /api/library 的 audiobooks[]）
struct Audiobook: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String?
    let category: String?
    let totalDurationSec: Int
    let coverUrl: String?     // 形如 /media/audiobooks/<id>/cover.jpg，可空
    let chapters: [Chapter]
}

struct Library: Codable {
    let version: Int
    let updatedAt: String?
    let videos: [Video]
    let audiobooks: [Audiobook]?   // 旧 Worker 无此字段，可空
}

struct Rules: Codable, Equatable {
    let dailyLimitMin: Int?
    let allowedStart: Int?
    let allowedEnd: Int?
}

struct ProgressResponse: Codable {
    let ok: Bool
    let progress: [String: Int]
    let rules: Rules
    let watchedSec: Int?
    let weekSec: Int?
}

struct ActivateResponse: Codable {
    let ok: Bool
    let deviceId: String
    let token: String
}

// POST /api/progress 的返回
struct ProgressPostResponse: Codable {
    let ok: Bool
    let blocked: String?     // null / "outside_allowed_hours" / "daily_limit_reached"
    let watchedSec: Int?
}

// 一个系列的分组（客户端按 series 字段聚合）
struct SeriesGroup: Identifiable {
    let id: String           // 系列名，或 "未分组"
    let title: String
    let videos: [Video]
}

enum BlockReason: Equatable {
    case hours
    case limit

    init?(apiString: String?) {
        switch apiString {
        case "outside_allowed_hours": self = .hours
        case "daily_limit_reached": self = .limit
        default: return nil
        }
    }
}
