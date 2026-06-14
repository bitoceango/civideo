# 需求文档：开发者模式（家长自助上传，桌面端）

> 编号：007 ｜ 状态：草稿（待评审）
> 创建日期：2026-06-14 ｜ 关联：`003-windows-app.md`、`006-android-app.md`、`docs/architecture.md`、CLAUDE.md「三端同时实现」规则（本功能为合理例外，见 §3）

## 1. 背景与目标
现在上传视频只能开发者在电脑上调 `cpv` CLI。家长（如配偶）希望**自己**往库里加视频——既能**上传本地视频文件**，也能**从网址（含 YouTube）下载**后入库，全程不碰命令行。

**核心目标**：在**桌面端播放器（Windows / macOS）**里加一个**「开发者模式 / 家长上传」**入口（**藏在家长 PIN 门后**，孩子端无感），把 `yt-dlp` + `ffmpeg` 工具**随 App 捆绑**，在家长本机完成「下载 / 探测 / 转码 / 截图」，再**预签名直传 R2 + 经 Worker 写 manifest**，刷新即出现在所有设备。

## 2. 范围
- **本次要做（In scope）**：
  - **Windows + macOS** 播放器内「开发者模式」（家长 PIN 门后）。
  - **本地文件上传**：选 mp4（或其它 ffmpeg 可读格式）→ 探测/必要时转码 H.264/AAC mp4 → 截首帧海报 → 直传 R2 → 写 manifest。
  - **网址下载**：粘贴链接（**YouTube / Bilibili 等 yt-dlp 支持的站点**）→ 捆绑的 `yt-dlp` 本机下载 → 同上流程入库。
  - **登录态 / 会员内容**：支持 `--cookies-from-browser`（家长在本机浏览器登录 B 站/YouTube 后自动读 cookies）或粘贴 cookies，从而下载**大会员清晰度 / VIP 专享 / 已购内容**（用家长自己的账号权限，不破解付费墙；无权限的下不了）。cookies **只在本机使用，不上传、不入库**。
  - **工具捆绑**：`yt-dlp` + `ffmpeg` 作为 sidecar 随包分发（Windows Tauri sidecar；macOS SwiftUI 内置二进制）。
  - **R2 写入走预签名**：R2 密钥只在 Worker；App 向 Worker（PIN 鉴权）换**短时效预签名 PUT URL** 直传 R2，再请求 Worker 追加 manifest 条目。**App 内不存任何长期密钥。**
  - 复用现有 `cpv` 的处理逻辑（探测/重封装/转码判定/海报）思路。
- **本次不做（Out of scope）**：
  - **Android / iOS 上传**（无法捆 yt-dlp/ffmpeg；上传是家长桌面功能，移动端保持纯看——见 §3）。
  - 批量队列管理、断点续传、上传进度持久化（先单条、简单进度）。
  - 删除/编辑已有视频的完整管理后台（可后续；本次聚焦"加"）。
  - 把 R2 长期密钥打进 App（明确否决，开源+可拆包）。

## 3. 设计原则 / 约束
- **封闭花园不破**：上传入口**必须在家长 PIN 门后**，孩子端默认完全看不到。
- **「三端同时实现」的合理例外**：上传是**家长侧管理功能**、且依赖只有桌面才有的工具链，故**仅 Windows/macOS**；Android/iOS 维持纯消费端。此例外写入本文档备案。
- **密钥不入 App / 不入库**：R2 密钥仅在 Worker secrets；App 走预签名。仓库零密钥。
- **本机处理**：下载/转码/截图在家长电脑跑（捆绑工具），Worker 不跑 ffmpeg/yt-dlp。
- **复用单一事实源**：仍写同一个 `manifest.json`；播放端无需改。
- **家庭量级**：单条上传、简单进度即可，不过度设计。

## 4. Epics 与 Stories

### Epic UP-A：Worker 管理接口（PIN 鉴权）
**目标**：让桌面 App 能安全地把处理好的视频写入 R2 与 manifest。
**范围**：`worker/src/index.js`、Worker secrets（R2 S3 凭据）。

- **Story UP-A1 — 预签名上传 URL**
  - **AC**：[ ] `POST /api/admin/upload-url`（PIN 鉴权）入参 {ext/contentType}，返回新 `id` + 视频/海报两个 **R2 预签名 PUT URL**（短时效）；[ ] R2 S3 凭据存 Worker secrets，用 Web Crypto 做 AWS SigV4 预签名。
