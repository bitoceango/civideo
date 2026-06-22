# cpv — child-podcast 上传 CLI

把视频上传到 Cloudflare R2 并维护播放列表 `manifest.json`。播放器读同一个 manifest，上传完成后刷新即见新视频。

为 AI 调用设计：非交互、`--json` 结构化输出、明确退出码、`--id` 幂等覆盖。

## 安装

```bash
cd cli && npm install
# 可选：npm link 后可以直接用 `cpv` 命令
```

依赖本机 ffmpeg：`brew install ffmpeg`

## R2 配置（一次性）

1. Cloudflare 控制台 → R2 → 创建 bucket（如 `child-podcast`），**保持私有**
2. R2 → Manage R2 API Tokens → 创建 Token，权限选 **Object Read & Write**，限定到该 bucket
3. 设置环境变量（写进 shell profile 或 `.env` 后 source）：

```bash
export R2_ACCOUNT_ID=<YOUR_CLOUDFLARE_ACCOUNT_ID>   # S3 端点里那串 / 控制台右侧可见
export R2_ACCESS_KEY_ID=xxx
export R2_SECRET_ACCESS_KEY=xxx
export R2_BUCKET=child-video
```

4. 验证：`cpv doctor`

## 豆包 TTS 配置（仅 `audiobook` 听书功能需要）

把电子书转成听书要调火山引擎豆包语音合成（seed-tts-2.0）。在**新版语音控制台**（`console.volcengine.com/speech/new`）开通「语音合成大模型」并在「API Key 管理」创建 API Key，然后：

```bash
export DOUBAO_TTS_API_KEY=<新版控制台的 API Key>
```

> 鉴权用新版控制台的单头 `X-Api-Key`（不是旧版 App ID + Access Token）。密钥**绝不入库**。`cpv doctor` 会顺带探测 TTS 连通性。

## 用法

```bash
# 上传（自动探测：H.264/AAC+MP4 直传；容器不对仅重封装；编码不兼容才转码）
cpv upload 小猪佩奇01.mp4 --title "小猪佩奇 第1集" --series "小猪佩奇" --json

# 先看处理计划，不动手
cpv upload video.mkv --title "测试" --dry-run --json

# 完整处理但只输出到本地目录（联调用，不上传）
cpv upload video.webm --title "测试" --local-out /tmp/out --json

# 列出播放列表（视频 + 听书）/ 删除（视频 v 开头、听书 a 开头）
cpv list --json
cpv remove v1a2b3c4d5 --json

# 电子书 → 听书（EPUB/TXT/MD）：按章合成→上传→更新 manifest
# 先预览章节/字数/预计时长/成本，不合成：
cpv audiobook 西游记.epub --title "西游记" --category 国学 --dry-run --json
# 实跑（需 DOUBAO_TTS_API_KEY）：
cpv audiobook 西游记.epub --title "西游记" --category 国学 --json
# 指定音色 / 单段字数 / 幂等覆盖：
cpv audiobook book.txt --title "睡前故事" --speaker zh_female_vv_uranus_bigtts --seg-chars 300 --id ab_bedtime --json
```

### 存储治理 / 自动回收（GC）—— 需求文档 008

R2 按字节计费，长期堆积旧视频会逼近上限。下面三条命令让用量可观测、可自动回收，且**绝不误删收藏/未看完的内容**（详见 `docs/requirements/008-r2-storage-gc.md`）。

```bash
# 用量统计 + 阈值告警（按 videos/audiobooks/其它 分组；状态 ok/warn/over）
cpv storage --json
cpv storage --cap-gb 500 --low-gb 450        # 覆盖默认阈值

# 保护某视频：gc 永不删它（收藏保护）。取消用 unkeep
cpv keep  v1a2b3c4d5
cpv unkeep v1a2b3c4d5

# 自动回收：超低水位才删「看完且过冷却期、未保护」的旧视频，按上传时间 old→new 删到低水位
cpv gc --dry-run --json                       # 先预览候选与预计释放（强烈建议先 dry-run）
cpv gc --json                                 # 真删（默认直接执行）
cpv gc --low-gb 400 --cooldown-days 14 --json # 覆盖低水位与冷却天数
```

> **安全失败**：`gc` 必须能连到 Worker 的 `/api/admin/watch-stats`（受家长 PIN 保护）查「看完状态」。Worker 地址 / PIN 不可达或缺失时，**宁可不删**——直接退出非 0，不动任何对象。适合挂 cron/CI 定时跑。

**存储治理相关环境变量**（均有默认、可选；也可用同名 `--flag` 覆盖）：

```bash
export R2_CAP_GB=500           # 存储上限 GB（over 阈值）
export R2_LOW_GB=450           # 低水位 GB（gc 删到 ≤ 此值；warn 阈值）
export GC_COOLDOWN_DAYS=7      # 视频「看完」后至少冷却几天才允许删
export CV_WORKER_URL=https://video.example.com   # gc 查看完状态用（也可 --worker）
export PARENT_PIN=1234         # 家长 PIN，调 watch-stats 鉴权用（也可 --pin）
```

## 退出码与 JSON 输出（AI 集成约定）

| 退出码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 运行失败（文件不存在 / ffmpeg 失败 / R2 / TTS 报错，详见 stdout 的 `error` 字段） |
| 2 | 缺配置（R2 环境变量，或 `audiobook` 缺 `DOUBAO_TTS_API_KEY`） |
| 3 | 缺 ffmpeg/ffprobe |

`--json` 时结果只打到 stdout（单个 JSON 对象，`ok` 字段标识成败），进度信息走 stderr，可放心 `JSON.parse`。

上传成功输出示例：

```json
{
  "ok": true,
  "id": "v1a2b3c4d5",
  "action": "direct",
  "entry": {
    "id": "v1a2b3c4d5",
    "title": "小猪佩奇 第1集",
    "series": "小猪佩奇",
    "durationSec": 300,
    "video": "videos/v1a2b3c4d5/video.mp4",
    "poster": "videos/v1a2b3c4d5/poster.jpg"
  },
  "manifestVideos": 12
}
```

## manifest.json 结构（播放器消费的播放列表）

存于 bucket 根部，`Cache-Control: no-store`（播放器每次拉取都是最新）：

```json
{
  "version": 1,
  "updatedAt": "2026-06-11T12:00:00.000Z",
  "videos": [ { "id": "...", "title": "...", "series": "...", "durationSec": 300,
                "width": 1280, "height": 720, "sizeBytes": 0,
                "video": "videos/<id>/video.mp4", "poster": "videos/<id>/poster.jpg",
                "createdAt": "...", "updatedAt": "..." } ],
  "audiobooks": [ { "id": "a...", "title": "...", "author": "...", "cover": "audiobooks/<id>/cover.jpg",
                    "category": "国学", "totalDurationSec": 1234,
                    "chapters": [ { "idx": 1, "title": "第一章", "audio": "audiobooks/<id>/ch-1.mp3", "durationSec": 200 } ],
                    "createdAt": "...", "updatedAt": "...",
                    "source": { "format": "epub", "engine": "doubao", "speaker": "zh_female_vv_uranus_bigtts" } } ]
}
```

注意：manifest 是整文件读-改-写，**不要并行跑多个 upload/remove**（家庭规模单写足够；真要批量就串行循环）。
