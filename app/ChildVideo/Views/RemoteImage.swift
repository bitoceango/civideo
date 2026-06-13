import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

// 带鉴权头的封面图加载（AsyncImage 不支持自定义 header，故自行实现）
actor ImageCache {
    static let shared = ImageCache()
    private var store: [String: PlatformImage] = [:]
    func get(_ key: String) -> PlatformImage? { store[key] }
    func set(_ key: String, _ img: PlatformImage) { store[key] = img }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let headers: [String: String]
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                #if os(iOS)
                Image(uiImage: image).resizable().scaledToFill()
                #else
                Image(nsImage: image).resizable().scaledToFill()
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        let key = url.absoluteString
        if let cached = await ImageCache.shared.get(key) { image = cached; return }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = PlatformImage(data: data) else { return }
        await ImageCache.shared.set(key, img)
        image = img
    }
}
