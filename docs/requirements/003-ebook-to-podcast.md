# 需求文档：电子书 → 播客（听书）

> 编号：003 ｜ 状态：草稿（待评审）
> 创建日期：2026-06-13 ｜ 关联：`docs/architecture.md`、001（三大模块重构，听书作为新分类接入）、火山豆包 seed-tts-2.0 接入（已实测打通）

## 1. 背景与目标
家长手里有不少适合孩子的电子书（绘本、故事、国学、科普）。希望把电子书**转成音频「听书」**，让孩子在现有封闭播放器里**收听**——既能护眼（不盯屏），又能利用碎片/睡前时间。

复用现有成熟链路：**家长（AI 调 CLI）本地处理 → 上传 Cloudflare R2 → 更新 `manifest.json` → Worker 网关 → 孩子端 App**。中文语音用**豆包 seed-tts-2.0**（童声自然、单本成本几毛钱，已联调成功）。

**核心目标**：用一条命令把一本电子书变成可在 App 里收听的「听书」，每章一集；中文童声、封闭、可家长管控。

## 2. 范围
- **本次要做（In scope）**：
  - CLI 新命令 `cpv audiobook <电子书>`：解析→按章 TTS 合成→上传 R2→写入 manifest。
  - 电子书解析：**EPUB（P0）**、**TXT/Markdown（P1）**，按章节切分 + 文本清洗/分段。
  - TTS 引擎：豆包 seed-tts-2.0（**接口化、可插拔**，便于日后换/兜底）。
  - manifest 增 `audiobooks` 数据模型；`list`/`remove`/`doctor` 支持听书。
  - App「听书」分类入口、章节列表、**音频播放器**（无视频画面）、续听/收藏。
  - Worker `/api/library` 透传 `audiobooks`。
- **本次不做（Out of scope，列后续）**：
  - **PDF**（排版复杂、文字提取易错，后续单开）。
  - 本地离线 TTS 兜底引擎（接口已留，后续接）。
  - 声音复刻 / 自定义音色、多音色对话演播。
  - 逐句字幕高亮 / 跟读、AB 复读、背景音乐/音效。
  - 锁屏/后台播放控制的精细打磨（基础可放后续）。

## 3. 设计原则 / 约束
- **封闭花园**：无外链、无推荐流、无社交/评论、无电商，与 001 一致。
- **复用现有架构**：CLI 做重活；manifest 为单一事实源；密钥**绝不入库**（走环境变量 / `deploy.local.json`）。
- **串行处理**：manifest 整文件读-改-写，批量/多本严格串行（同既有上传约定）。
- **为 AI 调用设计**：非交互、`--json` 输出、明确退出码（沿用 0/1/2/3，TTS 缺密钥归入「缺配置」语义）。
- **家庭量级**：不过度设计；章节即「集」，进度/收藏复用现有机制。
- **成本可控**：儿童读物字数少，豆包按字计费单本几毛；`--dry-run` 先预览章节与字数/时长估算再合成。

## 4. Epics 与 Stories

### Epic A：TTS 引擎（豆包 seed-tts-2.0 接入）
**目标**：在 cli 提供稳定的「文本 → 音频」能力，并接口化以便替换/兜底。
**范围**：新增 `cli/src/tts.js`、`cli/src/config.js`（增 TTS 密钥）、`cli/src/index.js`（doctor）。

- **Story A1 — 豆包 TTS 客户端模块**
  - 作为开发者，我想有 `synthesize(text, opts) -> mp3 Buffer`，封装 seed-tts-2.0 的 WebSocket 二进制事件协议，以便上层无脑调用。
  - **AC**：
    - [ ] WS `wss://openspeech.bytedance.com/api/v3/tts/bidirection`，鉴权用**新版控制台单头 `X-Api-Key`** + `X-Api-Resource-Id: seed-tts-2.0`。
    - [ ] 完整事件流（StartConnection→StartSession→TaskRequest→FinishSession），累加 AudioServer 帧得到 mp3。
    - [ ] 长文本**分段合成并拼接**（单段限长，避免超时/超限）。
    - [ ] 失败重试（指数退避，N 次）与**清晰错误**（区分鉴权失败 / 资源未授权 / 网络）。
    - [ ] 密钥读环境变量 `DOUBAO_TTS_API_KEY`，**不入库**。
  - 改动范围：`cli/src/tts.js`、`config.js`　｜　依赖：`ws` npm 包
