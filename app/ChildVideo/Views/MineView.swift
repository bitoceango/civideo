import SwiftUI

// 我的（Epic D）：家长门（PIN）→ 家长中心设置。锁定后再次进入需重新输 PIN。
struct MineView: View {
    @EnvironmentObject var model: AppModel
    @State private var pin = ""
    @State private var unlocked = false
    @State private var enteredPIN = ""

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.bg2, Theme.bg], center: .top, startRadius: 10, endRadius: 700)
                .ignoresSafeArea()
            if unlocked {
                ParentSettings(pin: enteredPIN, onExit: relock)
            } else {
                gate
            }
        }
    }

    private func relock() { unlocked = false; pin = ""; enteredPIN = "" }

    private var gate: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.card).frame(width: 72, height: 72)
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(Theme.accentHi)
            }
            Text("家长中心").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
            Text("输入家长密码进入管理与设置").font(.system(size: 14)).foregroundStyle(Theme.faint)

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i < pin.count ? Theme.accentHi : Theme.cardHi)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(i < pin.count ? .clear : Theme.line, lineWidth: 1))
                }
            }.padding(.vertical, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 14), count: 3), spacing: 14) {
                ForEach(1...9, id: \.self) { n in key("\(n)") { press("\(n)") } }
                Color.clear.frame(width: 78, height: 64)
                key("0") { press("0") }
                Button { if !pin.isEmpty { pin.removeLast() } } label: {
                    Text("⌫").font(.system(size: 22)).foregroundStyle(Theme.muted).frame(width: 78, height: 64)
                }.buttonStyle(.plain)
            }
            .frame(width: 78*3 + 14*2)
        }
        .padding(30)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.text)
                .frame(width: 78, height: 64)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func press(_ d: String) {
        guard pin.count < 4 else { return }
        pin += d
        if pin.count == 4 {
            enteredPIN = pin
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { unlocked = true }
        }
    }
}
