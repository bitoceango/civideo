import SwiftUI

// 学科 → 图标/配色（封闭花园：固定映射，无外部数据）
enum CategoryStyle {
    static func icon(_ name: String) -> String {
        if name.contains("科学") || name.contains("自然") { return "atom" }
        if name.contains("动物") { return "pawprint.fill" }
        if name.contains("英语") || name.lowercased().contains("english") { return "textformat.abc" }
        if name.contains("数") { return "function" }
        if name.contains("国学") || name.contains("古诗") || name.contains("语文") { return "book.closed.fill" }
        if name.contains("艺术") || name.contains("画") || name.contains("音乐") { return "paintpalette.fill" }
        if name.contains("历史") { return "clock.arrow.circlepath" }
        if name.contains("安全") { return "shield.lefthalf.filled" }
        return "square.grid.2x2.fill"
    }
    static func hue(_ name: String) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Double(h % 360) / 360.0
    }
    static func color(_ name: String) -> Color {
        Color(hue: hue(name), saturation: 0.5, brightness: 0.7)
    }
}

// 分类总览（Story C1）
struct CategoryView: View {
    @EnvironmentObject var model: AppModel
    private let cols = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.categoryGroups.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(model.categoryGroups) { g in
                            NavigationLink(value: LibraryDestination.category(g.id)) { CategoryCard(group: g) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
            .background(Theme.bg)
            .navigationTitle("分类")
            .navigationDestination(for: LibraryDestination.self) { dest in
                switch dest {
                case .category(let id):
                    if let g = model.categoryGroups.first(where: { $0.id == id }) {
                        CategoryDetailView(group: g)
                    }
                case .series(let name):
                    SeriesDetailView(title: name)
                }
            }
        }
        .tint(Theme.accent)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40)).foregroundStyle(Theme.faint)
            Text("还没有分类").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
            Text("上传视频时用 --category 指定学科，这里就会出现").font(.system(size: 13)).foregroundStyle(Theme.faint)
        }.frame(maxWidth: .infinity).padding(.vertical, 100)
    }
}

struct CategoryCard: View {
    let group: SeriesGroup
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(CategoryStyle.color(group.title).opacity(0.22))
                Image(systemName: CategoryStyle.icon(group.title))
                    .font(.system(size: 30))
                    .foregroundStyle(CategoryStyle.color(group.title))
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Text("\(group.videos.count) 个视频").font(.system(size: 13)).foregroundStyle(Theme.faint)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.faint)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

// 分类详情（Story C2）：按系列分组展示，固定排序，无热度榜
struct CategoryDetailView: View {
    @EnvironmentObject var model: AppModel
    let group: SeriesGroup
    private let cols = [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 18)]

    private var bySeries: [SeriesGroup] {
        var order: [String] = []; var map: [String: [Video]] = [:]
        for v in group.videos {
            let k = v.series ?? "单集"
            if map[k] == nil { order.append(k); map[k] = [] }
            map[k]?.append(v)
        }
        return order.map { SeriesGroup(id: $0, title: $0, videos: map[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bySeries) { s in
                    SeriesRow(title: s.title, subtitle: "共 \(s.videos.count) 集",
                              videos: s.videos, big: false, seriesId: s.id)
                }
                Color.clear.frame(height: 30)
            }
        }
        .background(Theme.bg)
        .navigationTitle(group.title)
    }
}