- **Story A2 — 可插拔 TTS 接口 + doctor 检查**
  - 作为开发者，我想 TTS 走统一 `engine` 接口，以便将来加本地/其他引擎；并能体检连通性。
  - **AC**：
    - [ ] `--tts <engine>`（默认 `doubao`），接口签名稳定。
    - [ ] 未配置 `DOUBAO_TTS_API_KEY` 时给明确错误与退出码（缺配置）。
    - [ ] `cpv doctor` 增「TTS 连通性」检查项（一小段试合成或鉴权探测）。
  - 改动范围：`cli/src/index.js`、`tts.js`

### Epic B：电子书解析（章节切分 + 文本清洗）
**目标**：把电子书读成有序「章节列表（标题 + 纯文本）」+ 书籍元数据。
**范围**：新增 `cli/src/ebook.js`。

- **Story B1 — EPUB 解析（P0）**
  - 作为家长，我想上传 EPUB 自动按章节切分，以便每章成为一「集」。
  - **AC**：[ ] 解析 EPUB（spine/toc）得到**有序章节**；[ ] 每章提取**纯文本**（去 HTML/样式）；[ ] 取书名/作者/封面；[ ] 取章节标题（无则「第 N 章」）。
  - 改动范围：`cli/src/ebook.js`　｜　依赖：EPUB 解析库（如解 zip + XHTML）
- **Story B2 — TXT / Markdown 解析（P1）**
  - 作为家长，我想上传纯文本也能按规则切章。
  - **AC**：[ ] 按标题行/分隔符/字数切章；[ ] 无结构时按长度均匀分段；[ ] 首行/文件名兜底为书名。
- **Story B3 — 文本清洗与 TTS 友好分段（P0）**
  - 作为开发者，我想把章节文本清洗并切成适合 TTS 的小段，以便合成稳定、语音自然。
  - **AC**：[ ] 去页眉页脚/多余空白/控制字符；[ ] 长章节按句子边界切成 ≤N 字的小段；[ ] 段落停顿合理（句末/换行）。

### Epic C：CLI 命令 `audiobook`（端到端：电子书→R2→manifest）
**目标**：一条命令完成解析→合成→上传→上线。
**范围**：`cli/src/index.js` 新增 `audiobook` 命令；`cli/src/r2.js`（manifest 增 audiobooks 读写）。

- **Story C1 — `cpv audiobook <file>` 端到端**
  - 作为家长（AI 上传），我想 `cpv audiobook book.epub --title "书名" [--category 国学] [--speaker zh_female_vv_uranus_bigtts]` 一步生成听书并上线。
  - **AC**：
    - [ ] 流程：解析 → 逐章逐段 TTS → 每章合成一个 mp3 → 上传 `audiobooks/<id>/ch-<n>.mp3` 与封面 → 更新 manifest。
    - [ ] `--dry-run`：输出章节列表、每章字数、预计时长与**成本估算**，不合成不上传。
    - [ ] `--json` 结果在 stdout（`ok` 字段）、进度在 stderr；退出码 0/1/2/3 约定。
    - [ ] **串行**处理，幂等（`--id` 同 ID 覆盖）；中途失败可重跑。
  - 改动范围：`cli/src/index.js`、`ebook.js`、`tts.js`、`r2.js`
- **Story C2 — manifest 数据模型（audiobooks）**
  - 作为系统，我想 manifest 用独立 `audiobooks` 数组承载听书，不破坏 videos。
  - **AC**：[ ] 新增 `audiobooks: [{ id, title, author, cover, category, chapters:[{ idx, title, audio, durationSec }], totalDurationSec, createdAt, updatedAt, source }]`；[ ] `getManifest` 兼容旧 manifest（无该字段时补空数组）；[ ] 不影响现有 `videos`。
- **Story C3 — `list` / `remove` 支持听书**
  - 作为家长，我想列出与删除听书。
  - **AC**：[ ] `cpv list` 同时显示视频与听书（标注类型/章节数/总时长）；[ ] `cpv remove <id>` 能删听书（`audiobooks/<id>/` 全部对象 + 条目）。

### Epic D：App「听书」呈现与音频播放
**目标**：孩子端能发现并收听听书。
**范围**：app Swift（Models、AppModel、新增听书相关 View、音频播放）。

- **Story D1 — 模型与数据加载**
  - **AC**：[ ] 新增 `Audiobook`/`Chapter` 模型；[ ] `APIClient`/`AppModel` 解析 `/api/library` 的 `audiobooks`；[ ] 旧数据（无 audiobooks）不崩。
- **Story D2 — 「听书」入口与列表**
  - 作为孩子，我想在分类/首页看到「听书」，进去看到书与章节。
  - **AC**：[ ] 「听书」作为一个分类/入口（贴合 001 的分类结构）；[ ] 书籍封面网格 → 进入显示章节列表。
