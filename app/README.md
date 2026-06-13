# ChildVideo — 孩子端 App（iOS + macOS）

一套 SwiftUI 多平台代码，覆盖 iPhone / iPad / Mac。播放统一用系统 AVPlayer，接已部署的 Worker（`https://video.example.com`）。

## 目录

```
app/
  project.yml              xcodegen 工程描述（iOS 17+ / macOS 14+）
  ChildVideo/
    ChildVideoApp.swift    @main + RootView 路由
    Support/
      Theme.swift          深色影院风配色（由网页原型 oklch 转 sRGB）
      Config.swift         默认服务器地址、持久化键、当日/分钟换算
      Models.swift         与 Worker API 对齐的 Codable 模型
      TokenStore.swift     设备令牌存 Keychain
      APIClient.swift      activate/library/media/progress/rules
      AppModel.swift       应用状态、分组、续播、家长闸门
    Views/
      ActivationView       家长 PIN 激活（服务器地址预填）
      LibraryView          问候 + 时长胶囊 + 系列封面墙 + 继续观看
      PosterCard           封面卡（鉴权加载真实封面 + 续播进度条）
      RemoteImage          带鉴权头的图片加载（AsyncImage 不支持自定义 header）
      VideoSurface         AVPlayerLayer 跨平台承载
      PlayerView           商业级播放控件（拖动/倍速/±10s/自动隐藏/同系列下一集）
      ParentView           PIN 键盘 + 设置（每日时长 / 允许时段 / 注销）
      BreakView            "休息一下"拦截页（超时段 / 超时长）
```

## 构建

需要 Xcode 16+ 和 xcodegen（`brew install xcodegen`）。

```bash
cd app
xcodegen generate          # 生成 ChildVideo.xcodeproj（两个 target）
open ChildVideo.xcodeproj
```

命令行构建验证：

```bash
# macOS
xcodebuild -scheme ChildVideo_macOS -configuration Debug -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
# iOS 模拟器
xcodebuild -scheme ChildVideo_iOS -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios CODE_SIGNING_ALLOWED=NO build
```

## 分发到家庭设备

- **Mac**：Xcode 直接 Run，或 Product → Archive → 导出 Developer ID / ad-hoc，本地运行（无年费）。
- **iPhone / iPad**：用**免费 Apple ID** 在 Xcode 里签名（Signing & Capabilities → 选个人 Team），导出 .ipa 后用 **SideStore** 安装并自动续签（7 天证书，SideStore 在设备本地自动刷新）。详见 docs/architecture.md §4.4。

## 首次使用

App 第一次启动显示「激活这台设备」：服务器地址已预填 `https://video.example.com`，输入家长 PIN 即激活，令牌存入 Keychain，之后直接进入孩子界面。

## 调试种子（仅 DEBUG 构建）

为方便端到端测试，`AppModel.bootstrap()` 内有 `#if DEBUG` 路径，可用 UserDefaults 注入状态（release 构建编译移除，不影响线上）：

| 键 | 作用 |
|---|---|
| `cv.debugToken` (string) | 直接注入设备令牌，跳过激活 |
| `cv.debugAutoplay` (bool) | 启动即播放库中第一个视频 |
| `cv.debugRoute` (string=parent) | 启动直达家长页 |

```bash
xcrun simctl spawn booted defaults write com.example.childvideo cv.debugToken -string "<token>"
```
