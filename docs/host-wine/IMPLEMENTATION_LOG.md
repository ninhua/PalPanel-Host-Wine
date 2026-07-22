# Host Wine 实施日志

## P0-03：建立基线与实施映射

- 日期：2026-07-22
- 目标仓库：`ninhua/PalPanel-Host-Wine`
- 默认分支：`main`
- 工作分支：`codex/p0-baseline`
- PalPanel 基线：`b0b3806e6c49610f43d96af361412a348f6a653d`
- PalOps Web 参考：`b51bd84a76ae0e83442feaa8c6bffc1b97e5d119`
- 启动脚本：v1.0.36，SHA-256
  `8f5e3daacccae9b4c233fe08f93a754135a17b55bc22035305dc97fa63a621db`

### 范围

- 导入交接文档、环境变量示例、清单和只读启动脚本基线。
- 不修改 Go、React、侧车或运行时行为。
- 不切换上游版本。

### 验证

- `Get-FileHash -Algorithm SHA256 scripts/baseline/palworld-panel-start-fixed-v1.0.36.sh`：
  通过，结果与交接基线一致。
- UTF-8 严格解码检查：通过，共检查 15 个新增或修改的文本文件。
- `git diff --check`：通过。
- `bash -n scripts/baseline/palworld-panel-start-fixed-v1.0.36.sh`：未运行；
  当前 Windows 执行环境未安装 Bash，交由 Linux CI 补充验证。
- `scripts/scan-secrets.sh`：未运行；依赖 Bash，交由 Linux CI 补充验证。
- Go、React、sav-cli、PalCalc 测试：本次未修改程序源码；完整基线测试将在
  P0-04 单独执行和记录。

### 下一项

P1-01：定义 `host_wine` Runtime Provider 的最小接口与模式校验测试。

## P0-05：补充 Workshop 匿名模式契约

- 日期：2026-07-22
- 范围：计划、脚本映射、验收、Codex 任务说明和 CHANGELOG。
- 要求：移除 Mod/Workshop 页面针对 Steam 账号和登录状态的强制门禁；后端正式
  接受 `anonymous` 和空用户名；保留 PalPanel 自身认证、权限与高风险确认。
- 程序行为：本提交仅补充实施契约，具体前后端实现归入 P1-06。

## P1-01：Host Wine Runtime Provider 契约

- 日期：2026-07-22
- 新增 Runtime 模式：`host_wine`。
- 新增 Provider 能力边界：安装、更新、校验、启动、保存、优雅关服、停止、
  强制停止、重启、状态、健康、指标、日志、启动参数保存和运行状态恢复。
- Setup 页面可以识别并展示 Host Wine 模式；Docker 模式和 Windows SteamCMD
  模式继续保留。
- 本提交只建立接口和模式契约；Linux `/proc` 身份验证与实际进程控制由后续
  P1-02/P1-03 原子提交实现。

### 验证

- P0 完整 GitHub Actions CI：通过，Linux、Windows、vulnerability 三个 Job
  全部成功（run `29906437187`）。
- `npm run typecheck`：通过。
- `npm run test -- src/pages/Setup.test.tsx`：通过，12/12。
- `gofmt`：已应用于本提交修改和新增的 Go 文件。
- 本机 Go 测试：未形成有效结果；工作盘无法在超时内完整展开便携 Go 标准库。
  当前提交的 Go 编译与单元测试由推送后的 Linux/Windows CI 验证。
- `git diff --check`：通过。

## P1-02：Host Wine 进程身份（进行中）

- 新增可持久化的 Host Wine 进程身份记录：PID、PGID、Linux `/proc` 启动时钟、
  Shipping 路径和 `WINEPREFIX`。
- 读取 `/proc/<pid>/stat` 时按最后一个右括号切分，兼容进程名中包含空格或括号，
  避免字段错位。
- 重验命令行中的完整 Shipping 路径和环境中的完整 `WINEPREFIX`，不接受子串匹配。
- 新增 `PalServerShippingPath()` 正式路径入口及 Linux 单元测试；不以 PID 单值
  判断服务仍在运行。

## P1-03：生命周期与日志（进行中）

- `host_wine` 已从 Manager 的启动、停止、重启和状态路径接入 Go 原生实现，
  不再落入 Docker Runner 或 Windows 进程分支。
- 通过 `setsid` 建立独立 PalServer 会话；启动后在该 PGID 内发现并严格验证
  Shipping 进程，再持久化完整身份。
- 停服前重新验证 PID/PGID/启动时钟/Shipping 路径/`WINEPREFIX`；先向进程组发送
  `SIGTERM`，超时后才发送 `SIGKILL`。
- 继续使用 PalPanel 正式轮转日志；新增 Linux 生命周期测试夹具，覆盖启动、
  状态恢复、身份持久化和停止。
- 新增 `PALPANEL_WINE_BIN`，默认 `wine64`；Host Wine 前置检查不再要求 Docker。
- CI 首次发现停服退出竞态：`SIGTERM` 后 zombie 的空命令行被误判为身份变化；
  已改为显式识别 Linux zombie/退出态，活进程仍执行全部身份重验。

## P1-04：PalServer 会话资源统计

- Monitor 对 `host_wine` 使用 Provider 指标，不再落入 Windows `tasklist` 分支。
- CPU 通过两次 `/proc/stat` 与会话进程 CPU tick 差值计算；内存汇总同一 PGID
  所有进程的 RSS。
- 统计前先严格重验持久化的 Shipping 进程身份；扫描范围限定为该 PGID，独立
  SteamCMD Prefix、其他 Wine 会话和面板进程均不计入。
- 新增 `/proc` 解析测试和 Monitor Provider 映射测试。
