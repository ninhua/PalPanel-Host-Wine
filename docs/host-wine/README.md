# PalPanel Host-Wine 源码化与 PalOps 功能扩展：Codex 交接包

生成日期：2026-07-22

本包用于把当前 `palworld-panel-start-fixed-v1.0.36.sh` 中针对 PalPanel v1.2.1 的运行时补丁，逐步迁移到 PalPanel 源码，并在稳定的 Host-Wine 基线上增加 PalOps Web 的运营、安全、权限、审计、维护和通知能力。

## 目标顺序

1. **先源码化启动脚本补丁**：增加正式 `host_wine` Runtime Provider，取消伪 Docker、二进制 URL 替换和编译后前端文案替换。
2. **启动脚本仍负责环境安装**：便携 Wine、Xvfb、vcrun2022、Windows SteamCMD、目录权限、自定义 PalPanel 发布包下载与启动。
3. **Workshop 改用 Windows SteamCMD**：与服务器安装更新共用 Windows `steamcmd.exe`，但使用独立 `wineprefix-steamcmd`，不得与 PalServer 共用 Wine 前缀。
4. **统一 GitHub 下载链**：主代理 `https://v4.gh-proxy.org` → 备用代理 `https://cdn.gh-proxy.org` → GitHub 直连；源码和启动脚本都使用同一策略。
5. **再增加 PalOps 功能**：RBAC、审计、RCON、批量发放、玩家纪律、PalDefender 深度管理、维护编排、崩溃守护、通知、统计、存档差异和插件回滚。
6. **每次原子修改都推送 GitHub**：测试、文档、更新日志、提交和推送必须在同一个任务闭环内完成。

## 包内文件

- `docs/01-项目运行环境与硬边界.md`：生产环境、目录、端口、Wine/NFS 约束。
- `docs/02-总体实施计划.md`：分阶段计划、依赖、交付物与优先级。
- `docs/03-启动脚本补丁源码化映射.md`：v1.0.36 中每类补丁如何迁移到源码。
- `docs/04-PalOps功能与参考文件映射.md`：每项新增功能对应 PalOps Web 的实际参考目录和文件。
- `docs/05-上游文档原地址.md`：PalPanel 与 PalOps Web 的官方原始文档、源码、发布和许可证地址。
- `docs/06-Git工作流与持续交付.md`：逐提交推送、分支、PR、CI、更新日志和版本规范。
- `docs/07-测试与验收.md`：单元、集成、E2E、Wine/NFS 实机验收。
- `docs/08-许可与引用规则.md`：GPL、来源标注和不可直接照搬的实现边界。
- `codex/CODEX_PROMPT.md`：可直接发送给 Codex 的任务说明。
- `codex/AGENTS.md`：建议放入目标仓库根目录的长期执行约束。
- `config/palpanel-hostwine.env.example`：部署环境变量示例，不含凭据。
- `scripts/palworld-panel-start-fixed-v1.0.36.sh`：当前基线脚本，原样保留。
- `scripts/README.md`：脚本版本、修改和交付规则。
- `CHANGELOG.md`：本交接包更新日志。
- `MANIFEST.json`、`CHECKSUMS.sha256`：包内容与校验值。

## 使用前必须填写

Codex 开始修改前，必须在任务记录中填入：

```text
TARGET_REPO=<你的 PalPanel Fork，owner/repo>
TARGET_DEFAULT_BRANCH=<通常为 main 或 dev>
PUSH_BRANCH_PREFIX=codex/
```

未提供目标 Fork 地址，因此本包没有对任何仓库执行写入。

## 仓库归档说明

本目录由原始交接包导入。`HANDOFF_MANIFEST.json` 和
`HANDOFF_CHECKSUMS.sha256` 记录的是交接 ZIP 解压时的原始相对路径；导入仓库后
文件已归档到 `docs/host-wine/` 和 `scripts/baseline/`，因此不应在仓库根目录直接
使用该校验清单。导入前已完成原始清单的逐文件 SHA-256 验证。
