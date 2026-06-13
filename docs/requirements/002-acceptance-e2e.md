# 需求文档：整体功能验收与端到端测试

> 编号：002 ｜ 状态：已执行（2026-06-13，19/0 通过）
> 关联：001 三大模块、`docs/architecture.md`、`tests/e2e-backend.sh`

## 1. 目标
对"从视频上传到流媒体播放"的整条链路做端到端测试与功能验收，并逐项核对"播放体验对齐商业流媒体"。

## 2. 端到端自动化测试（后端）
脚本 `tests/e2e-backend.sh`，对线上 Worker 做 19 项断言，可重复运行、有 pass/fail 退出码。

```bash
source ~/.zshrc
PIN=1234 bash tests/e2e-backend.sh   # 退出码 0=全过
```

**最近一次结果（2026-06-13）：通过 19 / 失败 0。** 覆盖：
健康检查 · 无令牌 401 · 错误 PIN 403 · 激活发令牌 · 带令牌拉库 · library 含媒体 URL · 媒体 Range 206+Content-Range · 媒体全量 200 · **边缘缓存 HIT** · 封面 200 · 进度 GET（含 weekSec 本周报告）· 进度 POST 累加 · 规则错误 PIN 403 · 规则保存 200 + 回读生效 · 超时段拦截 · 超时长拦截。

## 3. 上传 → 播放 全链路 E2E（手动 + 模拟器）
- ✅ `cpv upload --category` 上传 → manifest 更新 → 库立即可见（CLI 已验证）。
- ✅ iOS 模拟器：激活 → 首页(金刚区/系列) → 分类 → 播放(真实流) → 我的(家长 PIN) 全部截图验证。
- ✅ 播放真实流媒体（Big Buck Bunny 720p）：206 分段、缓冲、拖动、同系列自动下一集（模拟器实测画面解码正常）。
- ✅ 家长闸门：超时段/超时长 → "休息一下"页（模拟器实测触发）。

## 4. 播放体验 vs 商业流媒体 —— 逐项验收清单
（对标 Netflix / YouTube / B站 / 爱奇艺；✅=已实现并构建通过）

| 维度 | 功能 | 状态 | 实现位置 |
|---|---|---|---|
| 播放控制 | 播放/暂停 | ✅ | PlayerView 中心大按钮 |
| 播放控制 | 进度条拖动 + 缓冲指示 | ✅ | scrubber（fill+buffered+knob，拖动 seek） |
| 播放控制 | ±10 秒快退/快进 | ✅ | 中心 gobackward/goforward.10 |
| 播放控制 | 倍速（0.75/1/1.25/1.5，儿童克制档） | ✅ | 倍速菜单 |
| 播放控制 | 播完重播 | ✅ | ended 态显示重播按钮 |
| 音频 | 音量滑块 + 静音 | ✅ | bottomBar Slider + 静音按钮 |
| 字幕 | CC 字幕开关（内嵌字幕轨） | ✅ | AVMediaSelectionGroup（hasSubtitles 时显示） |
| 内容导航 | 选集面板（同系列） | ✅ | episodeListSheet |
| 内容导航 | 同系列上一集/下一集 | ✅ | onNext/onPrev + 下一集按钮 |
| 内容导航 | 同系列自动连播 | ✅ | autoNext（不跨系列、无推荐） |
| 内容导航 | 继续观看（断点续播） | ✅ | startAt + 进度上报 |
| 内容导航 | 收藏（我喜欢的） | ✅ | model.toggleFavorite + 首页行 |
| 系统集成 | AirPlay 投屏 | ✅ | AVRoutePickerView |
| 系统集成 | Now Playing 锁屏/控制中心/耳机线控 | ✅ | MPNowPlayingInfoCenter + MPRemoteCommandCenter |
| 儿童/家长 | 防误触锁定（长按解锁） | ✅ | locked + lockedOverlay |
| 儿童/家长 | 每日时长上限 + 允许时段 | ✅ | 家长设置 + 服务端规则 + 休息页 |
| 儿童/家长 | 护眼休息提醒 | ✅ | eyeCareOverlay（间隔可配） |
| 儿童/家长 | 学习报告（今日/本周） | ✅ | weekSec + 家长设置展示 |
| 性能 | 边缘缓存降起播 | ✅ | Worker Cache API（etag 键） |

**有意不做（违背封闭专注理念，对标里明确排除）**：弹幕、评论/社交、算法推荐流、热度榜、外链、画质手动切换（封闭库统一 720p）、2x+ 高倍速、PiP 默认开。

**已知取舍**：双击快进手势未做（已有可见 ±10s 按钮，避免与单击控件冲突）；缩略图进度预览未做（需 HLS I-frame，当前为 MP4 渐进式）。

## 5. 两端构建与交付
- ✅ macOS：`xcodebuild ChildVideo_macOS` BUILD SUCCEEDED；已安装到 `/Applications/ChildVideo.app` 运行。
- ✅ iOS（模拟器）：`xcodebuild ChildVideo_iOS -sdk iphonesimulator` BUILD SUCCEEDED；模拟器全流程验证。
- iOS 真机交付：用免费 Apple ID 在 Xcode 签名 + SideStore 安装（见 `app/README.md`、`docs/architecture.md §4.4`）。真机 .ipa 需用户本地 Apple ID 签名（无年费路径）。

## 6. 结论
端到端后端测试 19/0 通过；上传→播放全链路在模拟器与 CLI 实测打通；商业播放器体验清单逐项落实（封闭花园相关项有意排除）。功能验收达成。
