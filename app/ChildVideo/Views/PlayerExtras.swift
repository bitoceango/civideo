import SwiftUI
import AVKit
import MediaPlayer

// AirPlay / 投屏按钮（包装系统 AVRoutePickerView，跨 iOS/macOS）
#if os(iOS)
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.9)
        v.activeTintColor = UIColor(red: 0.33, green: 0.81, blue: 0.88, alpha: 1)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.isRoutePickerButtonBordered = false
        return v
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

// 锁屏 / 控制中心 / 耳机 的「正在播放」与远程控制
enum NowPlaying {
    static func activateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    static func update(title: String, series: String?, duration: Double, elapsed: Double, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
        if let series { info[MPMediaItemPropertyArtist] = series }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // 注册远程命令，返回以便后续移除
    static func setupCommands(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        skip: @escaping (Double) -> Void,
        seek: @escaping (Double) -> Void,
        next: @escaping () -> Void,
        prev: @escaping () -> Void
    ) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.isEnabled = true
        c.pauseCommand.isEnabled = true
        c.skipForwardCommand.isEnabled = true
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.isEnabled = true
        c.skipBackwardCommand.preferredIntervals = [10]
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        c.changePlaybackPositionCommand.isEnabled = true

        c.playCommand.addTarget { _ in play(); return .success }
        c.pauseCommand.addTarget { _ in pause(); return .success }
        c.skipForwardCommand.addTarget { _ in skip(10); return .success }
        c.skipBackwardCommand.addTarget { _ in skip(-10); return .success }
        c.nextTrackCommand.addTarget { _ in next(); return .success }
        c.previousTrackCommand.addTarget { _ in prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { event in
            if let e = event as? MPChangePlaybackPositionCommandEvent { seek(e.positionTime) }
            return .success
        }
    }

    static func teardownCommands() {
        let c = MPRemoteCommandCenter.shared()
        for cmd in [c.playCommand, c.pauseCommand, c.skipForwardCommand, c.skipBackwardCommand,
                    c.nextTrackCommand, c.previousTrackCommand] {
            cmd.removeTarget(nil)
        }
        c.changePlaybackPositionCommand.removeTarget(nil)
    }
}
