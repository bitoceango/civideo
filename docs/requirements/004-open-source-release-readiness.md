# 需求文档：开源发布就绪（安全加固 / 一键部署 / 多平台分发）

> 编号：004 ｜ 状态：草稿（待评审）
> 创建日期：2026-06-13 ｜ 关联：`README.md`、`docs/architecture.md`、`worker/src/index.js`、003 Windows App

## 1. 背景与目标

项目即将作为开源项目对外发布，目标是**让更多人能搜到、能自部署、能安全使用**。当前有三类摩擦：

1. **安全**：孩子端只需「域名 + PIN」即可激活。而**域名不是秘密**（自定义域名的 HTTPS 证书会进公开的 Certificate Transparency 日志，可被 crt.sh 等枚举），且 `PARENT_PIN` 很可能是 4–6 位数字（兼作孩子端家长门），激活接口 `/api/activate` **无任何限流** → 知道域名即可暴力破解 PIN、激活设备、拿到全部内容。
2. **部署**：后端要 7 条命令 + 2 次手动编辑 `wrangler.jsonc`（填域名、把 `d1 create` 输出的 `database_id` 复制回去），README 还漏写 `wrangler login`，且强制要求自有自定义域名。对新手劝退。
3. **分发**：没有预打包产物，别人要自己从源码构建。

**核心目标**：补齐安全短板（P0），把自部署压到「尽量一条命令」，必需的人工步骤在 README 写清楚，并在 Release 页提供各平台预打包产物。

## 2. 范围

- **本次要做（In scope）**：
  - Worker 激活接口限流/锁定；激活密钥与家长 PIN 分离。
  - 一键部署脚本（建桶/建库/写回 d1 id/迁移/设密钥/部署）；自定义域名可选（默认 `workers.dev`）。
  - README 部署章节重写，含「必需人工步骤」清单。
  - GitHub Actions 多平台 Release 打包（Windows / macOS / CLI / iOS 未签名 ipa）。
  - App 服务器地址支持构建期注入（公开版留空）。
- **本次不做（Out of scope）**：
  - 用户系统 / 多租户 / 账号体系（仍是单家庭单 PIN 模型）。
  - 桌面 App 的正式代码签名与公证（付费证书，单列后续）。
  - iOS 公开 TestFlight（需 $99/年，单列后续）。

## 3. 设计原则 / 约束

- **域名不可作为安全边界**：安全只能依赖 PIN/密钥强度 + 限流，不能依赖「域名保密」。
- **App 包内不含任何机密**：密码只存在部署者自己的 Worker secret 里；公开构建产物里域名留空。
- **家庭量级，不过度设计**：限流/锁定用最简单可靠的实现，避免引入额外存储依赖（优先 D1 / Cloudflare 原生能力）。
- **向后兼容**：现有已激活设备的令牌不失效；老部署升级路径平滑。

## 4. Epics 与 Stories

### Epic A：后端安全加固（P0，最高优先）
**目标**：消除「知道域名 + 弱 PIN + 无限流 = 可暴力破解」的洞。
**范围**：`worker/src/index.js`、`worker/schema.sql`、Cloudflare 控制台配置。

- **Story A1 — 激活接口限流与失败锁定**
  - 作为部署者，我希望 `/api/activate` 被暴力猜测时会被限流/锁定，以便短 PIN 也不会被在线爆破。
  - **验收标准（AC）**：
    - [ ] 同一来源（IP / CF-Connecting-IP）连续失败 N 次（默认 5）后进入退避/锁定窗口（默认 15 分钟），期间返回 `429`。
    - [ ] 成功激活或锁定窗口过期后计数重置。
    - [ ] 失败计数与窗口持久化（D1 表或 Cloudflare 原生限流），Worker 实例漂移不绕过。
    - [ ] README 同时给出「零代码版」：Cloudflare WAF Rate Limiting 规则示例（`/api/activate` 每 IP 每分钟 ≤5）。
  - 改动范围：`worker/src/index.js`（`handleActivate`）、可能新增 `schema.sql` 一张计数表　｜　依赖：无

