# 发送给 Codex 的任务说明

你将修改一个基于 `uitok/palworld-panel` v1.2.1 的 Fork。目标不是部署 PalOps Web，而是：

1. 先把 `/home/container/start.sh` v1.0.36 中针对 PalPanel 的补丁正式写入 PalPanel Go/React 源码；
2. 保留启动脚本承担环境安装；
3. 在稳定 Host-Wine Runtime 上逐步实现 PalOps Web 的运营功能；
4. 每个原子修改完成后立即提交并推送 GitHub，并同步更新文档和 CHANGELOG。

## 开始前

必须先确认并记录：

```text
TARGET_REPO=<owner/repo>
TARGET_DEFAULT_BRANCH=<main/dev>
UPSTREAM_PALPANEL=https://github.com/uitok/palworld-panel
REFERENCE_PALOPS=https://github.com/CoderYiXin/PalOpsWeb
```

固定资料基线：

```text
PalPanel: b0b3806e6c49610f43d96af361412a348f6a653d（v1.2.1 基线）
PalOps:   b51bd84a76ae0e83442feaa8c6bffc1b97e5d119（1.2.0 基线）
Script:   v1.0.36, sha256=8f5e3daacccae9b4c233fe08f93a754135a17b55bc22035305dc97fa63a621db
```

先完整阅读本包：

```text
README.md
docs/01-项目运行环境与硬边界.md
docs/02-总体实施计划.md
docs/03-启动脚本补丁源码化映射.md
docs/04-PalOps功能与参考文件映射.md
docs/05-上游文档原地址.md
docs/06-Git工作流与持续交付.md
docs/07-测试与验收.md
scripts/palworld-panel-start-fixed-v1.0.36.sh
```

## 生产环境不可改变的事实

```text
平台：简幻欢 Linux amd64 容器，/home/container 为 NFS 持久化
唯一启动脚本：/home/container/start.sh
数据根：/home/container/palworld_win
没有真实 Docker daemon
Wine：便携 Wine 11.13 amd64-wow64
PalServer 前缀：/home/container/palworld_win/wineprefix
SteamCMD 计划前缀：/home/container/palworld_win/wineprefix-steamcmd
Windows SteamCMD：/home/container/palworld_win/steamcmd/steamcmd.exe
实际服务器程序：server/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe
唯一存档：server/Pal/Saved/SaveGames
Xvfb：默认 :99
```

不得把启动脚本移动到 `/home/container/palworld_win/start.sh`，不得创建 `/home/container/palworld-panel`。

## 第一阶段：只做补丁源码化

按顺序完成：

1. 新增正式 `host_wine` Runtime Provider，不再让后端调用伪 Docker。
2. 在 Linux `/proc` 上实现严格 PID/PGID/启动时间/路径/WINEPREFIX 重验。
3. 原生实现启动、保存、优雅停止、强制停止、重启、日志和资源统计。
4. Windows `steamcmd.exe` 负责服务端和 Workshop；Workshop 使用独立 `wineprefix-steamcmd`。
5. Workshop 默认 anonymous；不默认用户名；不强制登录；可选复用缓存账号；Steam Guard/停滞/超时返回结构化状态。
   第一阶段必须检查并删除 PalPanel 原版 Mod/Workshop 页面针对 Steam 账号和
   Steam 登录状态的强制前端校验。匿名模式必须能够进入页面、创建下载任务并
   完成安装。只移除 Steam 登录门槛，不得移除 PalPanel 自身的用户认证、权限
   控制和高风险操作确认。
6. 把 SaveGames Linux/Wine 原子替换预检和 Prepared 恢复迁入后端/正式环境探针。
7. Launcher 正式管理 sav-cli 和 palcalc-bridge。
8. 建立统一 GitHub 下载客户端：v4.gh-proxy.org → cdn.gh-proxy.org → 直连；SHA、大小、压缩包安全和缓存。
9. PalDefender Release API 地址配置化；403 不阻塞本地状态；删除 Go 二进制 URL 替换和 Python Release 代理。
10. UE4SS 原生支持 experimental-palworld；删除编译后前端文案替换和伪造日志。
11. 简化启动脚本，但必须保留 Wine、Xvfb、vcrun2022、Windows SteamCMD、目录、Release 下载、原子升级/回滚和 Launcher 启动。
12. 新脚本从 v1.0.37 开始顺序递增；v1.0.36 只读保留。

Phase 1 未通过实机验收前，不开始 RBAC/RCON/玩家纪律等新功能。

## 第二阶段以后

按 `docs/02-总体实施计划.md` 实现 RBAC、审计、RCON、批量发放、消息、玩家纪律、PalDefender 配置、维护、崩溃守护、通知、统计、存档差异和插件回滚。

每项功能必须在设计或 PR 中列出所参考的 PalOps 文件，映射见 `docs/04-PalOps功能与参考文件映射.md`。不得直接复制 .NET/Vue 架构；必须重写为 PalPanel 的 Go/React 模块。

## Git 纪律

每个原子变更必须执行：

```text
测试 → 文档 → CHANGELOG → 实施日志 → commit → push → CI
```

- 每次提交后立即 `git push`。
- 不在本地累计多个未推送大改动。
- 不直接推送受保护主分支。
- 不强制推送 main/dev。
- CI 失败时先修复并推送，再继续下一项。
- 任务结束时工作区必须干净且 HEAD 已在远端。

建议提交：

```text
feat(runtime): add host-wine provider
fix(workshop): isolate Windows SteamCMD prefix
test(save): cover prepared transaction recovery
docs(runtime): document NFS preflight
chore(script): bump startup script to 1.0.37
```

## 每次回复/实施日志必须报告

- 当前分支和目标仓库；
- 修改文件；
- 完成的计划 ID；
- 测试命令与结果；
- CHANGELOG/文档修改；
- commit SHA；
- push 目标；
- CI 状态；
- 未完成项和风险。

## 禁止事项

- 不使用 Linux SteamCMD 作为 Workshop 必需依赖。
- 不让 Windows SteamCMD 与 PalServer 共用 Wine 前缀。
- 不回退系统 Wine 10。
- 不引入 `/dev/shm` 存档镜像。
- 不修改活动存档进行差异分析。
- 不把密码、Token、Steam Guard、存档或日志提交到 GitHub。
- 不修改编译后的 Go 二进制字符串。
- 不搜索替换编译后的前端 JS 作为正式实现。
- 不伪造 UE4SS 加载日志。
- 不把 PalOps .NET/Vue 应用嵌入为第二套运行服务。

开始工作时先提交一个“基线和实施映射”小提交并推送；不要直接进行大规模重构。
