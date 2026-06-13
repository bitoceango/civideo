# child-podcast — 自建儿童视频流媒体

一套**家庭自用**的私有儿童视频流媒体：家长把视频上传到 Cloudflare R2，孩子在原生 Apple App（iPhone / iPad / Mac）里观看。

**为什么自己建**：商业视频平台充斥推荐流、广告和不适合孩子的内容，孩子很容易被无关视频吸引、无法专注。这个项目是一个**封闭内容花园**——孩子端没有搜索、没有外部入口、没有推荐算法，**只能看到家长放进去的内容**。

> 月成本只有 R2 存储费（起步在免费额度内 = $0，约 500GB ≈ $7/月），出口流量永久免费，**无任何年费**（孩子端用 SideStore 免费侧载，不交 Apple Developer $99/年）。

## 架构一览

```
家长下载视频 ──cpv 上传──▶ Cloudflare R2 (私有桶)
                              │  manifest.json = 播放列表单一事实源
                              ▼
                        Cloudflare Worker (鉴权流媒体网关 + D1 进度/规则)
                              │  绑定自有域名（绕开被墙的 *.workers.dev）
                              ▼
                    原生 SwiftUI App (iPhone / iPad / Mac, AVPlayer)
```

- **存储**：R2 按字节计费 + 出口免费（明确否决按时长计费的 Cloudflare Stream）。
- **不转码**：互联网视频多为 H.264/AAC，`cpv` 用 ffprobe 探测，只在必要时重封装/转码。
- **播放**：MP4 渐进式 + HTTP Range，系统 AVPlayer 原生支持，零第三方播放内核。
- **封闭花园**：孩子端无外部内容入口；家长 PIN + 每日时长上限 + 允许时段。

完整设计见 [`docs/architecture.md`](docs/architecture.md)。

## 仓库结构

| 目录 | 内容 |
|---|---|
| `cli/` | 上传 CLI `cpv`（Node + S3 SDK）：探测/转码/上传 R2/维护 manifest。专为 AI 调用设计 |
| `worker/` | Cloudflare Worker：激活、媒体网关（Range）、进度、家长规则 + D1 schema |
| `app/` | SwiftUI 多平台 App（iOS 17+ / macOS 14+，xcodegen 工程） |
| `designs/` | 孩子端 UI 设计原型（可在浏览器打开的 HTML） |
| `docs/` | 架构设计文档 |

## 快速开始

> 私密部署参数（域名 / Account ID / 数据库 ID 等）放在 `deploy.local.json`（已 gitignore，不进仓库）。下面用占位符。

### 1. 后端（Cloudflare）

```bash
cd worker
npm install
cp wrangler.example.jsonc wrangler.jsonc      # 填入你的域名 / bucket
npx wrangler r2 bucket create child-video      # 建 R2 桶（控制台也可）
npx wrangler d1 create child-video-db          # 建 D1，把返回的 database_id 填进 wrangler.jsonc
npx wrangler d1 execute child-video-db --remote --file=./schema.sql
npx wrangler secret put PARENT_PIN             # 设家长 PIN
npx wrangler deploy                            # 部署 + 自动绑定自定义域名
```

### 2. 上传 CLI

```bash
cd cli && npm install
# 配置 R2 S3 凭证（见 cli/README.md），然后：
node src/index.js doctor --json                # 自检 ffmpeg + R2 连通性
node src/index.js upload video.mp4 --title "标题" --series "系列名" --json
```

需要本机 `ffmpeg`（`brew install ffmpeg`）。视频可用 [yt-dlp](https://github.com/yt-dlp/yt-dlp) 从网上下载（见 `docs/architecture.md`）。

### 3. 孩子端 App

```bash
cd app
brew install xcodegen
xcodegen generate
open ChildVideo.xcodeproj
```

首次启动在激活页填入你的 Worker 域名 + 家长 PIN 即可。分发到家庭设备见 [`app/README.md`](app/README.md)（Mac 直接 Run；iPhone/iPad 用免费 Apple ID + SideStore）。

## 隐私与安全

- R2 桶保持**私有**，所有媒体请求经 Worker 校验设备令牌后才返回字节，R2 永不公开直连。
- 家长 PIN 是 Worker secret，R2 密钥是本机环境变量，**都不在仓库里**。
- 仅供家庭内部私密访问，请勿公开分享链接或二次分发受版权保护的内容。

## License

[MIT](LICENSE)
