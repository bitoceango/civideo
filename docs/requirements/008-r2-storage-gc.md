# 需求文档：R2 存储治理与自动回收（GC）

> 编号：008 ｜ 状态：开发中
> 创建日期：2026-06-15 ｜ 关联：issue #48 / #49 / #50 / #51；架构 `docs/architecture.md`（R2 按字节计费）
> 备注：本 Epic 的 issue 早先误写需求文档号为 `006-r2-storage-gc.md`，但 006 已被「Android App」占用，正式编号为本文件 **008**。

## 1. 背景与目标

R2 按存储字节计费（出口免费）。家庭长期使用下，看完即弃的旧视频会持续堆积，逼近免费额度（10GB）/ 自定义上限（默认 500GB），产生不必要的月费。

目标：**让存储用量可观测、可自动回收**——一条命令看清用量与阈值状态；超阈值时自动删除「孩子已看完且过了冷却期」的旧视频到低水位，且**绝不误删收藏/未看完的内容**。整套工具非交互、`--json`、退出码友好，可挂到 cron/CI 定时跑。

## 2. 范围

- **本次要做（In scope）**：
  - `cpv storage`：R2 用量统计 + 阈值监控（A1 / #48）
  - Worker `/api/admin/watch-stats`：受保护的「看完状态」聚合查询（B1 / #49）
  - `cpv gc`：按策略自动删看完旧视频到低水位（C1 / #50）
  - GC 可配置（阈值/水位/冷却天数）+ 收藏保护 `cpv keep/unkeep` + 安全失败（C2 / #51）
- **本次不做（Out of scope）**：
  - App 内展示用量/手动清理 UI（留 P2）
  - 定时任务/CI 的实际编排（留 P1，仅保证工具适合被定时调用）
  - 三端 App 改动（本 Epic 是 CLI + Worker 后端/家长运维工具，不涉及面向孩子的 UI）

## 3. 设计原则 / 约束

- **宁可不删，不可误删**：候选判定数据不全 / admin 接口不可达 → 安全失败（退出非 0，不删任何东西）。
- **收藏/保护永不删**：`keep` 标记落在 manifest（服务端可见），是 gc 的硬护栏。
- **家庭量级，不过度设计**：直接 ListObjectsV2 全量累加即可，无需 R2 用量分析 API。
- **单一事实源**：删除同时改 R2 对象与 manifest，保持一致；串行、幂等。
- **可观测**：所有破坏性动作支持 `--dry-run` 预览；日志走 stderr，结果走 stdout。

## 4. Epics 与 Stories

### Epic A：用量可观测
**目标**：一眼看清 R2 用量与阈值状态。范围：cli（r2.js、index.js、config.js）。

- **Story A1 — `cpv storage`（#48）**
  - 作为家长运维者，我想一条命令算出 R2 总用量并对阈值告警，以便知道何时该清理。
  - **AC**：
    - [ ] ListObjectsV2 分页累加所有对象 size 得总用量
    - [ ] 按前缀分组：`videos/` / `audiobooks/` / 其它
    - [ ] 与上限（默认 500GB）/低水位（默认 450GB）比较，标 `ok`/`warn`/`over`
    - [ ] 支持 `--json`；用量与控制台数值一致（合理误差）
  - 改动范围：cli/src/r2.js（列举/统计）、cli/src/index.js（storage 命令）、cli/src/config.js（阈值）

### Epic B：看完状态可查询
**目标**：给清理程序提供「每个视频是否被看完 + 最后观看时间」。范围：worker。

- **Story B1 — Worker `/api/admin/watch-stats`（#49）**
  - 作为清理程序，我想查到每个视频的看完状态，以便只删已看完的。
  - **AC**：
    - [ ] 受保护：用 PARENT_PIN（admin 凭证），**非设备令牌**（CLI 无设备令牌）
    - [ ] 读 manifest（各视频 duration）+ 聚合 D1 `watch_progress`
    - [ ] 每 videoId 返回 `{watched: 任一设备 position≥duration-ε, lastWatchedAt}`
    - [ ] 只回聚合，不泄露设备明细；无/错 PIN → 401/403
  - 改动范围：worker/src/index.js（新增 handler + 路由，置于 authDevice 设备门之前）

### Epic C：自动回收 + 护栏
**目标**：超阈值时安全地删到低水位。范围：cli。

- **Story C1 — `cpv gc`（#50）**
  - 作为家长运维者，我想超阈值时自动删看完旧视频，以便控制月费且不用手动挑。
  - **AC**：
    - [ ] 先算用量，未超低水位则直接返回不删
    - [ ] 候选 = `watched && (now-lastWatchedAt)≥冷却天数(默认7) && 非 keep`
    - [ ] 按 `createdAt` old→new 排序，依次删 `videos/<id>/` 全部对象 + manifest 条目，直到 ≤ 低水位
    - [ ] `--dry-run` 列清单 + 预计释放；默认全自动执行；`--json`；日志到 stderr
    - [ ] 串行 / 幂等；输出删了哪些 / 释放多少 / 剩余用量
  - 改动范围：cli/src/index.js（gc 命令，调用 B1 + r2.js）

- **Story C2 — GC 配置与安全护栏（#51）**
  - 作为家长运维者，我想能配阈值/水位/冷却并保护收藏，以便安心定时跑。
  - **AC**：
    - [ ] 可配 `R2_CAP_GB`(500) / `R2_LOW_GB`(450) / `GC_COOLDOWN_DAYS`(7) / worker 地址 + PIN
    - [ ] 收藏/保护视频永不删（manifest `keep` 标记 + `cpv keep/unkeep`）
    - [ ] admin 接口不可达 / 数据不全 → 安全失败（不删，退出非 0）
    - [ ] 适合 cron/CI（退出码 + JSON 友好）
  - 改动范围：cli/src/config.js、cli/src/index.js（keep/unkeep）、manifest（keep 字段）

## 5. 数据 / 接口影响

- **manifest**：video 条目新增可选 `keep: boolean`（true = gc 永不删）。向后兼容（缺省视为 false）。
- **Worker**：新增 `POST /api/admin/watch-stats`，body `{pin}`，返回 `{ok, stats: {<videoId>: {watched, lastWatchedAt}}}`。
- **D1**：只读 `watch_progress`（device_id, video_id, position_sec, updated_at），无 schema 变更。
- **CLI 环境变量**（均带默认/可选）：`R2_CAP_GB` / `R2_LOW_GB` / `GC_COOLDOWN_DAYS` / `CV_WORKER_URL` / `PARENT_PIN`（亦可用 `--worker` / `--pin` 覆盖）。

## 6. 里程碑 / 优先级

- P0：A1（#48）、B1（#49）、C1（#50）、C2（#51）—— 本批次。
- P1：cron/CI 定时编排（后续）。
- P2：App 内用量展示 / 手动清理（后续）。

## 7. 测试与验收总览

- `cpv storage --json` 用量与 Cloudflare 控制台一致（合理误差），阈值状态正确。
- Worker watch-stats：无/错 PIN → 401/403；造 `watch_progress` 看到结尾 → `watched=true`、`lastWatchedAt` 正确。
- `cpv gc --dry-run`：候选正确（看完 + 冷却 + 非 keep，按上传时间排序）；实跑后用量 ≤ 低水位、收藏/未看完未动、manifest 同步。
- 安全失败：worker 不可达 / 缺 PIN 时 gc 不删任何对象并退出非 0。
- `cpv keep <id>` 后该视频不进 gc 候选。
