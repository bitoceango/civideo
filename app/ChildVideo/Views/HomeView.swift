import SwiftUI

// 首页（Epic B）：学科金刚区 + 继续观看 + 我喜欢的 + 系列聚合。无推荐流。
struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    header

                    if let err = model.loadError { errorBanner(err) }

                    if !model.categoryGroups.isEmpty {
                        subjectGrid   // 金刚区（Story B1）
                    }

                    if !model.continueWatching.isEmpty {
                        SeriesRow(title: "继续观看", subtitle: nil, videos: model.continueWatching, big: true)
                    }
                    if !model.favoriteVideos.isEmpty {
                        SeriesRow(title: "我喜欢的", subtitle: nil, videos: model.favoriteVideos, big: false)
                    }
                    ForEach(model.seriesGroups) { g in
                        SeriesRow(title: g.title, subtitle: "共 \(g.videos.count) 集", videos: g.videos, big: false)
                    }
                    if model.library.isEmpty && model.loadError == nil { emptyState }
                    Color.clear.frame(height: 30)
                }
            }
            .background(Theme.bg)
            .navigationDestination(for: String.self) { catId in
                if let g = model.categoryGroups.first(where: { $0.id == catId }) {
                    CategoryDetailView(group: g)
                }
            }
            .refreshable { await model.reload() }
        }
        .tint(Theme.accent)
    }

    // MARK: 头部
    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Theme.accentHi, Color(hex: 0x7AD0B0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                    .overlay(Text(avatarChar).font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.onAccent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(greeting()).font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("今天想学点什么呢？").font(.system(size: 13.5)).foregroundStyle(Theme.faint)
                }
            }
            Spacer()
            if let rem = model.remainingMin { timePill(rem) }
        }
        .padding(.horizontal, 34).padding(.top, 26).padding(.bottom, 14)
    }

    // MARK: 学科金刚区
    private var subjectGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(model.categoryGroups) { g in
                    NavigationLink(value: g.id) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(CategoryStyle.color(g.title).opacity(0.22)).frame(width: 64, height: 64)
                                Image(systemName: CategoryStyle.icon(g.title)).font(.system(size: 26))
                                    .foregroundStyle(CategoryStyle.color(g.title))
                            }
                            Text(g.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        .frame(width: 78)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 34).padding(.vertical, 8)
        }
    }

    private func timePill(_ rem: Int) -> some View {
        let low = rem <= 10
        return HStack(spacing: 7) {
            Circle().fill(low ? Theme.warn : Theme.good).frame(width: 8, height: 8)
            Text("今天还可观看 \(rem) 分钟").font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .foregroundStyle(Theme.text)
    }

    private func errorBanner(_ msg: String) -> some View {
        Text("⚠︎ \(msg)").font(.system(size: 13)).foregroundStyle(Theme.warn)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 34).padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack").font(.system(size: 40)).foregroundStyle(Theme.faint)
            Text("还没有视频").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
            Text("家长上传视频后，这里就会出现啦").font(.system(size: 13)).foregroundStyle(Theme.faint)
        }.frame(maxWidth: .infinity).padding(.vertical, 80)
    }

    private var childName: String {
        UserDefaults.standard.string(forKey: Config.kChildName) ?? Config.defaultChildName
    }
    private var avatarChar: String { String(childName.prefix(1)) }
    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 11 ? "早上好" : (h < 18 ? "下午好" : "晚上好")
        return "\(part)，\(childName)"
    }
}