- **Story A2 — 激活密钥与家长 PIN 分离**
  - 作为部署者，我希望「设备激活」用一串长随机密钥，「孩子端家长门」用短数字 PIN，以便短 PIN 不再是服务器命门。
  - **验收标准（AC）**：
    - [ ] 新增 `env.ACTIVATION_KEY`（长随机串）用于 `/api/activate`；`PARENT_PIN` 退化为「改本机家长规则」用途，或纯本地校验。
    - [ ] 激活页可输入较长密钥（不限 4 位数字键盘）。
    - [ ] 文档建议 `ACTIVATION_KEY` ≥ 24 位随机；提供生成命令。
    - [ ] 旧部署兼容：未设 `ACTIVATION_KEY` 时回退到 `PARENT_PIN`（带告警）。
  - 改动范围：`worker/src/index.js`、`app/`（激活页输入）、`docs`　｜　依赖：可与 A1 并行

- **Story A3 —（可选）纵深防御**
  - 作为部署者，我希望可选启用 Turnstile / 网络段白名单，进一步挡机器人激活。
  - **AC**：[ ] 文档给出 Turnstile 接入与 WAF 自定义规则示例；[ ] 默认关闭，不增加普通用户负担。

### Epic B：一键部署（P1）
**目标**：自部署从「7 命令 + 2 次手编」压到「一条脚本 + 回答两三个问题」。
**范围**：`worker/`（脚本、package.json scripts）、`README.md`、`wrangler.example.jsonc`。

- **Story B1 — `npm run setup` 引导脚本**
  - 作为新部署者，我希望一条命令完成后端资源创建与部署，以便不必手动逐步操作。
  - **验收标准（AC）**：
    - [ ] `npm run setup` 依次：检查 `wrangler login` → 建 R2 桶（幂等）→ 建 D1 → **自动把 `database_id` 写回 `wrangler.jsonc`** → 跑 `schema.sql` → 提示输入并 `secret put`（激活密钥）→ `deploy`。
    - [ ] 仅交互询问真正需要人输入的项（密钥、是否用自定义域名）。
    - [ ] 可重复运行（幂等），失败有清晰报错与重试指引。
    - [ ] 结束打印最终访问域名 + App 端下一步。
  - 改动范围：新增 `worker/scripts/setup.mjs`、`worker/package.json` scripts　｜　依赖：B2

- **Story B2 — 自定义域名可选（默认 workers.dev）**
  - 作为没有自有域名的用户，我希望默认用 `*.workers.dev` 零域名部署，以便最低门槛跑起来。
  - **验收标准（AC）**：
    - [ ] `wrangler.example.jsonc` 默认 `workers_dev: true`、不含 `routes`；自定义域名作为注释/可选段。
    - [ ] setup 脚本询问「是否绑定自定义域名」，否则用 workers.dev。
    - [ ] README 注明 `*.workers.dev` 在中国大陆可能被墙，需要自定义域名。
  - 改动范围：`worker/wrangler.example.jsonc`、setup 脚本、README

- **Story B3 — README 部署章节重写 + 人工步骤清单**
  - 作为新用户，我希望 README 清楚列出哪些必须手动、怎么做，以便不踩坑。
  - **验收标准（AC）**：
    - [ ] 新增「必需人工步骤」清单：注册 Cloudflare、`wrangler login`、（CLI 用的）R2 S3 API Token 在控制台创建、（可选）自定义域名 DNS、iOS 构建/SideStore。
    - [ ] 一条命令快速路径 + 分步详解；含 `wrangler login`（当前缺失）。
    - [ ] 可选：「Deploy to Cloudflare」按钮（说明它只覆盖到 80%，secret/迁移仍需补）。
  - 改动范围：`README.md`、`worker/README.md`、`cli/README.md`

### Epic C：多平台 Release 打包与 CI（P1）
**目标**：Release 页提供可下载产物；明确各平台「能不能下载即用」。
**范围**：`.github/workflows/`、`app/`、`windows/`、`cli/`。

