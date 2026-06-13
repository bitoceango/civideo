import SwiftUI
import AVFoundation

// 用 AVPlayerLayer 承载视频画面（跨 iOS/macOS），以便自绘控件
#if os(iOS)
import UIKit
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView { PlayerLayerView(player: player) }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) { uiView.playerLayer.player = player }
}
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError() }
}
#else
import AppKit
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerLayerView { PlayerLayerView(player: player) }
    func updateNSView(_ nsView: PlayerLayerView, context: Context) { nsView.playerLayer.player = player }
}
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        // 关闭隐式动画，避免每次布局对 playerLayer.frame 触发动画造成画面周期性抖动
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
#endif

// 用带鉴权头的 AVURLAsset 构建 player item
func makeAuthedPlayerItem(url: URL, headers: [String: String]) -> AVPlayerItem {
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    return AVPlayerItem(asset: asset)
}
