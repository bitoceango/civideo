# GOAL：自建儿童视频流媒体（child-video）

> 这是一份自包含的开发目标说明。执行者读完即可独立完成剩余开发，无需追溯历史对话。
> 所有架构细节见 `docs/architecture.md`；CLI 用法见 `cli/README.md` 和根 `CLAUDE.md`。

## 1. 一句话目标

为自己的孩子做一个**私有、封闭**的视频流媒体：家长把从互联网下载的视频，通过 AI 调用 `cpv` CLI 上传到 Cloudflare R2；孩子在原生 Apple App（iPhone/iPad/Mac）里**只能看到家长放进去的内容**，没有推荐流、没有外部入口、没有广告，让孩子专注于学习视频本身。

## 2. 为什么这么做（约束的来源）

- **封闭花园**：商业平台的推荐和无关内容会让孩子分心。客户端必须没有任何"通往外部世界"的入口（无外部搜索、无浏览器、无推荐算法）。
- **成本极低**：家庭自用，观众 1–3 人。选 R2（按字节计费 + 出口流量免费），否决按时长计费的 Cloudflare Stream。起步在免费额度内 $0，500GB 约 $7/月。
- **零年费分发**：不交 Apple Developer $99/年，用 SideStore 免费侧载。
- **AI 驱动上传**：家长不手动操作，让 AI 调 `cpv upload` 完成入库。

## 3. 已完成（不要重做）

| 模块 | 状态 | 位置 |
|---|---|---|
| 架构设计 | ✅ v0.6 | `docs/architecture.md` |
| 上传 CLI `cpv` | ✅ 已实现并端到端验证 | `cli/`（Node + @aws-sdk/client-s3） |
| R2 bucket | ✅ 已建 `child-video`（APAC） | Cloudflare 账号 |
| R2 API 凭证 | ✅ 已配在 `~/.zshrc`，`cpv doctor` 全绿 | 环境变量 |
| wrangler 授权 | ✅ 已 `wrangler login` | OAuth |
| Worker 代码 | ✅ 已写好（未部署） | `worker/src/index.js` + `schema.sql` + `wrangler.jsonc` |
| D1 数据库 | ✅ 已创建 `child-video-db` | database_id 已写入 wrangler.jsonc |
| 端到端上传 | ✅ 已验证 | — |
| Worker 部署 | ✅ 已上线 `https://video.example.com`（含 rules / watchedSec 端点） | worker/ |
| SwiftUI App（iOS+macOS） | ✅ 已实现并双端构建通过 | app/ |
| 端到端验收 | ✅ 5 屏在真机模拟器跑通（激活/库/播放/休息/家长）+ 全 API 验证 | — |

### 关键固定值（直接用，勿改）

- Cloudflare Account ID：`<YOUR_CLOUDFLARE_ACCOUNT_ID>`
- R2 bucket：`child-video`（Asia-Pacific）
- D1：`child-video-db`，database_id `<YOUR_D1_DATABASE_ID>`
- Worker 名：`child-video-api`
- **部署域名：`video.example.com`**（该域名已托管在用户 Cloudflare 账号，Active）
  —— 绝不用 `*.workers.dev`，它在中国大陆无法直连。
- 本机：macOS、Xcode 26.3、ffmpeg 8.1、node 25。`cpv` 需 `source ~/.zshrc` 才有 R2 环境变量（非交互 shell 不自动加载）。

## 4. 待完成的任务（按顺序）

### Task A — 部署后端 Worker

1. `cd worker`，执行 D1 schema：
   `npx wrangler d1 execute child-video-db --remote --file=./schema.sql`
2. 设家长 PIN（用户自定 4–6 位）：
   `npx wrangler secret put PARENT_PIN`
3. 部署：`npx wrangler deploy`（会自动在 zone `example.com` 下创建自定义域名 `video.example.com`）
4. **验收**：
   - `curl https://video.example.com/api/health` → `{"ok":true}`
   - 无令牌 `curl .../api/library` → 401
   - `POST /api/activate {"pin":"<PIN>","name":"test"}` → 返回 `token`
   - 带 `Authorization: Bearer <token>` 请求 `/api/library` → 看到 `e2etest01`
   - 带令牌 `curl -H "Range: bytes=0-1023" .../media/e2etest01/video.mp4` → 206 + Content-Range
   - 全部通过后，用 `cpv remove e2etest01` 清理测试视频。

### Task B — SwiftUI 多平台 App（孩子端）

一个 Xcode 多平台 target（iOS 17+ / macOS 14+），SwiftUI + AVKit。目录建议 `app/`。