- **Story C1 — GitHub Actions 统一 Release 工作流**
  - 作为维护者，我希望打 tag 即自动构建各平台产物并发布到 Release，以便用户直接下载。
  - **验收标准（AC）**：
    - [ ] 推送 `v*` tag 触发：构建 **Windows**（Tauri `.msi/.exe`）、**macOS**（`.app`/`.dmg`，未签名）、**CLI**（tarball 或 npm）、**iOS 未签名 `.ipa`**（供 SideStore）。
    - [ ] 产物作为 GitHub Release 资产上传；Release notes 自动列出各产物 + 安装说明链接。
    - [ ] 每个桌面产物在 README/Release 注明未签名的系统拦截绕过法（macOS 右键打开 / Windows SmartScreen「仍要运行」）。
    - [ ] 明确标注：**iOS 不能下载即用**，ipa 仅供 SideStore 自签或源码自建。
  - 改动范围：`.github/workflows/release.yml`（新增）、各端构建脚本　｜　依赖：D（App 域名留空构建）

### Epic D：App 服务器地址构建期注入（P2）
**目标**：个人构建可把域名烤进包省得每次手填；公开构建留空。
**范围**：`app/project.yml`、`app/ChildVideo/Support/Config.swift`、`app/ChildVideo/Info.plist`。

- **Story D1 — 构建期注入服务器地址**
  - 作为部署者，我希望自己的构建预填好 Worker 域名，以便（尤其 7 天重装后）不必每次手输。
  - **验收标准（AC）**：
    - [ ] 构建设置 `CV_SERVER_HOST` → 注入 Info.plist `CVServerHost` → `Config.defaultServer` 读取（host-only，代码补 `https://`，规避 `.xcconfig` 把 `//` 当注释的坑）。
    - [ ] 提供 gitignored `app/Local.xcconfig` 与提交版 `app/Local.example.xcconfig`。
    - [ ] **公开 Release 构建不带该文件 → 域名留空**，保持「不硬编码私有域名」。
    - [ ] 也支持命令行 `xcodebuild ... CV_SERVER_HOST=...` 注入（折进装机配方/CI）。
  - 改动范围：`app/project.yml`、`Config.swift`、`Info.plist`、`.gitignore`　｜　依赖：无

## 5. 数据 / 接口影响

- **D1**：A1 可能新增激活失败计数表（如 `activation_attempts(ip, fails, locked_until)`）。
- **Worker env**：新增 `ACTIVATION_KEY`（A2）；`PARENT_PIN` 语义收窄。
- **App**：激活页输入框放宽（A2）；新增 `CVServerHost` Info.plist 键（D1）。
- **接口**：`/api/activate` 增加 `429` 限流响应（A1）；校验凭证从 PIN 改密钥（A2，带回退）。

## 6. 里程碑 / 优先级

| 优先级 | Epic / Story | 说明 |
|---|---|---|
| **P0** | A1、A2 | 安全洞，发布前必须修 |
| P1 | B1、B2、B3 | 部署体验，决定开源转化率 |
| P1 | C1 | 预打包产物 |
| P2 | A3、D1 | 增强项 |

建议顺序：**A1 → A2 →（B1+B2+B3 并行）→ C1 → D1 →（A3）**。

## 7. 测试与验收总览

- **安全**：扩展 `tests/e2e-backend.sh`：连续错误 PIN 触发 `429`；锁定窗口内拒绝；窗口过期/成功后恢复；`ACTIVATION_KEY` 与回退路径。
- **部署**：在干净 Cloudflare 账号上跑 `npm run setup` 全程，记录真正需要人工的步骤数；workers.dev 路径零域名可跑通。
- **打包**：tag 触发后各平台产物可下载并能打开（桌面绕过拦截后）；iOS ipa 可被 SideStore 装。
- **App 注入**：带 `Local.xcconfig` 构建预填域名；不带则留空。
