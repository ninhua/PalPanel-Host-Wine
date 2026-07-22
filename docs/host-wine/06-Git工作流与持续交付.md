# Git 工作流与持续交付

## 1. 目标仓库

开始前必须设置：

```text
TARGET_REPO=<owner/repo>
TARGET_DEFAULT_BRANCH=<main 或 dev>
```

禁止在未确认远程仓库和权限时修改错误的仓库。

## 2. 分支规则

推荐：

```text
codex/p0-baseline
codex/p1-host-wine-runtime
codex/p1-windows-steamcmd-workshop
codex/p1-save-preflight
codex/p2-rbac-audit
...
```

- 一个分支对应一个可独立审查的工作项或紧密相关的小批次。
- 不在 `main`/`dev` 上直接开发。
- 禁止强制推送受保护分支。
- 需要重写提交时，只允许在个人功能分支并确认不会覆盖他人工作。

## 3. 每次修改都必须推送

“每次修改”按**原子、可测试变更**定义，不是每敲一行代码。每个原子变更必须：

1. 查看 `git status` 和当前分支；
2. 完成一个明确范围；
3. 运行相关测试；
4. 更新 `CHANGELOG.md` 的 `[Unreleased]`；
5. 更新受影响文档/OpenAPI；
6. 更新实施日志，记录测试命令和结果；
7. `git diff --check`；
8. 提交；
9. 立即推送到 GitHub；
10. 检查远端分支和 CI。

任务结束时必须满足：

```text
git status --short 为空
本地 HEAD 与远端功能分支一致
CI 通过，或实施日志明确记录失败和后续修复提交
```

## 4. 提交信息

使用 Conventional Commits：

```text
feat(runtime): add host-wine provider skeleton
fix(workshop): isolate Windows SteamCMD wine prefix
test(save): cover prepared transaction recovery
docs(env): document NFS save constraints
chore(release): bump startup script to 1.0.37
```

一个提交必须包含与代码匹配的测试和必要文档。禁止使用 `update`, `fix stuff`, `changes` 等无意义信息。

## 5. PR 规则

每个阶段使用 Draft PR，正文至少包含：

- 目的和边界；
- 修改文件；
- 数据迁移；
- 安全风险；
- 测试命令和结果；
- 简幻欢 Host-Wine 实机结果；
- 回滚步骤；
- 对应 PalOps 参考文件；
- 更新日志条目。

PR 每次推送后更新进度，而不是最后一次性填写。

## 6. 更新日志

根 `CHANGELOG.md` 使用 Keep a Changelog 风格：

```markdown
## [Unreleased]
### Added
### Changed
### Fixed
### Security
### Removed
```

每一个用户可见变化、配置变化、目录变化、数据库迁移、脚本版本、兼容性变化都必须记录。

脚本更新同时记录：

- `SCRIPT_VERSION`；
- `SCRIPT_BUILD`；
- 前一版本；
- SHA-256；
- 新增/修改/删除；
- 回滚方式。

## 7. Release 交付

每个可部署 Release 必须包含：

- Linux amd64 PalPanel 发布包；
- `SHA256SUMS`；
- 对应 `/home/container/start.sh`；
- 上一脚本版本到当前版本 diff；
- CHANGELOG；
- 部署和升级说明；
- 配置变更说明；
- 回滚说明；
- 测试报告。

## 8. CI 最低检查

```bash
(cd backend && go test -p=1 ./...)
(cd sav-cli && CGO_ENABLED=1 go test -p=1 ./...)
(cd palcalc-bridge && dotnet build -c Release)
(cd frontend && npm ci && npm run check && npm run test:e2e)
python -m unittest discover -s astrbot_plugin_palpanel/tests
bash -n scripts/*.sh
```

新增 Host-Wine Runner 后，还要增加：

- heredoc 脚本提取后的 `bash -n`；
- Python 辅助脚本 `py_compile`；
- 假 `/proc` fixture 单元测试；
- Windows SteamCMD 命令参数测试；
- 下载代理回退和 SHA 失败测试；
- SQLite/NFS 配置测试；
- 升级和自动回滚测试。

## 9. 凭据和安全

不得提交：

- Steam 密码、Steam Guard、缓存文件；
- Palworld AdminPassword；
- RCON 密码；
- PalDefender Token；
- Webhook secret；
- QQ/AstrBot HMAC secret；
- 实际公网地址、Cookie、存档、数据库、日志和 Data Protection key。

推送前运行现有 gitleaks/secret 扫描。
