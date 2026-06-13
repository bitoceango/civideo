# 开发规范（Contributing）

本项目采用 **需求文档先行 + issue 先行** 的开发流程。任何新需求、功能改动，**必须先有需求文档（含 Epic / Story），再按 Story 建 issue，再开发、再提交**。

## 流程

```
提需求 → 写需求文档（Epic + Story）→ 评审 → 按 Story 建 Issue → 开发（feat/<issue号> 分支）→ 提交（关联 issue）→ 对照 Story 验收 → 合并/关闭
```

### 1. 先写需求文档（含 Epic / Story）
在 `docs/requirements/` 下新建需求文档（参考 [模板](docs/requirements/TEMPLATE.md)）：
- **Epic**：一个大功能/主题（如「首页模块」「播放器增强」）。每个 Epic 写清背景、目标、范围。
- **Story**：Epic 拆出的用户故事，格式「作为<角色>，我想<能力>，以便<价值>」，每条带**验收标准（AC）**。
- 一个 Epic 含多个 Story；Story 要小到能独立开发与验收。

### 2. 按 Story 建 Issue
每个 Story 对应一个 [功能需求 issue](.github/ISSUE_TEMPLATE/feature_request.md)，把 5 项填全（目标/功能特性/改动范围/测试方案/验收方案），并在 issue 里回链所属 Epic 与需求文档。

### 3. 再开发
从 `main` 切分支 `feat/<issue号>-<简述>`（或 `fix/<issue号>-...`）。

### 4. 再提交
commit / PR 标题或正文**关联 issue 号**（如 `feat: 选集面板 (#12)` 或正文 `Closes #12`）。

### 5. 验收
对照 Story 的验收标准 + issue 的验收方案逐条确认，通过后合并并关闭。

## 约定

- **没有 issue,不写代码、不提交。** 这是硬性规则。
- 一个 issue 聚焦一件事;过大就拆成多个。
- commit message 用中文/英文均可,但要能对应到 issue。
- 提交前确保两端都能构建:
  ```bash
  cd app && xcodegen generate
  xcodebuild -scheme ChildVideo_macOS -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
  xcodebuild -scheme ChildVideo_iOS -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios CODE_SIGNING_ALLOWED=NO build
  ```
- 敏感信息(域名/账号 ID/密钥/孩子姓名)绝不入库,放本地 `deploy.local.json`(已 gitignore)。

## 命令行建 issue（可选）

```bash
gh issue create --template feature_request.md
# 或直接：
gh issue create --title "[Feature] 选集面板" --label feature --body-file <(cat <<'EOF'
## 🎯 目标
...
EOF
)
```