- **Story D3 — 音频播放器**
  - 作为孩子，我想点章节就能听，并能上一章/下一章、暂停。
  - **AC**：[ ] 音频播放界面（封面 + 标题 + 进度条，无视频画面）；[ ] 章节连播/切换；[ ] 受现有时长/时段管控（复用休息页/护眼逻辑）。
- **Story D4 — 续听与收藏（复用进度）**
  - **AC**：[ ] 记录每本书最后收听章节与位置，「继续收听」；[ ] 可收藏，进「我喜欢的」。

### Epic E：Worker 透传 `audiobooks`
**目标**：让 `/api/library` 返回听书数据。
**范围**：`worker/src/index.js`。

- **Story E1 — `/api/library` 透传 audiobooks**
  - **AC**：[ ] manifest 的 `audiobooks` 原样下发；[ ] 章节音频按既有 `videos` 的鉴权/边缘缓存方式经 Worker 访问；[ ] 旧客户端忽略该字段不受影响。

### Epic W：Windows 端听书（对接现成接口）
**目标**：Windows App 与 Apple 端对齐，能发现并收听听书。后端（Worker `/api/library` 透传 + `/media/audiobooks/*` 网关）已就绪，本 Epic 为**纯前端**。
**范围**：`windows/src/app.js`（听书 Tab + 书架 + 章节列表 + 音频播放器）、`windows/src/styles.css`；`api.js` 复用（`library()` 已含 `audiobooks`，`mediaUrl()` 已带 `?t=` 令牌，无需改）。关联 `003-windows-app.md`。

- **Story W1 — 听书 Tab 与书架**
  - 作为孩子，我想在 Windows 上有「听书」入口，进去看到书（按分类/继续收听）。
  - **AC**：[ ] 顶部新增「听书」Tab（首页/分类/听书/我的）；[ ] 书架按分类分组 + 封面网格（无封面用占位图）；[ ] 有进度的书显示「继续收听」。
- **Story W2 — 书籍详情与章节列表**
  - **AC**：[ ] 点书进入详情（封面 + 书名 + 作者 + 总时长 + 章节数）；[ ] 章节列表（序号/标题/时长）；[ ] 「播放 / 继续收听」按钮。
- **Story W3 — 音频播放器**
  - 作为孩子，我想点章节就能听，并能上一章/下一章、暂停、调速、拖动进度。
  - **AC**：[ ] 音频播放界面（封面 + 书名 + 章节标题 + 进度条，无视频画面）；[ ] 章节连播 / 上一章 / 下一章 / 自动续播；[ ] 续听（记住最后章节与位置）；[ ] 受**时段**管控（睡前不放）。
- **范围外（后续）**：迷你播放条 / 睡眠定时 / 后台续播（Apple 端 Epic G/H；Windows 为桌面常驻窗口，优先级低）。**设计决策**：听书**不计入每日观看上限**（护眼初衷：鼓励听、少看屏），仅受**时段**管控。

## 5. 数据 / 接口影响
- **manifest.json**：新增 `audiobooks` 数组（见 C2）；`videos` 不变。
- **R2 对象**：`audiobooks/<id>/ch-<n>.mp3`、`audiobooks/<id>/cover.jpg`。
- **CLI 配置**：新增环境变量 `DOUBAO_TTS_API_KEY`（豆包新版控制台 API Key）。`cli/README.md` 补说明。
- **Worker**：`/api/library` 透传 `audiobooks`；音频走与视频一致的网关/缓存策略。
- **客户端**：新增 `Audiobook`/`Chapter` 模型；`AppModel` 增听书加载与播放状态。

## 6. 里程碑 / 优先级
- **P0（先做，打通「能产出听书并上线」的后端链路）**：Epic A（TTS）、Epic B1 + B3（EPUB 解析 + 清洗分段）、Epic C（audiobook 命令 + manifest）。
- **P1（让孩子端能用）**：Epic E（Worker 透传）、Epic D1–D3（模型/入口/播放）。
- **P2**：Epic B2（TXT/MD）、Epic D4（续听收藏）、PDF、本地 TTS 兜底、字幕跟读。

## 7. 测试与验收总览
- **TTS 连通性**：`cpv doctor` 通过（含 TTS 检查）。
- **端到端（P0）**：`cpv audiobook sample.epub --title "测试故事" --category 国学 --dry-run` 先看章节/成本 → 去掉 `--dry-run` 实跑 → R2 出现 `audiobooks/<id>/ch-*.mp3` + manifest 含该听书 → `cpv list` 可见。
- **端到端（P1）**：App「听书」可见该书 → 进章节 → 播放出声 → 续听/收藏生效。
- **构建**：两端构建通过（macOS + iOS 模拟器，命令见 CONTRIBUTING）。
- **成本/边界**：超长章节分段拼接正确、空章节跳过、中途失败重跑幂等、旧 manifest 兼容。
