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
