# child-podcast — 自建儿童视频流媒体

一套**家庭自用**的私有儿童视频流媒体：家长把视频上传到 Cloudflare R2，孩子在原生 Apple App（iPhone / iPad / Mac）里观看。

**为什么自己建**：商业视频平台充斥推荐流、广告和不适合孩子的内容，孩子很容易被无关视频吸引、无法专注。这个项目是一个**封闭内容花园**——孩子端没有外部搜索、没有外部入口、没有推荐算法、没有弹幕/社交，**只能看到家长放进去的内容**。

> 月成本只有 R2 存储费（起步在免费额度内 = $0，约 500GB ≈ $7/月），出口流量永久免费，**无任何年费**（孩子端用 SideStore 免费侧载，不交 Apple Developer $99/年）。

## 架构一览

```
家长下载视频 ──cpv 上传──▶ Cloudflare R2 (私有桶)
                              │  manifest.json = 播放列表单一事实源
                              ▼
                    Cloudflare Worker (鉴权流媒体网关 + 边缘缓存 + D1 进度/规则)
                              │  绑定自有域名（绕开被墙的 *.workers.dev）
                              ▼
                  原生 SwiftUI App (iPhone / iPad / Mac, AVPlayer)
                  首页 / 分类 / 我的 三大模块 + 商业级播放器
```

- **存储**：R2 按字节计费 + 出口免费（明确否决按时长计费的 Cloudflare Stream）。
- **不转码**：互联网视频多为 H.264/AAC，`cpv` 用 ffprobe 探测，只在必要时重封装/转码。
- **播放**：MP4 渐进式 + HTTP Range，系统 AVPlayer 原生支持，零第三方播放内核。
- **边缘缓存**：Worker 用免费 Cache API（按 R2 etag 作键，覆盖视频自动失效），降起播延迟。
- **封闭花园**：孩子端无外部内容入口；家长 PIN + 每日时长上限 + 允许时段 + 护眼提醒。

完整设计见 [`docs/architecture.md`](docs/architecture.md)。

## 功能

**孩子端 App（三大模块）**
- 🏠 **首页**：学科金刚区 + 继续观看 + 我喜欢的 + 系列聚合（横排预览，多集进竖向网格）。自动刷新，新上传的视频自动出现。
- 📚 **分类**：按「学科/能力」（科学/英语/数理/国学/艺术…）二级浏览，无热度榜。
- 👤 **我的**：家长 PIN 门 → 每日时长 / 允许时段 / 护眼提醒 / 学习报告（今日·本周）/ 设备管理。

**播放器（对齐商业流媒体）**
- 播放/暂停、进度拖动 + 缓冲、±10 秒、倍速（0.75–1.5，儿童克制档）、播完重播
- 音量滑块 + 静音、CC 字幕开关（内嵌字幕轨）、选集面板、上一集/下一集、同系列自动连播、断点续播、收藏
- AirPlay 投屏、Now Playing 锁屏/控制中心/耳机线控
- 防误触锁定（长按解锁）、护眼休息提醒

> 有意**不做**（违背封闭专注理念）：算法推荐流、弹幕、评论/社交、热度榜、外链、电商/会员、UGC 上传。

## 仓库结构

| 目录 | 内容 |
|---|---|
| `cli/` | 上传 CLI `cpv`（Node + S3 SDK）：探测/转码/上传 R2/维护 manifest。专为 AI 调用设计。含 `import-youtube.sh` 一键导入 |
| `worker/` | Cloudflare Worker：激活、媒体网关（Range + 边缘缓存）、进度、家长规则 + D1 schema |
| `app/` | SwiftUI 多平台 App（iOS 17+ / macOS 14+，xcodegen 工程），含图标生成脚本 |
| `tests/` | `e2e-backend.sh` 端到端后端验收测试（curl 断言，带退出码） |
| `docs/` | 架构设计 + `requirements/`（需求文档：PRD/Epic/Story、验收与测试计划） |
| `designs/` | 孩子端 UI 设计原型（可在浏览器打开的 HTML） |

## ⚠️ 开发流程（硬性规则）

任何新需求/功能/改动，**必须先有需求文档（`docs/requirements/`，含 Epic 与 Story）→ 按 Story 建 GitHub issue → 再开发 → 提交关联 issue**。详见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。没有需求文档和 issue，不写代码。

## 快速开始