- **Story UP-A2 — 写 manifest**
  - **AC**：[ ] `POST /api/admin/manifest-add`（PIN 鉴权）入参 {id,title,series,category,durationSec,width,height,sizeBytes} → 读-改-写 `manifest.json`（追加/覆盖同 id）；[ ] 与 `cpv` 写出的结构一致。
- **Story UP-A3 — 限流/鉴权复用**
  - **AC**：[ ] 复用激活那套失败限流；[ ] 非家长 PIN 一律 403。

### Epic UP-B：桌面工具捆绑（sidecar）
**目标**：App 自带 `yt-dlp` + `ffmpeg`，离线即可处理。
**范围**：Windows `windows/src-tauri`（Tauri sidecar/shell）；macOS `app/`（.app 内置二进制 + `Process`）；CI 拉二进制。

- **Story UP-B1 — Windows sidecar**
  - **AC**：[ ] `yt-dlp.exe` + `ffmpeg.exe` 作为 Tauri sidecar 打进安装包；[ ] 前端经 Tauri 命令调用。
- **Story UP-B2 — macOS 内置二进制**
  - **AC**：[ ] `yt-dlp` + `ffmpeg`（arm64/универ）内置进 `.app/Contents/Resources`；[ ] SwiftUI 经 `Process` 调用。
- **Story UP-B3 — CI 取二进制**
  - **AC**：[ ] 构建时下载对应平台的 yt-dlp/ffmpeg 放入打包位置（不入仓库）。

### Epic UP-C：Windows 开发者模式 UI + 流程
**目标**：Windows 家长能本地传 / 网址下载入库。
**范围**：`windows/src`（家长中心加入口）、`windows/src-tauri`（Rust 命令：调 sidecar、读文件、PUT R2、调 Worker）。

- **Story UP-C1 — 入口与表单**
  - **AC**：[ ] 家长中心（PIN 后）加「上传视频」；[ ] 两种来源：本地文件选择 / 粘贴网址；[ ] 填 标题/系列/分类。
- **Story UP-C2 — 处理与上传流水线**
  - **AC**：[ ] 网址→yt-dlp 下载；[ ] ffprobe 探测，必要时转码 H.264/AAC mp4；[ ] ffmpeg 截首帧海报；[ ] 向 Worker 取预签名 → 直传视频+海报 → 调 manifest-add；[ ] 进度与成功/失败反馈；[ ] 完成后库内可见。

### Epic UP-D：macOS 开发者模式 UI + 流程
**目标**：macOS（SwiftUI）家长同样能传。
**范围**：`app/`（SwiftUI 上传视图 + 调用内置二进制 + URLSession 直传）。

- **Story UP-D1 — 入口与表单**：[ ] 家长门后「上传视频」视图（本地文件 / 网址 + 元数据）。
- **Story UP-D2 — 处理与上传流水线**：[ ] 调内置 yt-dlp/ffmpeg → 探测/转码/海报 → 取预签名 → URLSession 直传 → manifest-add → 库内可见。

## 5. 数据 / 接口影响
- **Worker**：新增 `/api/admin/upload-url`、`/api/admin/manifest-add`（均 PIN 鉴权）；新增 secrets：R2 S3 `access key id` / `secret`（+ account id / bucket，可复用 vars）。
- **R2**：可能需配 **CORS**（允许 App 来源直传 PUT）；或由 Tauri Rust / SwiftUI 原生发起 PUT 规避浏览器 CORS。
- **manifest.json**：结构不变（沿用 `videos[]`）。
- **App 分发**：桌面包体增大（含 yt-dlp/ffmpeg，约 +100MB）。
- **播放端**：无改动。

## 6. 里程碑 / 优先级
- **P0**：UP-A（Worker 接口）+ UP-B1/UP-C（Windows 全链路：**本地文件上传**优先打通，再加网址下载）——媳妇在 Windows，先让她能用。
- **P1**：UP-D（macOS）+ UP-B2。
- **P2**：删除/管理、批量、断点续传、上传进度持久化。

## 7. 测试与验收总览
- **后端**：`upload-url`/`manifest-add` 非 PIN→403；PIN 正确→拿到预签名、能 PUT、manifest 追加成功（e2e 脚本加断言）。
- **Windows 端到端**：家长门→上传本地 mp4→库内出现可播放；粘贴 YouTube 链接→下载→入库可播放。
- **macOS 端到端**：同上。
- **安全**：App 包内**无任何 R2 长期密钥**（拆包核验）；孩子端无上传入口。
- **回归**：播放/听书不受影响；Windows/Android 构建仍绿。
