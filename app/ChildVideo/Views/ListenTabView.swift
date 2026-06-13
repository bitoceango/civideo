import SwiftUI

// 「听书」Tab：独立书架 —— 继续收听 + 分类筛选 + 书籍网格。
struct ListenTabView: View {
    @EnvironmentObject var model: AppModel
    @State private var category: String? = nil   // nil = 全部

    private var categories: [String] {
        var seen: [String] = []
        for b in model.audiobooks { if let c = b.category, !seen.contains(c) { seen.append(c) } }
        return seen
    }
    private var filtered: [Audiobook] {
        guard let category else { return model.audiobooks }
        return model.audiobooks.filter { $0.category == category }
    }
    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    header

                    if model.audiobooks.isEmpty {
                        emptyState
                    } else {
                        if !model.continueListening.isEmpty {
                            sectionTitle("继续收听")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(model.continueListening) { b in
                                        NavigationLink(value: b) { AudiobookCard(book: b, width: 116) }
                                            .buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 20).padding(.vertical, 4)
                            }
                        }

                        if !categories.isEmpty { chips }

                        LazyVGrid(columns: cols, spacing: 16) {
                            ForEach(filtered) { b in
                                NavigationLink(value: b) { AudiobookCard(book: b, width: nil) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 6)
                    }
                    Color.clear.frame(height: 20)
                }
            }
            .background(Theme.bg)
            .navigationDestination(for: Audiobook.self) { AudiobookDetailView(book: $0) }
            .refreshable { await model.reload() }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Theme.accentHi, Color(hex: 0x7AD0B0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 50)
                .overlay(Image(systemName: "headphones").font(.system(size: 22)).foregroundStyle(Theme.onAccent))
            VStack(alignment: .leading, spacing: 1) {
                Text("听书").font(.system(size: 21, weight: .bold)).foregroundStyle(Theme.text)
                Text("挑一本，边玩边听").font(.system(size: 13.5)).foregroundStyle(Theme.faint)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 8)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 4)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", on: category == nil) { category = nil }
                ForEach(categories, id: \.self) { c in chip(c, on: category == c) { category = c } }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func chip(_ t: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(t).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(on ? Theme.onAccent : Theme.muted)
                .overlay(Capsule().stroke(on ? .clear : Theme.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones").font(.system(size: 40)).foregroundStyle(Theme.faint)
            Text("还没有听书").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
            Text("家长用 cpv audiobook 上传电子书后，这里就会出现啦").font(.system(size: 13)).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80).padding(.horizontal, 30)
    }
}

// 书封面卡：width=nil 时自适应填满网格列宽
struct AudiobookCard: View {
    @EnvironmentObject var model: AppModel
    let book: Audiobook
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: model.api.mediaURL(book.coverUrl ?? ""), headers: model.api.authHeaders) {
                    LinearGradient.poster(seed: book.id)
                }
                .aspectRatio(3.0/4.0, contentMode: .fill)
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 14)).allowsHitTesting(false)

                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "headphones").font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.4), in: Capsule()).foregroundStyle(.white.opacity(0.92))
                        Spacer()
                    }.padding(8)
                    Spacer()
                    Text(book.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).shadow(color: .black.opacity(0.6), radius: 5)
                        .padding(.horizontal, 9).padding(.bottom, 9)
                }
            }
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .frame(width: width)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(book.author ?? "\(book.chapters.count) 章").font(.system(size: 11.5)).foregroundStyle(Theme.faint).lineLimit(1)
            }
        }
        .frame(width: width)
    }
}