> 私密部署参数（域名 / Account ID / 数据库 ID 等）放在 `deploy.local.json`（已 gitignore，不进仓库）。下面用占位符。

### 1. 后端（Cloudflare）

先 `npx wrangler login`（浏览器登录，首次必需）。然后**一键部署**（推荐）——自动建 R2 桶 / 建 D1 并写回 id / 迁移表 / 设密钥 / 部署，只问你域名和密钥：

```bash
cd worker
npm install
npm run setup       # 默认免费 *.workers.dev（零域名）；过程中可选绑定自定义域名
```

> 💡 `*.workers.dev` 在中国大陆可能被墙；需要稳定访问时按提示绑定自定义域名（需已托管在 Cloudflare）。

<details><summary>或手动逐步</summary>

```bash
cd worker
npm install
cp wrangler.example.jsonc wrangler.jsonc       # 默认 workers.dev；要自定义域名改这里
npx wrangler r2 bucket create child-video       # 建 R2 桶
npx wrangler d1 create child-video-db           # 建 D1，把返回的 database_id 填进 wrangler.jsonc
npx wrangler d1 execute child-video-db --remote --file=./schema.sql
npx wrangler secret put ACTIVATION_KEY          # 设备激活密钥：长随机串（openssl rand -hex 24）；不设则回退用 PARENT_PIN
npx wrangler secret put PARENT_PIN              # 家长门 PIN：改每日时长/允许时段规则用，可短数字
npx wrangler deploy
```
</details>

### 2. 上传 CLI

```bash
cd cli && npm install
# 配置 R2 S3 凭证（见 cli/README.md），然后：
node src/index.js doctor --json                # 自检 ffmpeg + R2 连通性
node src/index.js upload video.mp4 --title "标题" --series "系列名" --category "科学" --json
```

需要本机 `ffmpeg`（`brew install ffmpeg`）。

**从 YouTube 批量导入**（在你自己的 Mac / 家庭网络上跑，数据中心 IP 会被 YouTube 拦）：
```bash
brew install yt-dlp ffmpeg
bash cli/import-youtube.sh "<播放列表URL>" "动物兄弟 第五季" "科学"   # 下载720p+中文字幕 → 自动逐个上传
```

### 3. 孩子端 App

```bash
cd app
brew install xcodegen
xcodegen generate
open ChildVideo.xcodeproj
```

首次启动在激活页填入你的 Worker 域名 + 家长 PIN 即可。分发到家庭设备见 [`app/README.md`](app/README.md)（Mac 直接 Run；iPhone/iPad 用免费 Apple ID + SideStore）。

## 测试

```bash
source ~/.zshrc
PIN=<你的PIN> bash tests/e2e-backend.sh        # 端到端后端验收，退出码 0=全过
```
覆盖：健康检查 / 鉴权 401 / PIN 403 / 激活 / 拉库 / 媒体 Range 206 / 边缘缓存 HIT / 进度读写 / 家长规则 / 超时段·超时长拦截 / 本周报告。验收清单见 [`docs/requirements/002-acceptance-e2e.md`](docs/requirements/002-acceptance-e2e.md)。

## 隐私与安全

- R2 桶保持**私有**，所有媒体请求经 Worker 校验设备令牌后才返回字节，R2 永不公开直连。
- 家长 PIN 是 Worker secret，R2 密钥是本机环境变量，孩子姓名等**都不在仓库里**（放本地 `deploy.local.json`）。
- **激活防爆破**（issue #16）：`/api/activate` 内置限流——同一 IP 连续失败 5 次即锁定 15 分钟（返回 `429`），计数持久化在 D1；可用环境变量 `MAX_ACTIVATION_FAILS` / `ACTIVATION_LOCK_MIN` 调整。⚠️ 自定义域名会进公开的 Certificate Transparency 日志（**域名不是秘密**），安全只靠 **PIN 强度 + 限流**，请设强 PIN。（升级老部署需重跑 `schema.sql` 以建 `activation_attempts` 表。）
- **零代码加固**（可选，推荐叠加）：Cloudflare 控制台 → Security → WAF → Rate limiting rules，对表达式 `http.request.uri.path eq "/api/activate"` 设「每 IP 每分钟 ≤ 5 次，超出 Block」。
- R2 出口免费 = 没有带宽账单可被「盗刷」。
- 仅供家庭内部私密访问，请勿公开分享链接或二次分发受版权保护的内容。

## License

[MIT](LICENSE)
