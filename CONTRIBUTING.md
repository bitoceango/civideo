# 开发规范（Contributing）

本项目采用 **issue 先行** 的开发流程。任何新需求、功能改动、bug 修复，**必须先建 issue，再开发、再提交**。

## 流程

```
提需求 → 建 Issue（按统一模板填全 5 项）→ 开发（feat/<issue号> 分支）→ 提交（关联 issue）→ 验收 → 合并/关闭 issue
```

1. **先建 Issue**：用 [功能需求模板](.github/ISSUE_TEMPLATE/feature_request.md) 新建,把 5 项填全:
   - **🎯 目标**：要解决什么、达到什么效果
   - **✨ 功能特性**：逐条列出要做的功能点
   - **📐 改动范围**：涉及哪些模块/文件,哪些不做
   - **🧪 测试方案**：怎么验证(步骤/命令/用例)
   - **✅ 验收方案**：满足哪些条件算"做完"
2. **再开发**：从 `main` 切分支 `feat/<issue号>-<简述>`(或 `fix/<issue号>-...`)。
3. **再提交**：commit / PR 标题或正文里**关联 issue 号**(如 `feat: 选集面板 (#12)` 或正文 `Closes #12`)。
4. **验收**：对照 issue 的「验收方案」逐条确认,通过后合并并关闭 issue。

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
