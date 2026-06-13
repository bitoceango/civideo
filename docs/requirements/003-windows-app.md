# 需求文档：Windows x64 孩子端 App

> 编号：003 ｜ 状态：草稿（待评审 / 待确认技术选型）
> 创建日期：2026-06-13 ｜ 关联：`docs/architecture.md`、001 三大模块、`designs/child-video-player`

## 1. 背景与目标
当前孩子端只有 SwiftUI App（iOS/iPad/Mac，Apple 平台）。家里如果用 **Windows 电脑**，孩子无法观看。本需求：交付一个 **Windows x64 原生 App**，复用同一套已部署的 Worker API 与 R2 内容，体验对齐现有 Apple 端（封闭花园 + 三大模块 + 商业级播放器 + 家长管控）。

后端无需重做（REST + 媒体网关已就绪），只需少量适配（见 Epic C）。

## 2. 范围
- **本次要做**：Windows 10/11 x64 桌面 App：激活、首页/分类/我的、播放器、家长控制、安装包。
- **本次不做**：Windows ARM、应用商店上架、离线下载（后续）。

## 3. 技术选型分析（关键决策，待你拍板）

| 方案 | 包体 | 复用度 | 播放(H.264 MP4) | 评价 |
|---|---|---|---|---|
| **Tauri（Rust + WebView2）** ⭐推荐 | ~5–10MB | 高（直接复用 `designs/` 的 Web UI） | WebView2=Chromium，`<video>` 原生支持 | 最轻、原生 x64 .msi/.exe；与现有 Web 设计稿同源 |
| Electron（Node + Chromium） | ~100MB+ | 高 | 同上 | 复用度同 Tauri 但包体大、吃内存 |
| Flutter（Dart） | ~20MB | 低（重写 UI） | media_kit 可带鉴权头 | 跨平台强，但新生态、要重写 |
| PWA（Edge 安装到桌面） | 0 | 高 | `<video>` 原生 | 零安装但非"真 App"，全屏/防误触/家长锁较弱 |
| WinUI3/.NET MAUI（原生 C#） | 中 | 无 | MediaPlayerElement | 最原生但与现有栈完全不同、工作量大 |

**推荐：Tauri**——原生 x64 安装包、包体最小、**直接复用现有 Web 设计稿**作为 UI 层（HTML/JS talking to Worker REST），WebView2 播 H.264 MP4 无压力。

> ⚠️ 待你确认用哪个方案（默认 Tauri）后再进入开发。不同方案 Epic B 的实现差异很大。

## 4. Epics 与 Stories（以 Tauri 方案为例）

### Epic A：脚手架与构建
**目标**：建立 Tauri x64 工程，能出 `.msi`/`.exe`。
- **Story A1 — Tauri 工程初始化**
  - 作为开发者，我想有一个能构建 Windows x64 安装包的 Tauri 工程，以便后续填充功能。
  - **AC**：[ ] `windows/` 目录 Tauri 工程；[ ] `cargo tauri build` 产出 x64 `.msi`；[ ] 启动显示空白主窗口（深色）。

### Epic B：复用 Web UI 实现三大模块 + 播放器
**目标**：把 `designs/child-video-player` 的原型升级为对接真实 Worker API 的功能页面。
- **Story B1 — 激活页**：填服务器地址 + PIN → `/api/activate` → 令牌存本地安全存储。AC：激活成功进首页；失败提示。
- **Story B2 — 首页/分类/我的 三模块**：复刻 Apple 端信息架构（学科金刚区/继续观看/收藏/系列；学科二级；家长 PIN 门）。AC：三模块可切换、拉 `/api/library` 渲染。
- **Story B3 — 播放器**：`<video>` + 自定义控件（播放/进度/倍速/音量/CC/选集/上下集/续播）。AC：能播放、拖动、倍速、断点续播、同系列连播。

### Epic C：后端适配（`<video>` 鉴权）
**目标**：让 HTML `<video>` 能带令牌流式播放（它不能设自定义请求头）。
- **Story C1 — 媒体网关支持 query 令牌**
  - 作为 Web 客户端，我想用 `?t=<令牌>` 流式拉媒体，以便 `<video>` 直接 src 播放并支持 Range。
  - **AC**：[ ] `/media/:id/*?t=<token>` 校验等价于 Authorization 头；[ ] 仍支持 Range/206 + 边缘缓存；[ ] 无令牌仍 401。
  - 改动范围：`worker/src/index.js`（authDevice 兼容 query token）

### Epic D：家长控制与防误触
- **Story D1 — 家长 PIN 门 + 时长/时段**：复用 `/api/rules`；超限进"休息一下"。
- **Story D2 — 全屏 + 防误触/退出锁**：全屏播放；退出/设置需家长手势或 PIN（Windows 上用快捷键 + 确认）。

### Epic E：打包与分发
- **Story E1 — x64 安装包**：产出签名可选的 `.msi`/`.exe`，家长双击安装。AC：在 Windows 10/11 x64 安装运行；首启进激活页。

## 5. 数据 / 接口影响
- 仅 Epic C 一处后端改动：媒体网关接受 `?t=` query 令牌（与现有 Apple 端 Authorization 头并存，向后兼容）。
- 其余复用现有 `/api/*`、manifest、R2，无新表。

## 6. 里程碑 / 优先级
- P0：Epic A（脚手架）、Epic C（query 令牌，Apple 端不受影响）。
- P1：Epic B（三模块+播放器）、Epic D（家长控制）。
- P2：Epic E（安装包打磨、签名）。

## 7. 测试与验收
- 后端：扩展 `tests/e2e-backend.sh` 增加 `?t=` query 令牌的 Range/401 断言。
- 客户端：Windows x64 上手动走查 激活→首页→分类→播放(拖动/倍速/续播)→家长PIN→休息页。
- 两端互不影响：Apple 端回归（现有 E2E 仍 19/0）。

## 8. 待确认（开发前）
1. **技术选型**：默认 Tauri，是否同意？（或选 Electron / Flutter / PWA）
2. 是否需要 Windows 安装包代码签名（需证书，否则首次运行有 SmartScreen 提示）。
