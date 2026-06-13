import SwiftUI

// 底部三大模块（Epic A）：首页 / 分类 / 我的
struct RootTabView: View {
    @State private var tab: Int = {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "cv.debugTab")  // 测试用：指定初始 Tab
        #else
        return 0
        #endif
    }()

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            CategoryView()
                .tabItem { Label("分类", systemImage: "square.grid.2x2.fill") }.tag(1)
            MineView()
                .tabItem { Label("我的", systemImage: "person.fill") }.tag(2)
        }
        .tint(Theme.accent)
    }
}
