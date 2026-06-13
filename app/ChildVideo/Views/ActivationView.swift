import SwiftUI

struct ActivationView: View {
    @EnvironmentObject var model: AppModel
    @State private var server = UserDefaults.standard.string(forKey: Config.kServer) ?? Config.defaultServer
    @State private var deviceName = UserDefaults.standard.string(forKey: Config.kDeviceName) ?? defaultDeviceName()
    @State private var pin = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.bg2, Theme.bg], center: .top, startRadius: 10, endRadius: 700)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.card).frame(width: 76, height: 76)
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                    Image(systemName: "lock.shield").font(.system(size: 30)).foregroundStyle(Theme.accentHi)
                }
                VStack(spacing: 6) {
                    Text("激活这台设备").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
                    Text("由家长输入密码，激活后孩子即可观看").font(.system(size: 14)).foregroundStyle(Theme.faint)
                }

                VStack(spacing: 14) {
                    field(title: "服务器地址", text: $server, placeholder: "https://你的-worker-域名")
                    field(title: "设备名称", text: $deviceName, placeholder: "")
                    SecureField("", text: $pin, prompt: Text("家长密码 / 激活密钥").foregroundStyle(Theme.faint))
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                        .foregroundStyle(Theme.text)
                        // #17：放开数字键盘，支持长随机激活密钥（ACTIVATION_KEY）
                        #if os(iOS)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        #endif
                }
                .frame(maxWidth: 380)

                if let error {
                    Text(error).font(.system(size: 13)).foregroundStyle(Color(hex: 0xE06B6B))
                }

                Button(action: activate) {
                    HStack {
                        if busy { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                        Text(busy ? "激活中…" : "激活").font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: 380).padding(.vertical, 15)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.plain)
                .disabled(busy || pin.isEmpty || server.isEmpty)
                .opacity(pin.isEmpty || server.isEmpty ? 0.5 : 1)
            }
            .padding(30)
        }
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.faint)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.faint))
                .textFieldStyle(.plain)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .foregroundStyle(Theme.text)
                #if os(iOS)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                #endif
        }
    }

    private func activate() {
        busy = true; error = nil
        Task {
            do {
                try await model.activate(server: server.trimmingCharacters(in: .whitespaces),
                                         pin: pin, deviceName: deviceName)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

func defaultDeviceName() -> String {
    #if os(iOS)
    return UIDevice.current.name
    #else
    return Host.current().localizedName ?? "Mac"
    #endif
}
