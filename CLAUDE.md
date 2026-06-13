# child-podcast

家庭自用儿童视频流媒体：家长上传视频到 Cloudflare R2，孩子在封闭播放器里观看。完整架构见 `docs/architecture.md`。

## ⚠️ 开发流程：需求文档 + issue 先行（硬性规则）

任何新需求/功能/改动，**必须先有需求文档（在 `docs/requirements/`，含 Epic 与 Story，参考 `docs/requirements/TEMPLATE.md`），再按 Story 建 GitHub issue（模板 `.github/ISSUE_TEMPLATE/feature_request.md`：目标/功能特性/改动范围/测试方案/验收方案），再开发、再提交（关联 issue 号）**。详见 `CONTRIBUTING.md`。**没有需求文档和 issue，不写代码。**

## 上传视频（AI 直接调用 CLI）

前置：环境变量 `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET`（配置见 `cli/README.md`），本机需有 ffmpeg。首次使用先 `cd cli && npm install`。

实际部署值：bucket = `child-video`（APAC），`R2_ACCOUNT_ID=<YOUR_CLOUDFLARE_ACCOUNT_ID>`，Worker 域名 `video.example.com`。

```bash
node cli/src/index.js upload <视频文件> --title "标题" [--series "系列名"] --json
node cli/src/index.js list --json
node cli/src/index.js remove <id> --json
node cli/src/index.js doctor --json   # 检查 ffmpeg/配置/R2 连通性
```

约定：
- `--json` 结果在 stdout（单个 JSON 对象，`ok` 字段标识成败），进度在 stderr
- 退出码：0 成功 / 1 失败 / 2 缺 R2 配置 / 3 缺 ffmpeg
- 上传会自动探测编码：H.264/AAC+MP4 直传；仅容器不对就秒级重封装；编码不兼容才转码（慢）。先 `--dry-run` 可预览
- 上传成功即更新 R2 里的 `manifest.json`（播放列表单一事实源），播放器刷新即见
- 批量上传请串行执行，勿并行（manifest 整文件读-改-写）
