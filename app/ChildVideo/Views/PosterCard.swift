import SwiftUI

struct PosterCard: View {
    @EnvironmentObject var model: AppModel
    let video: Video
    let big: Bool
    let onTap: () -> Void

    @State private var hovering = false

    private var width: CGFloat { big ? 320 : 220 }
    private var aspect: CGFloat { big ? 16.0/9.0 : 16.0/10.0 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 9) {
                art
                meta
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }

    private var art: some View {
        ZStack {
            RemoteImage(url: model.api.mediaURL(video.posterUrl), headers: model.api.authHeaders) {
                LinearGradient.poster(seed: video.series ?? video.id)
            }
            .frame(width: width, height: width / aspect)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: .bottom, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack {
                HStack {
                    if let epNo = episodeLabel {
                        Text(epNo).font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Text(big ? video.title : (video.series ?? video.title))
                        .font(.system(size: big ? 19 : 17, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                        .shadow(color: .black.opacity(0.6), radius: 6)
                    Spacer()
                    Text(runtimeString(video.durationSec))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(13)

            if hovering {
                Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
            }

            // 续播进度条
            let pos = model.position(of: video)
            if pos > 5 && pos < video.durationSec - 5 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.18))
                            Rectangle().fill(Theme.accentHi)
                                .frame(width: geo.size.width * CGFloat(pos) / CGFloat(max(1, video.durationSec)))
                        }
                    }
                    .frame(height: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(width: width, height: width / aspect)
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(big ? video.title : (video.series ?? video.title))
                .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
            Text(big ? remainingText : (video.title))
                .font(.system(size: 12.5)).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }

    private var remainingText: String {
        let pos = model.position(of: video)
        return "还剩 " + runtimeString(max(0, video.durationSec - pos))
    }

    private var episodeLabel: String? {
        guard let series = video.series,
              let group = model.seriesGroups.first(where: { $0.id == series }),
              let idx = group.videos.firstIndex(of: video) else { return nil }
        return "第 \(String(format: "%02d", idx + 1)) 集"
    }
}
