# child-podcast

家庭自用儿童视频流媒体：家长上传视频到 Cloudflare R2，孩子在封闭播放器里观看。完整架构见 `docs/architecture.md`。

## ⚠️ 开发流程：需求文档 + issue 先行（硬性规则）

任何新需求/功能/改动，**必须先有需求文档（在 `docs/requirements/`，含 Epic 与 Story，参考 `docs/requirements/TEMPLATE.md`），再按 Story 建 GitHub issue（模板 `.github/ISSUE_TEMPLATE/feature_request.md`：目标/功能特性/改动范围/测试方案/验收方案），再开发、再提交（关联 issue 号）**。详见 `CONTRIBUTING.md`。**没有需求文档和 issue，不写代码。**

## ⚠️ 三端同时实现（硬性规则）

**任何面向用户的功能，必须同时落地到三端：Apple（macOS/iOS，SwiftUI，目录 `app/`）+ Windows（Tauri，目录 `windows/`）+ Android（Tauri，目录 `android/`，APK）。** 一个功能不能只做一端——需求文档的 Story/验收要覆盖三端，建 issue 时按端拆 Story 或在一个 issue 里列三端验收项。

技术路线：**Windows 与 Android 复用同一套 Web UI（`windows/src` 的 `app.js`/`api.js`/`styles.css`），用 Tauri v2 分别出桌面安装包与 APK**；Apple 走 SwiftUI（独立一套）。即「两套代码（SwiftUI + Tauri-Web）覆盖三端」。改 Web UI 时 Windows/Android 自动同步；改功能逻辑时记得 SwiftUI 端也要跟上。

## 上传视频（AI 直接调用 CLI）

前置：环境变量 `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET`（配置见 `cli/README.md`），本机需有 ffmpeg。首次使用先 `cd cli && npm install`。

实际部署值：bucket = `child-video`（APAC），`R2_ACCOUNT_ID=<YOUR_CLOUDFLARE_ACCOUNT_ID>`，Worker 域名 `video.example.com`。

```bash
node cli/src/index.js upload <视频文件> --title "标题" [--series "系列名"] [--category "学科"] --json
node cli/src/index.js list --json
node cli/src/index.js remove <id> --json
node cli/src/index.js doctor --json   # 检查 ffmpeg/配置/R2 连通性
node cli/src/index.js storage --json  # R2 用量统计 + 阈值（ok/warn/over）
node cli/src/index.js keep <id>       # 保护视频不被 gc 删（收藏保护）；unkeep 取消
node cli/src/index.js gc --dry-run --json  # 自动回收：删看完旧视频到低水位（先 dry-run）。需 CV_WORKER_URL+PARENT_PIN，不可达则安全失败不删
```

约定：
- `--json` 结果在 stdout（单个 JSON 对象，`ok` 字段标识成败），进度在 stderr
- 退出码：0 成功 / 1 失败 / 2 缺 R2 配置 / 3 缺 ffmpeg
- 上传会自动探测编码：H.264/AAC+MP4 直传；仅容器不对就秒级重封装；编码不兼容才转码（慢）。先 `--dry-run` 可预览
- 上传成功即更新 R2 里的 `manifest.json`（播放列表单一事实源），播放器刷新即见
- 批量上传请串行执行，勿并行（manifest 整文件读-改-写）
