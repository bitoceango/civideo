import Foundation

enum Config {
    // 默认后端地址。开源版留空：首次启动时由家长在激活页填入自己的 Worker 域名。
    // 自用可改成自己的地址，例如 "https://video.example.com"
    static let defaultServer = ""

    // 孩子昵称默认值（显示在主页问候里），家长可在 UserDefaults 改 cv.childName
    static let defaultChildName = "小朋友"

    // 持久化键
    static let kServer = "cv.server"
    static let kDeviceName = "cv.deviceName"
    static let kChildName = "cv.childName"
    static let kWatchedPrefix = "cv.watched."   // + yyyy-MM-dd -> 当日累计秒数

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func minuteOfDay(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
