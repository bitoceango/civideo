import SwiftUI

// 库内导航目的地（首页/分类共用）
enum LibraryDestination: Hashable {
    case category(String)   // 学科 id
    case series(String)     // 系列名
}

// 系列详情：竖向网格展示该系列【全部】集，解决横排放不下的问题
struct SeriesDetailView: View {
    @EnvironmentObject var model: AppModel
    let title: String
    private let cols = [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 18)]

    private var videos: [Video] {
        model.seriesGroups.first(where: { $0.id == title })?.videos ?? []
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 20) {
                ForEach(videos) { v in
                    PosterCard(video: v, big: false) { model.route = .player(v) }
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
        .navigationTitle("\(title) · 共 \(videos.count) 集")
    }
}
