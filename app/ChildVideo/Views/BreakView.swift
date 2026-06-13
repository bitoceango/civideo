import SwiftUI

struct BreakView: View {
    @EnvironmentObject var model: AppModel
    let reason: BlockReason

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2A2616), Theme.bg],
                           center: .init(x: 0.5, y: 0.3), startRadius: 10, endRadius: 700)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(Color(hex: 0x2D2818))
                        .frame(width: 92, height: 92)
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color(hex: 0x4A431F), lineWidth: 1))
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 40)).foregroundStyle(Theme.warn)
                }
                .padding(.bottom, 22)

                Text(title).font(.system(size: 27, weight: .bold)).foregroundStyle(Theme.text)
                    .padding(.bottom, 10)
                Text(line1).font(.system(size: 15.5)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 4)
                Text("不如去做点别的：读本书、出去走走、画幅画。")
                    .font(.system(size: 15.5)).foregroundStyle(Theme.muted)

                Text(countdown).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.warn)
                    .padding(.top, 14)

                Button { model.route = .parent } label: {
                    Label("家长可输入密码解除", systemImage: "lock.fill")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.faint)
                }.buttonStyle(.plain).padding(.top, 30)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            .padding(20)
        }
    }

    private var title: String {
        reason == .hours ? "现在不是观看时间哦" : "今天的观看时间到啦"
    }
    private var line1: String {
        reason == .hours ? "到了约定的时段就可以继续看啦。" : "看了很久啦，让眼睛休息一下吧 👀"
    }
    private var countdown: String {
        if reason == .hours, let s = model.rules.allowedStart {
            return "\(s/60):00 可以继续观看"
        }
        return "明天又有新的观看时间"
    }
}