**首次激活流程**：App 第一次启动 → 家长输入服务器地址（预填 `https://video.example.com`）+ PIN → 调 `/api/activate` → 把返回的 token 存进 **Keychain** → 之后进入孩子模式。

**孩子主界面**：
- 调 `/api/library`，按 `series` 分组展示**大封面网格**（封面图走 `/media/:id/poster.jpg`，请求带 Bearer token——用 `AVURLAsset` 的 `AVURLAssetHTTPHeaderFieldsKey` 或 URLSession 自定义头）。
- 无文字搜索框、无设置入口暴露在主界面（学龄前不识字）。
- 点封面 → 全屏 AVPlayer 播放 `/media/:id/video.mp4`（带 token 头）。AVPlayer 原生支持 H.264 MP4 + Range。
- **断点续播**：进入播放时 GET `/api/progress` 拿到上次位置 seek 过去；播放中定时（如每 10s）POST `/api/progress`（带 `videoId`、`positionSec`、`day`=设备本地 YYYY-MM-DD、`deltaSec`、`minuteOfDay`）。
- 播完自动播**同系列**下一集（不跨系列、不推荐）。

**家长控制**：
- 退出孩子模式 / 进入设置：藏在**长按 + 再次输入 PIN**之后（防孩子误触退出）。
- 响应后端的拦截信号：POST `/api/progress` 返回 `blocked` 字段为 `outside_allowed_hours` 或 `daily_limit_reached` 时，暂停播放并显示友好的"休息一下"页面。
- iOS/iPadOS 上提示家长可配合系统**引导式访问**把孩子锁在 App 内。

**鉴权细节**：所有媒体和 API 请求都必须带 `Authorization: Bearer <keychain 中的 token>`。token 无效（401）时回到激活页。

**验收**：在开发机 iOS 模拟器 + Mac 上能激活、看到测试视频网格、点击全屏播放、关闭重开能续播。

### Task C — SideStore 分发（装到家庭设备）

- Mac：直接 Xcode 本地构建运行（ad-hoc 签名，永久免费）。
- iPhone/iPad：用免费 Apple ID 在 Xcode 里签名导出 .ipa，通过 **SideStore** 安装并自动续签（初次需电脑配对一次）。
- 写一份 `app/SIDELOAD.md` 记录给家里每台设备装机的步骤。

### Task D（可选，后续）

- 家长管理台网页（Pages）：可视化排序/删除/配时长规则（目前这些靠直接改 manifest.json + D1）。
- 离线下载、tvOS（Apple TV）、音频内容支持。

## 5. 数据契约（前后端对齐用）

**manifest.json**（R2 根部，`cpv` 维护，Worker `/api/library` 读后追加 `videoUrl`/`posterUrl`）：
```json
{ "version": 1, "updatedAt": "ISO", "videos": [
  { "id": "v..", "title": "..", "series": ".."|null, "durationSec": 0,
    "width": 0, "height": 0, "sizeBytes": 0,
    "video": "videos/<id>/video.mp4", "poster": "videos/<id>/poster.jpg",
    "createdAt": "ISO", "updatedAt": "ISO" } ] }
```

**Worker API**：
- `POST /api/activate` body `{pin, name?}` → `{ok, deviceId, token}`（token 仅此一次返回）
- `GET /api/library`（Bearer）→ `{version, updatedAt, videos:[...,videoUrl,posterUrl]}`
- `GET /media/:id/video.mp4|poster.jpg`（Bearer，支持 Range）→ 200/206 流
- `GET /api/progress`（Bearer）→ `{ok, progress:{videoId:positionSec}, rules}`
- `POST /api/progress`（Bearer）body `{videoId, positionSec, day?, deltaSec?, minuteOfDay?}` → `{ok, blocked, watchedSec}`

## 6. 不要做的事（已明确否决）

- ❌ 不用 Cloudflare Stream（按分钟计费，大库小观众场景 $175+/月）
- ❌ 不用 HLS 切片（家庭场景无 ABR 需求；用 MP4 渐进式 + Range）
- ❌ 不交 Apple Developer $99/年（用 SideStore）
- ❌ 不用 `*.workers.dev`（国内被墙）
- ❌ 客户端不加任何外部内容入口（搜索外网/浏览器/推荐）
- ❌ 入库不做无谓转码（互联网视频多为 H.264/AAC，`cpv` 自动只在必要时转码）

## 7. 完成的定义（Definition of Done）

家长能用 AI 跑 `cpv upload` 把视频传上去；孩子在家里的 iPhone/iPad/Mac 上打开 App，看到这些视频的封面网格，点击即全屏播放，能续播，看不到任何外部内容；超时段/超时长会被温和拦截；整套月成本仅 R2 存储费（起步 $0），无年费。
