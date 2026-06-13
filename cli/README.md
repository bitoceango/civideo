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

## 用法

```bash
# 上传（自动探测：H.264/AAC+MP4 直传；容器不对仅重封装；编码不兼容才转码）
cpv upload 小猪佩奇01.mp4 --title "小猪佩奇 第1集" --series "小猪佩奇" --json

# 先看处理计划，不动手
cpv upload video.mkv --title "测试" --dry-run --json

# 完整处理但只输出到本地目录（联调用，不上传）
cpv upload video.webm --title "测试" --local-out /tmp/out --json

# 列出播放列表 / 删除视频
cpv list --json
cpv remove v1a2b3c4d5 --json
```

## 退出码与 JSON 输出（AI 集成约定）

| 退出码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 运行失败（文件不存在 / ffmpeg 失败 / R2 报错，详见 stdout 的 `error` 字段） |
| 2 | 缺 R2 环境变量 |
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
                "createdAt": "...", "updatedAt": "..." } ]
}
```

注意：manifest 是整文件读-改-写，**不要并行跑多个 upload/remove**（家庭规模单写足够；真要批量就串行循环）。
