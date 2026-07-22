# Changelog

本项目遵循 Keep a Changelog；版本策略以 PalPanel 上游版本和 Host Wine 后缀为基础。

## [Unreleased]

### Added

- 导入 Host Wine 源码化需求、运行环境边界、实施映射、测试矩阵和许可规则。
- 保留只读的 `palworld-panel-start-fixed-v1.0.36.sh` 行为基线。
- 新增 `host_wine` Runtime 模式和正式 Provider 生命周期接口，作为后续 Linux
  Host Wine 进程实现的稳定边界。

### Changed

- 记录 PalPanel 固定基线 `b0b3806e6c49610f43d96af361412a348f6a653d` 和
  PalOps Web 参考基线 `b51bd84a76ae0e83442feaa8c6bffc1b97e5d119`。
- 明确 Workshop 匿名模式不依赖 Steam 用户名、登录缓存或登录状态，并要求移除
  Mod/Workshop 页面的强制 Steam 登录门禁；PalPanel 自身认证和权限保持不变。

### Fixed

### Security

### Deprecated

### Removed
