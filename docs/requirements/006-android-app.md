# 需求文档：Android App（Tauri 复用 Web UI 出 APK）

> 编号：006 ｜ 状态：草稿（待评审）
> 创建日期：2026-06-14 ｜ 关联：`003-windows-app.md`（Tauri/Web UI 同源）、`003-ebook-to-podcast.md`（听书）、`CLAUDE.md`「三端同时实现」规则

## 1. 背景与目标
项目新增硬性规则：**功能须 Apple + Windows + Android 三端同时实现**（见 `CLAUDE.md`）。当前 Android 端**完全空白**（仓库只有 `app/`=SwiftUI、`windows/`=Tauri）。家里有 Android 手机/平板，孩子也要能在上面看视频、听书。

**核心目标**：用 **Tauri v2 的 Android target**，**复用 `windows/src` 那套现成 Web UI**（`app.js`/`api.js`/`styles.css`），打出 **Android APK**，功能与 Windows 对齐（首页/分类/听书/我的 + 视频播放器 + 音频播放器 + 家长控制），家长侧载安装即用。后端零改动（继续用现成 Worker API）。

## 2. 范围
- **本次要做（In scope）**：
  - 新建 `android/` Tauri 工程，**前端复用 `windows/src`**（单一事实源，不复制一份）。
  - Tauri v2 mobile 配置（`tauri.conf.json`）、Android 图标、**网络权限**（INTERNET）。
  - **移动端适配**：进度条拖动支持 **touch 事件**（现 Web 用 mouse 事件）、点触显隐控件、竖屏/安全区布局、视口缩放。
  - **CI 出 APK**：`android-build.yml` 在 runner 上装 Android SDK/NDK + Rust(android targets) + JDK，`tauri android init` + `tauri android build --apk`，上传 APK 工件。
  - 顺手统一三端**激活文案**：Windows/Android 激活框「家长密码」→「激活密码（家长密码）」，与 Apple 端一致（修 #17 遗留的误导文案）。
- **本次不做（Out of scope，列后续）**：
  - Google Play 上架、应用内更新、推送通知。
  - 原生 Kotlin 重写（明确走 Tauri 复用 Web UI）。
  - 正式签名密钥托管（先出 **debug 签名/未签名 APK**，家长手动开「允许安装未知来源」装；正式签名后续）。
  - iOS 用 Tauri（Apple 端继续用 SwiftUI，不重复）。

## 3. 设计原则 / 约束
- **Web UI 单一事实源**：Windows 与 Android 共用 `windows/src`，改一处两端同步；**不复制代码**。
- **不动现有 Windows 工程**：Android 独立 `android/`，引用同一份 Web UI，零回归风险。
- **封闭花园**：与 001 一致，无外链/推荐/电商。
- **复用后端**：Worker `/api/library`、`/media/*`、`/api/activate`、`?t=` 令牌全部复用，**无后端改动**。
- **为 AI/CI 出包设计**：APK 由 CI 产出（开发者不手装 Android 工具链），工件可下载侧载。
- **家庭量级**：不过度设计；未签名/ debug 包 + 侧载即可。

## 4. Epics 与 Stories

### Epic AN-A：Android Tauri 工程脚手架（复用 Web UI）
**目标**：有一个能初始化、能引用现成 Web UI 的 Tauri Android 工程。
**范围**：新增 `android/`（`src-tauri/` + 配置），`frontendDist` 指向 `windows/src`。

- **Story AN-A1 — 工程与配置**
  - **AC**：[ ] 新建 `android/src-tauri`（Cargo、`tauri.conf.json`、`build.rs`、`lib.rs`/`main.rs`、图标）；[ ] 前端复用 `windows/src`（不复制）；[ ] identifier/productName 与品牌一致（`儿童视频`）；[ ] 声明 INTERNET 权限。

### Epic AN-B：移动端适配（触屏 + 布局）
**目标**：现成 Web UI 在手机触屏上好用。
**范围**：`windows/src/app.js`、`styles.css`（**三端共用，改动对 Windows 向后兼容**）。

- **Story AN-B1 — 触屏交互**
  - 作为孩子，我想在手机上**拖动进度条**、点击显隐控件。
  - **AC**：[ ] 进度条拖动同时支持 `touch`（pointer 事件统一）；[ ] 点触显隐播放控件；[ ] 选集/章节面板触屏可点。改动不破坏 Windows 鼠标交互。
- **Story AN-B2 — 竖屏与安全区**
  - **AC**：[ ] 竖屏布局正常（金刚区/海报/书架不溢出）；[ ] 适配状态栏/安全区（`viewport-fit=cover` + `env(safe-area-inset-*)`）；[ ] 视口 `user-scalable=no`。

### Epic AN-C：CI 出 APK
**目标**：合并即由 CI 产出可侧载的 APK 工件。
**范围**：`.github/workflows/android-build.yml`。

- **Story AN-C1 — Android 构建工作流**
  - **AC**：[ ] runner 装 JDK + Android SDK/NDK + Rust(aarch64/armv7/x86_64-linux-android targets)；[ ] `tauri android init` + `tauri android build --apk`；[ ] 上传 `childvideo-android` APK 工件；[ ] 路径过滤 `android/**`、`windows/src/**`、本 workflow；可 `workflow_dispatch`。

### Epic AN-D：三端激活文案统一（顺手修）
**目标**：消除「家长密码」误导（激活其实用 ACTIVATION_KEY）。
**范围**：`windows/src/app.js`（Android 共用）；Apple 端已改，核对一致。

- **Story AN-D1 — 文案**
  - **AC**：[ ] 激活框 placeholder/标签改「激活密码（家长密码）」或「激活密钥」；[ ] 不改逻辑（仍发 `pin` 字段，Worker 比对 `ACTIVATION_KEY`）。

## 5. 数据 / 接口影响
- **无后端改动**：复用现成 Worker（`/api/library`、`/media/*`、`/api/activate`、`?t=` 令牌、`/api/progress`、`/api/rules`）。
- **新增目录**：`android/`（Tauri 工程）；`.github/workflows/android-build.yml`。
- **共用前端**：`windows/src` 成为 Windows + Android 共享前端（AN-B 的触屏改动对 Windows 向后兼容）。

## 6. 里程碑 / 优先级
- **P0**：AN-A（脚手架）+ AN-C（CI 出 APK）——先打通「能出一个能装的 APK」。
- **P1**：AN-B（触屏/竖屏适配）——让它在手机上真好用；AN-D（文案统一）。
- **P2**：正式签名、Google Play、推送。

## 7. 测试与验收总览
- **构建**：`android-build.yml` 跑绿，产出 `childvideo-android` APK 工件。
- **端到端**：APK 装到 Android 机 → 激活（服务器地址 + 激活密码 `loveson_520`）→ 首页出视频、听书 Tab 出 2 本书 → 视频能放、章节能听。
- **触屏**：进度条能拖、控件点触显隐、选集/章节面板可点（手机实测，或 Android 模拟器）。
- **回归**：Windows 构建仍绿、鼠标交互不受 AN-B 改动影响。
- **三端对齐**：功能集与 Windows 一致；激活文案三端统一。
