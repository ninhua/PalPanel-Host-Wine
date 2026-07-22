# Changelog

本项目遵循 Keep a Changelog；版本策略以 PalPanel 上游版本和 Host Wine 后缀为基础。

## [Unreleased]

### Added

- 导入 Host Wine 源码化需求、运行环境边界、实施映射、测试矩阵和许可规则。
- 保留只读的 `palworld-panel-start-fixed-v1.0.36.sh` 行为基线。
- 新增 `host_wine` Runtime 模式和正式 Provider 生命周期接口，作为后续 Linux
  Host Wine 进程实现的稳定边界。
- 新增 Linux Host Wine 严格进程身份校验基础：PID、进程组、`/proc` 启动时钟、
  Shipping 可执行文件参数和独立 `WINEPREFIX`。
- 新增 Go 原生 Host Wine 启动、状态恢复和进程组停服实现；服务会话使用 `setsid`
  隔离，并继续使用 PalPanel 的轮转日志文件。
- Host Wine 监控现在只汇总已验证 PalServer PGID 内的 Linux `/proc` CPU 与 RSS，
  不再误用 Windows `tasklist`，也不会统计 SteamCMD 或无关 Wine 会话。

### Changed

- 记录 PalPanel 固定基线 `b0b3806e6c49610f43d96af361412a348f6a653d` 和
  PalOps Web 参考基线 `b51bd84a76ae0e83442feaa8c6bffc1b97e5d119`。
- 明确 Workshop 匿名模式不依赖 Steam 用户名、登录缓存或登录状态，并要求移除
  Mod/Workshop 页面的强制 Steam 登录门禁；PalPanel 自身认证和权限保持不变。

### Fixed

### Security

### Deprecated

### Removed
