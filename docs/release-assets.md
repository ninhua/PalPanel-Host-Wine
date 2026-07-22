## 下载文件说明

| 文件 | 用途 | 适用人群 |
| --- | --- | --- |
| `palpanel_{{RELEASE_TAG}}_linux_amd64.tar.gz` | Linux x86-64 完整安装包，包含面板、后端、前端、sav-cli、PalCalc Bridge 和安装管理脚本 | Linux 和 Host Wine 用户 |
| `palpanel_{{RELEASE_TAG}}_windows_amd64.zip` | Windows x86-64 完整成品，包含 Windows 可执行文件和 Launcher | Windows 用户 |
| `palpanel_{{RELEASE_TAG}}_source.tar.gz` | PalPanel 整个项目的源码快照 | 审计、二次开发或自行编译 |
| `palpanel-sav-cli_{{RELEASE_TAG}}_source.tar.gz` | 独立的 sav-cli 存档处理工具源码 | 存档工具开发者 |
| `palpanel_{{RELEASE_TAG}}_linux_amd64.spdx.json` | Linux 成品的 SPDX 软件物料清单（SBOM） | 安全审计和合规检查 |
| `SHA256SUMS` | 所有发布文件的 SHA-256 校验值 | 建议所有用户安装前校验 |
| `THIRD_PARTY_LICENSES.txt` | 第三方依赖及开源许可证说明 | 合规、再发布或审计 |

### 快速选择

- Linux 或 Host Wine：下载 `palpanel_{{RELEASE_TAG}}_linux_amd64.tar.gz`。
- Windows：下载 `palpanel_{{RELEASE_TAG}}_windows_amd64.zip`。
- 普通用户不需要下载源码包或 SBOM。
- 安装前可使用 `SHA256SUMS` 核对下载文件的完整性。
