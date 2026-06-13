import SwiftUI

struct ParentView: View {
    @EnvironmentObject var model: AppModel
    @State private var pin = ""
    @State private var unlocked = false
    @State private var shake = false
    @State private var enteredPIN = ""

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.bg2, Theme.bg], center: .top, startRadius: 10, endRadius: 700)
                .ignoresSafeArea()
            if unlocked {
                ParentSettings(pin: enteredPIN, onExit: { model.route = .library })
            } else {
                pinPad
            }
        }
    }

    private var pinPad: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.card).frame(width: 72, height: 72)
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(Theme.accentHi)
            }
            Text("家长验证").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
            Text("输入密码进入设置").font(.system(size: 14)).foregroundStyle(Theme.faint)

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Theme.accentHi : Theme.cardHi)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(i < pin.count ? .clear : Theme.line, lineWidth: 1))
                }
            }
            .padding(.vertical, 10)
            .offset(x: shake ? -8 : 0)
            .animation(.default.repeatCount(3, autoreverses: true).speed(6), value: shake)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 14), count: 3), spacing: 14) {
                ForEach(1...9, id: \.self) { n in key("\(n)") { press("\(n)") } }
                ghostKey("取消") { model.route = .library }
                key("0") { press("0") }
                ghostKey("⌫") { if !pin.isEmpty { pin.removeLast() } }
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
    private func ghostKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.muted)
                .frame(width: 78, height: 64)
        }.buttonStyle(.plain)
    }

    private func press(_ d: String) {
        guard pin.count < 4 else { return }
        pin += d
        if pin.count == 4 {
            let entered = pin
            // 直接进入设置；保存时用 PIN 调后端校验，错误会在保存时反馈
            // 这里做本地"看起来对"的体验：任意 4 位先放行到设置（真正校验在保存接口）
            enteredPIN = entered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { unlocked = true }
        }
    }
}

struct ParentSettings: View {
    @EnvironmentObject var model: AppModel
    let pin: String
    let onExit: () -> Void

    @State private var limitEnabled: Bool
    @State private var limitMin: Int
    @State private var hoursEnabled: Bool
    @State private var startHour: Int
    @State private var endHour: Int
    @State private var saving = false
    @State private var saveError: String?
    @State private var saved = false

    @State private var eyeCareMin: Int

    init(pin: String, onExit: @escaping () -> Void) {
        self.pin = pin
        self.onExit = onExit
        _limitEnabled = State(initialValue: false)
        _limitMin = State(initialValue: 60)
        _hoursEnabled = State(initialValue: false)
        _startHour = State(initialValue: 16)
        _endHour = State(initialValue: 20)
        _eyeCareMin = State(initialValue: UserDefaults.standard.integer(forKey: Config.kEyeCareMin))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("家长设置").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
                        Text("已连接 " + serverHost).font(.system(size: 13)).foregroundStyle(Theme.faint)
                    }
                    Spacer()
                    Button(action: onExit) {
                        Label("返回", systemImage: "chevron.left").font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                            .foregroundStyle(Theme.text)
                    }.buttonStyle(.plain)
                }
                .padding(.top, 8)

                group {
                    settingRow(title: "每日观看上限", sub: "看满后自动进入休息页面") {
                        Toggle("", isOn: $limitEnabled).labelsHidden().tint(Theme.accent)
                    }
                    if limitEnabled {
                        settingRow(title: "上限时长", sub: nil) {
                            stepper(value: $limitMin, range: 15...180, step: 15, suffix: " 分钟")
                        }
                    }
                }

                group {
                    settingRow(title: "限制观看时段", sub: "仅在设定时段内可以播放") {
                        Toggle("", isOn: $hoursEnabled).labelsHidden().tint(Theme.accent)
                    }
                    if hoursEnabled {
                        settingRow(title: "开始时间", sub: nil) {
                            stepper(value: $startHour, range: 0...23, step: 1, suffix: ":00")
                        }
                        settingRow(title: "结束时间", sub: nil) {
                            stepper(value: $endHour, range: 1...24, step: 1, suffix: ":00")
                        }
                    }
                }

                group {
                    settingRow(title: "护眼提醒", sub: "连续观看到点提醒孩子休息眼睛") {
                        eyeCarePicker
                    }
                }

                group {
                    settingRow(title: "学习报告", sub: deviceName) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("今日 \(model.todayWatchedSec / 60) 分钟")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("本周 \(model.weekWatchedSec / 60) 分钟")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.faint)
                        }
                    }
                }

                if let saveError {
                    Text(saveError).font(.system(size: 13)).foregroundStyle(Color(hex: 0xE06B6B))
                }
                if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(Theme.good)
                }

                Button(action: save) {
                    HStack {
                        if saving { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                        Text(saving ? "保存中…" : "保存设置").font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.onAccent)
                }.buttonStyle(.plain)

                Button(role: .destructive) { model.deactivate() } label: {
                    Text("注销此设备").font(.system(size: 14)).foregroundStyle(Color(hex: 0xE06B6B))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.plain)

                Color.clear.frame(height: 30)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: loadCurrent)
    }

    private func loadCurrent() {
        if let lim = model.rules.dailyLimitMin { limitEnabled = true; limitMin = lim }
        if let s = model.rules.allowedStart, let e = model.rules.allowedEnd {
            hoursEnabled = true; startHour = s / 60; endHour = e / 60
        }
    }

    private func save() {
        saving = true; saveError = nil; saved = false
        Task {
            do {
                try await model.saveRules(
                    pin: pin,
                    dailyLimitMin: limitEnabled ? limitMin : nil,
                    allowedStart: hoursEnabled ? startHour * 60 : nil,
                    allowedEnd: hoursEnabled ? endHour * 60 : nil)
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
            } catch {
                saveError = error.localizedDescription
            }
            saving = false
        }
    }

    // MARK: 小组件
    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
    }

    private func settingRow<C: View>(title: String, sub: String?, @ViewBuilder trailing: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                if let sub { Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.faint) }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 16)
        .overlay(Divider().background(Theme.line), alignment: .bottom)
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, step: Int, suffix: String) -> some View {
        HStack(spacing: 4) {
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: {
                Image(systemName: "minus").frame(width: 34, height: 34).foregroundStyle(Theme.muted)
            }.buttonStyle(.plain)
            Text("\(value.wrappedValue)\(suffix)").font(.system(size: 15, weight: .semibold))
                .monospacedDigit().frame(minWidth: 78)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: {
                Image(systemName: "plus").frame(width: 34, height: 34).foregroundStyle(Theme.muted)
            }.buttonStyle(.plain)
        }
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12))
    }

    private var eyeCarePicker: some View {
        HStack(spacing: 4) {
            ForEach([(0, "关"), (20, "20"), (30, "30"), (45, "45")], id: \.0) { v, label in
                Button {
                    eyeCareMin = v
                    UserDefaults.standard.set(v, forKey: Config.kEyeCareMin)
                } label: {
                    Text(label).font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(eyeCareMin == v ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(eyeCareMin == v ? Theme.onAccent : Theme.muted)
                }.buttonStyle(.plain)
            }
        }
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12))
    }

    private var serverHost: String {
        URL(string: model.server)?.host ?? model.server
    }
    private var deviceName: String {
        UserDefaults.standard.string(forKey: Config.kDeviceName) ?? "这台设备"
    }
}
