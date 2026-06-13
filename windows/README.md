# 儿童视频 — Windows 客户端（Tauri）

Windows 10/11 x64 桌面 App，复用同一套 Worker API 与 R2 内容。基于 **Tauri v2**（Rust 壳 + 系统 WebView2 渲染 Web UI），安装包小（~5–10MB），WebView2 原生播放 H.264 MP4。

## 怎么拿到安装包（给家人用）

作者在 macOS 上开发，**Windows 安装包由 GitHub Actions 自动在 Windows 服务器上构建**：

1. 每次推送到 `main`（改动 `windows/**`）或手动触发，`Windows Build` workflow 会构建。
2. 进仓库 **Actions → 对应运行 → Artifacts**，下载 `childvideo-windows-x64`（含 `.msi`/`.exe`）。
3. 把安装包发给家人，**双击安装即用**。WebView2 是 Win10/11 自带的。
   - ⚠️ 未做代码签名时，首次运行 Windows SmartScreen 会提示"未知发布者"，点"更多信息 → 仍要运行"。

## 本地开发（在 Windows 上）

```bash
# 需要 Rust + Tauri CLI
cargo install tauri-cli --version "^2" --locked
cd windows
cargo tauri dev      # 开发热重载
cargo tauri build    # 出 x64 .msi/.exe（在 src-tauri/target/release/bundle/）
```

> 在 macOS 上只能 `cargo check`（验证 Rust 编译）；产出 Windows 安装包必须在 Windows/CI。

## 结构
```
windows/
  src/                前端（HTML/JS，对接 Worker REST；Epic B/#3 实现三模块+播放器）
  src-tauri/          Rust 壳 + tauri.conf.json + 图标
  package.json        前端（静态，无构建步骤）
```

首次启动在激活页填入 Worker 域名 + 家长 PIN（同 Apple 端）。
