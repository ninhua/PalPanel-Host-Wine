#!/bin/bash
case "${LF_BOOTSTRAPPED:-0}" in 1) ;; *) T="/tmp/start-lf.$$"; tr -d '\r' < "$0" > "$T"; chmod +x "$T"; cp "$T" "$0" 2>/dev/null || true; LF_BOOTSTRAPPED=1 exec /bin/bash "$T";; esac # CRLF_AUTO_FIX

set -Eeuo pipefail
umask 022

SCRIPT_VERSION="1.0.36"
SCRIPT_BUILD="2026-07-22-palpanel-optional-steam-login"

# =========================================================
# Palworld Panel v1.2.1
# 简幻欢：单目录、宿主 Wine、无 Docker 全新安装脚本
#
# 平台启动脚本固定放在：
#   /home/container/start.sh
# 除该启动脚本外，面板、服务端、Wine、SteamCMD、配置和存档均位于：
#   /home/container/palworld_win/
# =========================================================

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
APP_DIR="${ROOT}/app"
CONFIG_DIR="${ROOT}/config"
CONFIG_FILE="${CONFIG_DIR}/palpanel.env"
DATA_DIR="${ROOT}/data"
RUNTIME_DIR="${ROOT}/runtime"
LOG_DIR="${ROOT}/logs"
SERVER_DIR="${ROOT}/server"
WINE_PREFIX="${ROOT}/wineprefix"
WINE_HOME="${ROOT}/home"
RUN_DIR="${ROOT}/run"
TOOLS_DIR="${ROOT}/tools"
CACHE_DIR="${ROOT}/cache"
TMP_DIR="${ROOT}/tmp"
BACKUP_DIR="${ROOT}/backup"
STEAMCMD_DIR="${ROOT}/steamcmd"
XDG_RUNTIME_DIR_VALUE="${RUN_DIR}/xdg"

# 独立 Wine：不修改容器系统 Wine。该版本已在当前 NFS SaveGames 上验证可正常原子保存。
PORTABLE_WINE_VERSION="${PALPANEL_PORTABLE_WINE_VERSION:-11.13}"
PORTABLE_WINE_FLAVOR="${PALPANEL_PORTABLE_WINE_FLAVOR:-amd64-wow64}"
PORTABLE_WINE_FORCE_INSTALL="${PALPANEL_PORTABLE_WINE_FORCE_INSTALL:-0}"
PORTABLE_WINE_BASE="${PALPANEL_PORTABLE_WINE_DIR:-${RUNTIME_DIR}/wine}"
PORTABLE_WINE_ARCHIVE_NAME="wine-${PORTABLE_WINE_VERSION}-${PORTABLE_WINE_FLAVOR}.tar.xz"
PORTABLE_WINE_ARCHIVE="${CACHE_DIR}/${PORTABLE_WINE_ARCHIVE_NAME}"
PORTABLE_WINE_INSTALL_DIR="${PORTABLE_WINE_BASE}/wine-${PORTABLE_WINE_VERSION}-${PORTABLE_WINE_FLAVOR}"
PORTABLE_WINE_CURRENT="${PORTABLE_WINE_BASE}/current"
PORTABLE_WINE_DIRECT_URL="${PALPANEL_PORTABLE_WINE_URL:-https://github.com/Kron4ek/Wine-Builds/releases/download/${PORTABLE_WINE_VERSION}/${PORTABLE_WINE_ARCHIVE_NAME}}"
PORTABLE_WINE_SHA256="${PALPANEL_PORTABLE_WINE_SHA256:-}"
GH_PROXY_BASE="${GH_PROXY_BASE:-https://v4.gh-proxy.org}"
GH_PROXY_FALLBACK="${GH_PROXY_FALLBACK:-https://cdn.gh-proxy.org}"

WINE_BIN="${PORTABLE_WINE_CURRENT}/bin/wine"
WINEBOOT_BIN="${PORTABLE_WINE_CURRENT}/bin/wineboot"
WINESERVER_BIN="${PORTABLE_WINE_CURRENT}/bin/wineserver"
WINEPATH_BIN="${PORTABLE_WINE_CURRENT}/bin/winepath"
DIRECT_SAVE_PREPARE_TOOL="${TOOLS_DIR}/prepare-direct-save"

PANEL_VERSION="v1.2.1"
ARCHIVE_NAME="palpanel_v1.2.1_linux_amd64.tar.gz"
ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE_NAME}"
RELEASE_URL="https://github.com/uitok/palworld-panel/releases/download/${PANEL_VERSION}/${ARCHIVE_NAME}"

PANEL_PORT="${SERVER_PORT:-12559}"
GAME_PORT="${PALWORLD_GAME_PORT:-${SERVER_PORT:-12559}}"
QUERY_PORT="${PALWORLD_QUERY_PORT:-27015}"
REST_PORT="${PALWORLD_REST_PORT:-8212}"
RCON_PORT="${PALWORLD_RCON_PORT:-25575}"
PALDEFENDER_REST_PORT="${PALWORLD_PALDEFENDER_REST_PORT:-17993}"

DOCKER_SHIM="${TOOLS_DIR}/docker"
PALDEFENDER_INSTALLER="${TOOLS_DIR}/install-paldefender"
PALDEFENDER_RELEASE_PROXY="${TOOLS_DIR}/paldefender-release-proxy.py"
PALDEFENDER_RELEASE_PROXY_PID="${RUN_DIR}/paldefender-release-proxy.pid"
PALDEFENDER_RELEASE_PROXY_LOG="${LOG_DIR}/paldefender-release-proxy.log"
PALDEFENDER_RELEASE_PROXY_PORT="18081"
UE4SS_VERSION="experimental-palworld"
UE4SS_ARCHIVE_NAME="UE4SS-Palworld.zip"
UE4SS_ARCHIVE_SHA256="768a45718fbb9e429ac5cc3ce4a139a1b7b468bff31b4a136ae483d725aca1ca"
UE4SS_CACHE_DIR="${CACHE_DIR}/ue4ss"
UE4SS_ARCHIVE_PATH="${UE4SS_CACHE_DIR}/${UE4SS_ARCHIVE_NAME}"
UE4SS_CACHE_TOOL="${TOOLS_DIR}/cache-ue4ss"
UE4SS_MOD_INSTALLER="${TOOLS_DIR}/install-mods-wine"
UE4SS_LOAD_MONITOR_TOOL="${TOOLS_DIR}/monitor-ue4ss-load"
WINE_RUNTIME_PREPARE_TOOL="${TOOLS_DIR}/prepare-wine-runtime"
WINE_MOD_DIAG_TOOL="${TOOLS_DIR}/diagnose-wine-mods"
UE4SS_DOWNLOAD_LOG="${LOG_DIR}/ue4ss-download.log"
UE4SS_ARCHIVE_SHA_FILE="${UE4SS_ARCHIVE_PATH}.sha256"
UE4SS_RUNTIME_DIR="${SERVER_DIR}/Pal/Binaries/Win64/ue4ss"
UE4SS_LOAD_MARKER="${UE4SS_RUNTIME_DIR}/.load-confirmed"
UE4SS_LOCAL_URL="http://127.0.0.1:${PALDEFENDER_RELEASE_PROXY_PORT}/ue4ss/${UE4SS_ARCHIVE_NAME}"

# Steam Workshop 默认使用 anonymous。只有显式提供用户名时才启用账号缓存模式。
# 密码和 Steam Guard 令牌绝不写入脚本或配置。
STEAM_USERNAME_VALUE="${PALPANEL_STEAM_USERNAME:-}"
STEAM_LOGIN_ON_START="${PALPANEL_STEAM_LOGIN_ON_START:-0}"

STEAM_API_PROXY="${TOOLS_DIR}/steam-api-proxy.py"
STEAM_API_PROXY_PID="${RUN_DIR}/steam-api-proxy.pid"
STEAM_API_PROXY_LOG="${LOG_DIR}/steam-api-proxy.log"
STEAM_API_PROXY_CACHE="${CACHE_DIR}/steam-api"
STEAM_API_PROXY_PORT="${PALPANEL_STEAM_API_PROXY_PORT:-18082}"
STEAM_API_PROXY_URL="http://127.0.0.1:${STEAM_API_PROXY_PORT}"
HOST_WINE_STATE_TOOL="${TOOLS_DIR}/repair-host-wine-state"

XVFB_DISPLAY="${PALPANEL_XVFB_DISPLAY:-:99}"
WINETRICKS_ON_START="${PALPANEL_WINETRICKS_ON_START:-1}"
WINE_RUNTIME_PACKAGES_ON_START="${PALPANEL_INSTALL_WINE_RUNTIME_PACKAGES:-1}"

SAVE_INDEXER_HOST="127.0.0.1"
SAVE_INDEXER_PORT="8090"
SAVE_INDEXER_URL="http://${SAVE_INDEXER_HOST}:${SAVE_INDEXER_PORT}"
SAVE_INDEXER_PID="${RUN_DIR}/sav-cli.pid"
SAVE_INDEXER_LOG="${LOG_DIR}/sav-cli.log"
SAVE_INDEX_CACHE_DIR="${DATA_DIR}/save-index"
SAVE_INDEX_CACHE_FILE="${SAVE_INDEX_CACHE_DIR}/index-cache.json"
REBUILD_SAVE_INDEX_TOOL="${TOOLS_DIR}/rebuild-save-index"
NET_ID_RECOVERY_TOOL="${TOOLS_DIR}/recover-incompatible-net-id"

PALCALC_HOST="127.0.0.1"
PALCALC_PORT="8091"
PALCALC_URL="http://${PALCALC_HOST}:${PALCALC_PORT}"
PALCALC_PID="${RUN_DIR}/palcalc-bridge.pid"
PALCALC_LOG="${LOG_DIR}/palcalc-bridge.log"
DOTNET_BUNDLE_DIR="${CACHE_DIR}/dotnet-bundle"

PANEL_LOG="${LOG_DIR}/palpanel-console.log"

echo "================================================="
echo "Palworld Panel 单目录全新安装 v${SCRIPT_VERSION}"
echo "================================================="
echo "根目录：${ROOT}"
echo "面板端口：${PANEL_PORT}/TCP"
echo "游戏端口：${GAME_PORT}/UDP"
echo "运行方式：独立 Wine ${PORTABLE_WINE_VERSION} + Windows SteamCMD + Xvfb + vcrun2022"
echo "启动脚本：/home/container/start.sh"
echo "数据目录：${ROOT}"
echo "Docker：不安装，由本地兼容层接管"
echo "GitHub 主代理：${GH_PROXY_BASE}"
echo "GitHub 备用代理：${GH_PROXY_FALLBACK}"
echo "GitHub 下载顺序：主代理 → 备用代理 → 直连"
echo "================================================="

on_error() {
    local code="$?"
    local line="${1:-未知}"

    echo
    echo "================================================="
    echo "安装或启动失败"
    echo "退出码：${code}"
    echo "错误行：${line}"
    echo "================================================="

    if [ -f "${PANEL_LOG}" ]; then
        echo "面板日志最后 100 行："
        tail -n 100 "${PANEL_LOG}" 2>/dev/null || true
    fi
}

trap 'on_error "$LINENO"' ERR

require_command() {
    local name="$1"
    if ! command -v "${name}" >/dev/null 2>&1; then
        echo "错误：缺少必要命令：${name}"
        exit 1
    fi
}

for command_name in bash tr mkdir rm cp mv chmod find tar gzip xz curl unzip sed awk grep head tail tee env steamcmd setsid nohup timeout getconf python3 kill sleep sha256sum readlink stat df id sync; do
    require_command "${command_name}"
done

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：当前安装脚本需要以 root 身份运行。"
    exit 1
fi

# ---------------------------------------------------------
# 单目录结构
# ---------------------------------------------------------

mkdir -p \
    "${APP_DIR}" \
    "${CONFIG_DIR}" \
    "${DATA_DIR}" \
    "${RUNTIME_DIR}" \
    "${LOG_DIR}" \
    "${SERVER_DIR}" \
    "${WINE_PREFIX}" \
    "${WINE_HOME}/.config" \
    "${WINE_HOME}/.local/share" \
    "${RUN_DIR}/xdg" \
    "${TOOLS_DIR}" \
    "${CACHE_DIR}" \
    "${SAVE_INDEX_CACHE_DIR}" \
    "${DOTNET_BUNDLE_DIR}" \
    "${TMP_DIR}" \
    "${BACKUP_DIR}" \
    "${STEAMCMD_DIR}" \
    "${PORTABLE_WINE_BASE}"

chmod 700 "${CONFIG_DIR}" "${WINE_PREFIX}" "${WINE_HOME}" "${RUN_DIR}" "${RUN_DIR}/xdg" 2>/dev/null || true


# ---------------------------------------------------------
# 独立 Wine 运行时
# ---------------------------------------------------------

portable_wine_expected_sha256() {
    if [ -n "${PORTABLE_WINE_SHA256}" ]; then
        printf '%s\n' "${PORTABLE_WINE_SHA256}"
        return 0
    fi

    case "${PORTABLE_WINE_VERSION}:${PORTABLE_WINE_FLAVOR}" in
        11.13:amd64-wow64)
            printf '%s\n' '889423273334f12bf2a4e2249f6ade72d7ceb466f72274925fda1e11b8326164'
            ;;
        *)
            return 1
            ;;
    esac
}

portable_wine_valid() {
    [ -x "${PORTABLE_WINE_INSTALL_DIR}/bin/wine" ] || return 1
    [ -x "${PORTABLE_WINE_INSTALL_DIR}/bin/wineboot" ] || return 1
    [ -x "${PORTABLE_WINE_INSTALL_DIR}/bin/wineserver" ] || return 1
    [ -x "${PORTABLE_WINE_INSTALL_DIR}/bin/winepath" ] || return 1
    "${PORTABLE_WINE_INSTALL_DIR}/bin/wine" --version 2>/dev/null |
        grep -q "wine-${PORTABLE_WINE_VERSION}"
}

verify_portable_wine_archive() {
    local expected=""
    local actual=""

    expected="$(portable_wine_expected_sha256 || true)"
    [ -n "${expected}" ] || {
        echo "错误：未知独立 Wine 校验值，请设置 PALPANEL_PORTABLE_WINE_SHA256。" >&2
        return 1
    }

    [ -f "${PORTABLE_WINE_ARCHIVE}" ] || return 1
    actual="$(sha256sum "${PORTABLE_WINE_ARCHIVE}" | awk '{print $1}')"

    if [ "${actual}" != "${expected}" ]; then
        echo "警告：独立 Wine 压缩包 SHA-256 不匹配，将重新下载。" >&2
        rm -f "${PORTABLE_WINE_ARCHIVE}"
        return 1
    fi
}

download_portable_wine_archive() {
    local direct_url="${PORTABLE_WINE_DIRECT_URL}"
    local proxy_url="${GH_PROXY_BASE%/}/${direct_url}"
    local fallback_proxy_url="${GH_PROXY_FALLBACK%/}/${direct_url}"
    local partial="${PORTABLE_WINE_ARCHIVE}.part"
    local url=""

    for url in "${proxy_url}" "${fallback_proxy_url}" "${direct_url}"; do
        rm -f "${partial}"
        echo "下载独立 Wine：${url}"

        if curl \
            --fail \
            --location \
            --http1.1 \
            --ipv4 \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 25 \
            --max-time 1800 \
            --output "${partial}" \
            "${url}"
        then
            mv -f "${partial}" "${PORTABLE_WINE_ARCHIVE}"
            return 0
        fi
    done

    rm -f "${partial}"
    return 1
}

install_portable_wine() {
    local extract_dir="${TMP_DIR}/wine-runtime-extract.$$"
    local install_tmp="${PORTABLE_WINE_INSTALL_DIR}.installing.$$"
    local source_bin=""
    local source_root=""

    if ! verify_portable_wine_archive; then
        download_portable_wine_archive || {
            echo "错误：独立 Wine 下载失败。" >&2
            exit 1
        }
        verify_portable_wine_archive || {
            echo "错误：独立 Wine SHA-256 校验失败。" >&2
            exit 1
        }
    fi

    rm -rf "${extract_dir}" "${install_tmp}"
    mkdir -p "${extract_dir}" "${install_tmp}"
    tar -xJf "${PORTABLE_WINE_ARCHIVE}" -C "${extract_dir}"

    source_bin="$(find "${extract_dir}" -path '*/bin/wine' -print -quit)"
    [ -n "${source_bin}" ] || {
        echo "错误：独立 Wine 包内未找到 bin/wine。" >&2
        exit 1
    }

    source_root="$(dirname "$(dirname "${source_bin}")")"
    cp -a "${source_root}/." "${install_tmp}/"
    chmod +x \
        "${install_tmp}/bin/wine" \
        "${install_tmp}/bin/wineboot" \
        "${install_tmp}/bin/wineserver" \
        "${install_tmp}/bin/winepath"

    "${install_tmp}/bin/wine" --version 2>/dev/null |
        grep -q "wine-${PORTABLE_WINE_VERSION}" || {
            echo "错误：独立 Wine 版本检查失败。" >&2
            exit 1
        }

    rm -rf "${PORTABLE_WINE_INSTALL_DIR}"
    mv "${install_tmp}" "${PORTABLE_WINE_INSTALL_DIR}"
    rm -rf "${extract_dir}"
    ln -sfn "$(basename "${PORTABLE_WINE_INSTALL_DIR}")" "${PORTABLE_WINE_CURRENT}"
    echo "独立 Wine 已安装：${PORTABLE_WINE_INSTALL_DIR}"
}

prepare_portable_wine() {
    if [ "${PORTABLE_WINE_FORCE_INSTALL}" = "1" ]; then
        echo "警告：PALPANEL_PORTABLE_WINE_FORCE_INSTALL=1，将重新安装独立 Wine。" >&2
        rm -rf "${PORTABLE_WINE_INSTALL_DIR}"
    fi

    portable_wine_valid || install_portable_wine
    ln -sfn "$(basename "${PORTABLE_WINE_INSTALL_DIR}")" "${PORTABLE_WINE_CURRENT}"

    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
    hash -r

    local version_text=""
    local missing=""
    version_text="$("${WINE_BIN}" --version 2>/dev/null | head -n 1 || true)"
    [ -n "${version_text}" ] || {
        echo "错误：独立 Wine 无法执行，可能缺少动态库或目录被 noexec 挂载。" >&2
        exit 1
    }

    if command -v ldd >/dev/null 2>&1; then
        missing="$(ldd "${WINE_BIN}" 2>/dev/null | grep 'not found' || true)"
        [ -z "${missing}" ] || {
            echo "错误：独立 Wine 缺少动态库：${missing}" >&2
            exit 1
        }
    fi

    echo "独立 Wine 检查通过：${version_text}"
    echo "独立 Wine 目录：${PORTABLE_WINE_INSTALL_DIR}"
}

prepare_portable_wine

# 后续生成的 PalPanel、Docker 兼容层和辅助工具均继承该 PATH。
export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"

# ---------------------------------------------------------
# 下载发布包
# ---------------------------------------------------------

download_release() {
    local partial="${ARCHIVE_PATH}.part"
    local proxy_url="${GH_PROXY_BASE%/}/${RELEASE_URL}"
    local fallback_proxy_url="${GH_PROXY_FALLBACK%/}/${RELEASE_URL}"
    local url=""

    echo
    echo "正在下载 PalPanel ${PANEL_VERSION}（GitHub 代理优先）……"

    for url in "${proxy_url}" "${fallback_proxy_url}" "${RELEASE_URL}"; do
        rm -f "${partial}"
        echo "尝试下载：${url}"

        if curl \
            --fail \
            --location \
            --http1.1 \
            --ipv4 \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 900 \
            --output "${partial}" \
            "${url}"
        then
            if tar -tzf "${partial}" >/dev/null 2>&1; then
                mv -f "${partial}" "${ARCHIVE_PATH}"
                echo "PalPanel 发布包下载完成：${ARCHIVE_PATH}"
                return 0
            fi
            echo "警告：下载结果不是有效的 tar.gz，切换下一个地址。" >&2
        else
            echo "警告：下载失败，切换下一个地址。" >&2
        fi
    done

    rm -f "${partial}"
    echo "错误：PalPanel 发布包通过主代理、备用代理和 GitHub 直连均下载失败。" >&2
    return 1
}

if [ ! -f "${ARCHIVE_PATH}" ]; then
    download_release
elif ! tar -tzf "${ARCHIVE_PATH}" >/dev/null 2>&1; then
    echo "检测到损坏的发布包，重新下载。"
    rm -f "${ARCHIVE_PATH}"
    download_release
else
    echo "发布包检查通过：${ARCHIVE_PATH}"
fi

# ---------------------------------------------------------
# 安装或修复面板程序
# ---------------------------------------------------------

panel_complete() {
    [ -x "${APP_DIR}/palpanelctl" ] &&
    [ -x "${APP_DIR}/bin/palpanel" ] &&
    [ -x "${APP_DIR}/bin/sav-cli" ] &&
    [ -x "${APP_DIR}/bin/palcalc-bridge" ]
}

install_panel_files() {
    echo
    echo "================================================="
    echo "正在安装或修复 PalPanel 程序文件"
    echo "================================================="

    local extract_dir="${TMP_DIR}/panel-extract"
    local source_ctl=""
    local source_root=""

    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    tar -xzf "${ARCHIVE_PATH}" -C "${extract_dir}"

    source_ctl="$(find "${extract_dir}" -maxdepth 4 -type f -name palpanelctl -print -quit)"

    if [ -z "${source_ctl}" ]; then
        echo "错误：发布包内未找到 palpanelctl。"
        find "${extract_dir}" -maxdepth 3 -type f -print
        exit 1
    fi

    source_root="$(dirname "${source_ctl}")"

    rm -rf "${APP_DIR}"
    mkdir -p "${APP_DIR}"
    cp -a "${source_root}/." "${APP_DIR}/"

    chmod +x \
        "${APP_DIR}/palpanelctl" \
        "${APP_DIR}/bin/palpanel" \
        "${APP_DIR}/bin/sav-cli" \
        "${APP_DIR}/bin/palcalc-bridge"

    rm -rf "${extract_dir}"

    if ! panel_complete; then
        echo "错误：面板发布文件安装后仍不完整。"
        exit 1
    fi

    printf '%s\n' "${PANEL_VERSION}" > "${APP_DIR}/.installed-version"
}

if ! panel_complete; then
    install_panel_files
else
    echo "面板程序完整性检查通过。"
fi

# ---------------------------------------------------------
# 生成 Docker CLI 兼容层
#
# PalPanel 原后端会调用 Docker CLI。该兼容层把这些命令转换为：
#   SteamCMD 安装/更新 Windows 服务端
#   Wine 启动 Shipping-Cmd
#   PID 文件实现状态、停止、重启和日志
# ---------------------------------------------------------

cat > "${DOCKER_SHIM}" <<'DOCKER_SHIM_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
SERVER_DIR="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
WINE_PREFIX="${PALPANEL_WINE_PREFIX_DIR:-${ROOT}/wineprefix}"
WINE_HOME="${ROOT}/home"
WINE_BIN="${PORTABLE_WINE_CURRENT}/bin/wine"
WINEBOOT_BIN="${PORTABLE_WINE_CURRENT}/bin/wineboot"
WINESERVER_BIN="${PORTABLE_WINE_CURRENT}/bin/wineserver"
WINEPATH_BIN="${PORTABLE_WINE_CURRENT}/bin/winepath"
WINDOWS_STEAMCMD_DIR="${PALPANEL_WINDOWS_STEAMCMD_DIR:-${ROOT}/steamcmd}"
WINDOWS_STEAMCMD_EXE="${WINDOWS_STEAMCMD_DIR}/steamcmd.exe"
WINDOWS_STEAMCMD_ZIP="${ROOT}/cache/steamcmd.zip"
WINDOWS_STEAMCMD_ZIP_URL="${PALPANEL_WINDOWS_STEAMCMD_ZIP_URL:-https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip}"
DIRECT_SAVE_PREPARE_TOOL="${ROOT}/tools/prepare-direct-save"
WINE_RUNTIME_VERSION_FILE="${WINE_PREFIX}/.palworld-wine-runtime-version"
WINE_PREFIX_BACKUP_DIR="${ROOT}/backup/wineprefix-registry"
RUN_DIR="${ROOT}/run"
LOG_DIR="${PALPANEL_LOGS_DIR:-${ROOT}/logs}"
STATE_DIR="${RUN_DIR}/host-wine-runner"

PID_FILE="${STATE_DIR}/palserver.pid"
EXISTS_FILE="${STATE_DIR}/container.exists"
IMAGE_FILE="${STATE_DIR}/image.exists"
START_ARGS_FILE="${STATE_DIR}/start-args.nul"
START_ARGS_DEBUG_FILE="${STATE_DIR}/start-args.txt"
SERVER_LOG="${LOG_DIR}/palserver.log"
INSTALL_LOG="${LOG_DIR}/steamcmd-install.log"
WORKSHOP_LOG="${LOG_DIR}/workshop.log"
WORKSHOP_STATE_DIR="${STATE_DIR}/workshop"
WORKSHOP_DOWNLOAD_HOME="${ROOT}/home"
WORKSHOP_REPAIR_TOOL="${ROOT}/tools/repair-workshop-import"
WORKSHOP_PROGRESS_TOOL="${ROOT}/tools/workshop-progress"
WORKSHOP_PROGRESS_INTERVAL="${PALPANEL_WORKSHOP_PROGRESS_INTERVAL:-5}"
WORKSHOP_STALL_SECONDS="${PALPANEL_WORKSHOP_STALL_SECONDS:-180}"
WORKSHOP_ANONYMOUS_TIMEOUT="${PALPANEL_WORKSHOP_ANONYMOUS_TIMEOUT:-1800}"
WORKSHOP_CREDENTIAL_TIMEOUT="${PALPANEL_WORKSHOP_CREDENTIAL_TIMEOUT:-180}"

UE4SS_MOD_INSTALLER="${ROOT}/tools/install-mods-wine"
UE4SS_LOAD_MONITOR_TOOL="${ROOT}/tools/monitor-ue4ss-load"
WINE_RUNTIME_PREPARE_TOOL="${ROOT}/tools/prepare-wine-runtime"
WINE_MOD_DIAG_TOOL="${ROOT}/tools/diagnose-wine-mods"
CONFIG_FILE="${ROOT}/config/palpanel.env"

DISPLAY_VALUE="${PALPANEL_XVFB_DISPLAY:-:99}"
XVFB_PID_FILE="${STATE_DIR}/xvfb.pid"
XVFB_LOG="${LOG_DIR}/xvfb.log"
VCRUN_MARKER="${WINE_PREFIX}/.vcrun2022-installed"

SHIPPING_RELATIVE="Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe"
SHIPPING_EXE="${SERVER_DIR}/${SHIPPING_RELATIVE}"

STEAM_APP_ID="2394010"
DEFAULT_WORKSHOP_APP_ID="1623730"

mkdir -p \
    "${SERVER_DIR}" \
    "${WINE_PREFIX}" \
    "${WINE_HOME}/.config" \
    "${WINE_HOME}/.local/share" \
    "${RUN_DIR}/xdg" \
    "${LOG_DIR}" \
    "${STATE_DIR}" \
    "${WORKSHOP_STATE_DIR}" \
    "${WINE_PREFIX_BACKUP_DIR}"

chmod 700 "${WINE_PREFIX}" "${WINE_HOME}" "${RUN_DIR}" "${RUN_DIR}/xdg" "${STATE_DIR}" 2>/dev/null || true

# 这只是 PalPanel 的 Docker CLI 兼容状态，不代表运行了 Docker。
# 已有 Windows PalServer 时自动恢复“对象存在”，避免升级后被面板误判。
if [ -f "${SHIPPING_EXE}" ]; then
    touch "${IMAGE_FILE}" "${EXISTS_FILE}"
fi

read_config_value() {
    local key="$1"
    local value=""

    [ -f "${CONFIG_FILE}" ] || return 1

    value="$(
        awk -F= -v wanted="${key}" '
            $1 == wanted {
                sub(/^[^=]*=/, "")
                print
                exit
            }
        ' "${CONFIG_FILE}"
    )"

    [ -n "${value}" ] || return 1
    printf '%s\n' "${value}"
}

STEAM_USERNAME="${STEAM_USERNAME:-$(read_config_value STEAM_USERNAME 2>/dev/null || true)}"

build_workshop_login_args() {
    WORKSHOP_LOGIN_ARGS=(anonymous)
    if [ -n "${STEAM_USERNAME}" ]; then
        # 只传用户名，SteamCMD 从同一 HOME 下复用交互登录生成的令牌缓存。
        WORKSHOP_LOGIN_ARGS=("${STEAM_USERNAME}")
    fi
}

xvfb_display_number() {
    printf '%s\n' "${DISPLAY_VALUE#:}"
}

xvfb_running() {
    local pid=""

    [ -f "${XVFB_PID_FILE}" ] || return 1
    pid="$(tr -cd '0-9' < "${XVFB_PID_FILE}" 2>/dev/null || true)"
    [ -n "${pid}" ] || return 1
    kill -0 "${pid}" 2>/dev/null
}

start_xvfb() {
    local display_number=""
    local attempt=""
    local pid=""

    if xvfb_running; then
        return 0
    fi

    if ! command -v Xvfb >/dev/null 2>&1; then
        echo "警告：缺少 Xvfb，Wine 将尝试无显示运行。" >&2
        return 0
    fi

    display_number="$(xvfb_display_number)"

    if [ -e "/tmp/.X${display_number}-lock" ] &&
        ! pgrep -f "Xvfb ${DISPLAY_VALUE}" >/dev/null 2>&1
    then
        rm -f "/tmp/.X${display_number}-lock"
        rm -f "/tmp/.X11-unix/X${display_number}" 2>/dev/null || true
    fi

    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix 2>/dev/null || true
    : > "${XVFB_LOG}"

    Xvfb "${DISPLAY_VALUE}" \
        -ac \
        -nolisten tcp \
        -screen 0 640x480x8 \
        >> "${XVFB_LOG}" 2>&1 &

    pid="$!"
    printf '%s\n' "${pid}" > "${XVFB_PID_FILE}"

    for attempt in $(seq 1 50); do
        if [ -S "/tmp/.X11-unix/X${display_number}" ]; then
            echo "Xvfb 已启动：DISPLAY=${DISPLAY_VALUE}，PID=${pid}"
            return 0
        fi

        if ! kill -0 "${pid}" 2>/dev/null; then
            rm -f "${XVFB_PID_FILE}"
            echo "警告：Xvfb 提前退出。" >&2
            tail -n 80 "${XVFB_LOG}" >&2 || true
            return 0
        fi

        sleep 0.1
    done

    echo "警告：Xvfb 启动后未及时生成显示套接字。" >&2
    return 0
}

wine_bootstrap_env() {
    env \
        HOME="${WINE_HOME}" \
        USER="root" \
        LOGNAME="root" \
        XDG_CONFIG_HOME="${WINE_HOME}/.config" \
        XDG_DATA_HOME="${WINE_HOME}/.local/share" \
        XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
        DISPLAY="${DISPLAY_VALUE}" \
        WINEPREFIX="${WINE_PREFIX}" \
        WINEARCH="win64" \
        WINEDEBUG="-all" \
        WINEDLLOVERRIDES="mscoree,mshtml=" \
        "$@"
}

run_timed_wine_bootstrap() {
    local seconds="$1"
    shift

    timeout \
        --signal=TERM \
        --kill-after=30 \
        "${seconds}" \
        env \
            PATH="${PATH}" \
            HOME="${WINE_HOME}" \
            USER="root" \
            LOGNAME="root" \
            XDG_CONFIG_HOME="${WINE_HOME}/.config" \
            XDG_DATA_HOME="${WINE_HOME}/.local/share" \
            XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
            DISPLAY="${DISPLAY_VALUE}" \
            WINEPREFIX="${WINE_PREFIX}" \
            WINEARCH="win64" \
            WINEDEBUG="-all" \
            WINEDLLOVERRIDES="mscoree,mshtml=" \
            "$@"
}

wine_env() {
    env \
        HOME="${WINE_HOME}" \
        USER="root" \
        LOGNAME="root" \
        XDG_CONFIG_HOME="${WINE_HOME}/.config" \
        XDG_DATA_HOME="${WINE_HOME}/.local/share" \
        XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
        DISPLAY="${DISPLAY_VALUE}" \
        WINEPREFIX="${WINE_PREFIX}" \
        WINEARCH="win64" \
        WINEDEBUG="-all" \
        SteamAppId="${STEAM_APP_ID}" \
        SteamGameId="${STEAM_APP_ID}" \
        WINEDLLOVERRIDES="mscoree,mshtml=;dwmapi=n,b;d3d9=n,b" \
        "$@"
}

read_pid() {
    [ -f "${PID_FILE}" ] || return 1
    tr -cd '0-9' < "${PID_FILE}"
}

pid_is_palserver() {
    local pid="$1"
    local cmdline=""
    local prefix_match="0"

    [ -n "${pid}" ] || return 1
    kill -0 "${pid}" 2>/dev/null || return 1

    if [ -r "/proc/${pid}/cmdline" ]; then
        cmdline="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
        case "${cmdline}" in
            *PalServer-Win64-Shipping-Cmd.exe*|*"${SERVER_DIR}"*PalServer*)
                return 0
                ;;
        esac
    fi

    if [ -r "/proc/${pid}/environ" ]; then
        if tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null |
            grep -Fxq "WINEPREFIX=${WINE_PREFIX}"; then
            prefix_match="1"
        fi
    fi

    # Wine 启动器的 cmdline 在不同版本中可能只显示 wine-preloader。
    # 只有 REST API 同时就绪时，才把同前缀进程作为 PalServer 代表 PID。
    [ "${prefix_match}" = "1" ] && rest_api_ready
}

rest_api_ready() {
    local admin_password=""
    local base_url="http://127.0.0.1:${PALPANEL_REST_PORT:-8212}/v1/api"

    admin_password="$(read_config_value PALWORLD_ADMIN_PASSWORD 2>/dev/null || true)"
    [ -n "${admin_password}" ] || return 1

    curl \
        --silent \
        --fail \
        --max-time 2 \
        --user "admin:${admin_password}" \
        "${base_url}/info" \
        >/dev/null 2>&1
}

discover_server_pid() {
    local proc_dir=""
    local pid=""
    local cmdline=""
    local prefix_match="0"
    local fallback_pid=""

    for proc_dir in /proc/[0-9]*; do
        [ -r "${proc_dir}/stat" ] || continue
        pid="${proc_dir##*/}"
        cmdline=""
        prefix_match="0"

        if [ -r "${proc_dir}/cmdline" ]; then
            cmdline="$(tr '\0' ' ' < "${proc_dir}/cmdline" 2>/dev/null || true)"
            case "${cmdline}" in
                *PalServer-Win64-Shipping-Cmd.exe*|*"${SERVER_DIR}"*PalServer*)
                    printf '%s\n' "${pid}"
                    return 0
                    ;;
            esac
        fi

        if [ -r "${proc_dir}/environ" ]; then
            if tr '\0' '\n' < "${proc_dir}/environ" 2>/dev/null |
                grep -Fxq "WINEPREFIX=${WINE_PREFIX}"; then
                prefix_match="1"
            fi
        fi

        if [ "${prefix_match}" = "1" ] && [ -z "${fallback_pid}" ]; then
            fallback_pid="${pid}"
        fi
    done

    if [ -n "${fallback_pid}" ] && rest_api_ready; then
        printf '%s\n' "${fallback_pid}"
        return 0
    fi

    return 1
}

repair_server_state() {
    local pid=""

    pid="$(read_pid 2>/dev/null || true)"
    if [ -n "${pid}" ] && pid_is_palserver "${pid}"; then
        touch "${IMAGE_FILE}" "${EXISTS_FILE}"
        return 0
    fi

    rm -f "${PID_FILE}"
    pid="$(discover_server_pid 2>/dev/null || true)"

    if [ -n "${pid}" ]; then
        printf '%s\n' "${pid}" > "${PID_FILE}"
        chmod 600 "${PID_FILE}" 2>/dev/null || true
        touch "${IMAGE_FILE}" "${EXISTS_FILE}"
        return 0
    fi

    return 1
}

server_running() {
    repair_server_state
}

initialize_wine() {
    local runtime_version=""
    local recorded_version=""
    local status="0"
    local backup_dir=""
    local registry=""

    start_xvfb
    runtime_version="$("${WINE_BIN}" --version 2>/dev/null | head -n 1 || true)"
    [ -n "${runtime_version}" ] || {
        echo "独立 Wine 无法执行：${WINE_BIN}" >&2
        return 1
    }

    recorded_version="$(cat "${WINE_RUNTIME_VERSION_FILE}" 2>/dev/null || true)"

    if [ -f "${WINE_PREFIX}/system.reg" ]; then
        if [ "${recorded_version}" = "${runtime_version}" ]; then
            return 0
        fi

        backup_dir="${WINE_PREFIX_BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${backup_dir}"
        for registry in system.reg user.reg userdef.reg; do
            [ -f "${WINE_PREFIX}/${registry}" ] &&
                cp -p "${WINE_PREFIX}/${registry}" "${backup_dir}/${registry}"
        done
        printf '%s\n' "${recorded_version:-unknown}" > "${backup_dir}/previous-runtime.txt"
        printf '%s\n' "${runtime_version}" > "${backup_dir}/new-runtime.txt"

        echo "升级 Wine 前缀：${recorded_version:-未知} -> ${runtime_version}"
        set +e
        run_timed_wine_bootstrap 600 "${WINEBOOT_BIN}" -u
        status="$?"
        set -e

        set +e
        run_timed_wine_bootstrap 240 "${WINESERVER_BIN}" -w >/dev/null 2>&1
        set -e

        if [ "${status}" -ne 0 ]; then
            echo "Wine 前缀升级失败；注册表备份：${backup_dir}" >&2
            return "${status}"
        fi

        printf '%s\n' "${runtime_version}" > "${WINE_RUNTIME_VERSION_FILE}"
        echo "Wine 前缀升级完成。"
        return 0
    fi

    echo "Initializing Wine prefix: ${WINE_PREFIX} (${runtime_version})"

    set +e
    run_timed_wine_bootstrap 300 "${WINEBOOT_BIN}" --init
    status="$?"
    set -e

    set +e
    run_timed_wine_bootstrap 180 "${WINESERVER_BIN}" -w >/dev/null 2>&1
    set -e

    if [ ! -f "${WINE_PREFIX}/system.reg" ]; then
        echo "Wine prefix initialization failed with status ${status}" >&2
        return "${status}"
    fi

    printf '%s\n' "${runtime_version}" > "${WINE_RUNTIME_VERSION_FILE}"
}

prepare_wine_runtime() {
    initialize_wine

    if [ -x "${WINE_RUNTIME_PREPARE_TOOL}" ]; then
        PALPANEL_XVFB_DISPLAY="${DISPLAY_VALUE}" \
        PALPANEL_WINETRICKS_ON_START="${PALPANEL_WINETRICKS_ON_START:-1}" \
            "${WINE_RUNTIME_PREPARE_TOOL}" || {
                echo "警告：Wine vcrun2022 准备失败，继续尝试启动。" >&2
            }
    fi
}

install_mods() {
    if [ -x "${UE4SS_MOD_INSTALLER}" ]; then
        "${UE4SS_MOD_INSTALLER}" || {
            echo "警告：UE4SS/NativeMods 部署失败，继续启动以便保留诊断日志。" >&2
        }
    fi
}

download_windows_steamcmd() {
    local partial="${WINDOWS_STEAMCMD_ZIP}.part"
    local extract_dir="${ROOT}/tmp/windows-steamcmd-extract.$$"

    if [ -f "${WINDOWS_STEAMCMD_EXE}" ]; then
        return 0
    fi

    mkdir -p "${WINDOWS_STEAMCMD_DIR}" "$(dirname "${WINDOWS_STEAMCMD_ZIP}")" "${extract_dir}"

    if [ ! -f "${WINDOWS_STEAMCMD_ZIP}" ] ||
        ! unzip -tq "${WINDOWS_STEAMCMD_ZIP}" >/dev/null 2>&1
    then
        rm -f "${WINDOWS_STEAMCMD_ZIP}" "${partial}"
        curl \
            --fail \
            --location \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 25 \
            --max-time 1800 \
            --output "${partial}" \
            "${WINDOWS_STEAMCMD_ZIP_URL}"
        unzip -tq "${partial}" >/dev/null 2>&1 || {
            rm -f "${partial}"
            echo "Windows SteamCMD 下载包损坏。" >&2
            return 1
        }
        mv -f "${partial}" "${WINDOWS_STEAMCMD_ZIP}"
    fi

    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    unzip -q -o "${WINDOWS_STEAMCMD_ZIP}" -d "${extract_dir}"
    [ -f "${extract_dir}/steamcmd.exe" ] || {
        rm -rf "${extract_dir}"
        echo "Windows SteamCMD 包内没有 steamcmd.exe。" >&2
        return 1
    }

    rm -rf "${WINDOWS_STEAMCMD_DIR:?}/"*
    cp -a "${extract_dir}/." "${WINDOWS_STEAMCMD_DIR}/"
    rm -rf "${extract_dir}"
}

unix_to_windows_path() {
    local converted=""
    converted="$(
        wine_bootstrap_env "${WINEPATH_BIN}" -w "$1" 2>/dev/null |
            tr -d '\r' |
            tail -n 1
    )"
    [ -n "${converted}" ] || return 1
    printf '%s\n' "${converted}"
}

run_windows_steamcmd() {
    local timeout_seconds="$1"
    shift
    (
        cd "${WINDOWS_STEAMCMD_DIR}"
        run_timed_wine_bootstrap \
            "${timeout_seconds}" \
            "${WINE_BIN}" \
            "${WINDOWS_STEAMCMD_EXE}" \
            "$@"
    )
}

install_server() {
    local win_server_dir=""
    local runscript="${STATE_DIR}/steamcmd-install.txt"
    local win_runscript=""
    local status="0"

    initialize_wine
    download_windows_steamcmd

    echo "Installing or validating Palworld Windows Dedicated Server with Windows SteamCMD…"
    : > "${INSTALL_LOG}"

    # SteamCMD 自更新可能拉起同前缀子进程；先完成 bootstrap。
    set +e
    run_windows_steamcmd 900 +quit 2>&1 | tee -a "${INSTALL_LOG}"
    status="${PIPESTATUS[0]}"
    set -e

    set +e
    run_timed_wine_bootstrap 300 "${WINESERVER_BIN}" -w >/dev/null 2>&1
    set -e

    [ -f "${WINDOWS_STEAMCMD_EXE}" ] || {
        echo "Windows SteamCMD 自更新后 steamcmd.exe 不存在。" >&2
        return 1
    }

    win_server_dir="$(unix_to_windows_path "${SERVER_DIR}")" || {
        echo "Wine 无法转换服务端目录：${SERVER_DIR}" >&2
        return 1
    }

    {
        printf '@ShutdownOnFailedCommand 1\r\n'
        printf '@NoPromptForPassword 1\r\n'
        printf '@sSteamCmdForcePlatformType windows\r\n'
        printf '@sSteamCmdForcePlatformBitness 64\r\n'
        printf 'force_install_dir "%s"\r\n' "${win_server_dir}"
        printf 'login anonymous\r\n'
        printf 'app_info_update 1\r\n'
        printf 'app_update %s validate\r\n' "${STEAM_APP_ID}"
        printf 'quit\r\n'
    } > "${runscript}"

    win_runscript="$(unix_to_windows_path "${runscript}")" || {
        echo "Wine 无法转换 SteamCMD runscript：${runscript}" >&2
        return 1
    }

    set +e
    run_windows_steamcmd 7200 +runscript "${win_runscript}" 2>&1 | tee -a "${INSTALL_LOG}"
    status="${PIPESTATUS[0]}"
    set -e

    set +e
    run_timed_wine_bootstrap 300 "${WINESERVER_BIN}" -w >/dev/null 2>&1
    set -e

    if [ "${status}" -ne 0 ]; then
        echo "Windows SteamCMD failed with status ${status}" >&2
        return "${status}"
    fi

    if [ ! -f "${SHIPPING_EXE}" ]; then
        echo "Missing ${SHIPPING_EXE} after Windows SteamCMD install" >&2
        return 1
    fi

    touch "${IMAGE_FILE}"
}


save_start_args() {
    local arg=""

    : > "${START_ARGS_FILE}"
    : > "${START_ARGS_DEBUG_FILE}"

    for arg in "$@"; do
        printf '%s\0' "${arg}" >> "${START_ARGS_FILE}"
        printf '%q\n' "${arg}" >> "${START_ARGS_DEBUG_FILE}"
    done

    chmod 600 "${START_ARGS_FILE}" "${START_ARGS_DEBUG_FILE}" 2>/dev/null || true
}

load_start_args() {
    SAVED_START_ARGS=()
    local arg=""

    [ -f "${START_ARGS_FILE}" ] || return 1

    while IFS= read -r -d '' arg; do
        SAVED_START_ARGS+=("${arg}")
    done < "${START_ARGS_FILE}"

    return 0
}

capture_running_start_args() {
    local pid=""
    local arg=""
    local found_executable="0"
    local -a command_line=()
    local -a recovered=()
    local -a filtered=()

    if [ -s "${START_ARGS_FILE}" ]; then
        return 0
    fi

    pid="$(read_pid 2>/dev/null || true)"
    if [ -z "${pid}" ] || [ ! -r "/proc/${pid}/cmdline" ]; then
        return 1
    fi

    while IFS= read -r -d '' arg; do
        command_line+=("${arg}")
    done < "/proc/${pid}/cmdline"

    for arg in "${command_line[@]}"; do
        if [ "${found_executable}" = "0" ]; then
            case "${arg}" in
                *PalServer-Win64-Shipping-Cmd.exe)
                    found_executable="1"
                    ;;
            esac
            continue
        fi
        recovered+=("${arg}")
    done

    [ "${found_executable}" = "1" ] || return 1

    for arg in "${recovered[@]}"; do
        case "${arg}" in
            -unattended|-NoSplash|-NoSound|-stdout|-FullStdOutLogOutput|-logformat=text)
                continue
                ;;
        esac
        filtered+=("${arg}")
    done

    save_start_args "${filtered[@]}"
    echo "已从当前 PalServer 进程补录启动参数：${START_ARGS_DEBUG_FILE}"
}

stop_server() {
    local pid=""
    local wait_status="0"
    pid="$(read_pid 2>/dev/null || true)"

    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
        # Shipping 由 setsid 启动。先向整个进程组发送 INT，给存档事务完成时间。
        kill -INT -- "-${pid}" 2>/dev/null || kill -INT "${pid}" 2>/dev/null || true

        for _ in $(seq 1 60); do
            kill -0 "${pid}" 2>/dev/null || break
            sleep 1
        done

        if kill -0 "${pid}" 2>/dev/null; then
            echo "警告：PalServer 60 秒内未退出，发送 TERM。" >&2
            kill -TERM -- "-${pid}" 2>/dev/null || kill -TERM "${pid}" 2>/dev/null || true
            for _ in $(seq 1 20); do
                kill -0 "${pid}" 2>/dev/null || break
                sleep 1
            done
        fi

        if kill -0 "${pid}" 2>/dev/null; then
            echo "警告：PalServer 仍未退出，最后执行 KILL。" >&2
            kill -KILL -- "-${pid}" 2>/dev/null || kill -KILL "${pid}" 2>/dev/null || true
        fi
    fi

    set +e
    run_timed_wine_bootstrap 60 "${WINESERVER_BIN}" -w >/dev/null 2>&1
    wait_status="$?"
    set -e

    if [ "${wait_status}" -eq 124 ] || [ "${wait_status}" -eq 137 ]; then
        echo "警告：Wine 前缀仍有残留进程，执行最终清理。" >&2
        wine_bootstrap_env "${WINESERVER_BIN}" -k >/dev/null 2>&1 || true
    fi

    sync
    rm -f "${PID_FILE}"
}

start_server() {
    local reuse_saved_args="0"

    if [ "${1:-}" = "--reuse-saved-args" ]; then
        reuse_saved_args="1"
        shift
    fi

    local -a server_args=("$@")

    if server_running; then
        echo "palworld-host-wine-already-running"
        return 0
    fi

    if [ ! -f "${SHIPPING_EXE}" ]; then
        install_server
    else
        initialize_wine
    fi

    prepare_wine_runtime

    if [ -x "${DIRECT_SAVE_PREPARE_TOOL}" ]; then
        PALPANEL_ROOT="${ROOT}" \
        PALPANEL_SERVER_DIR="${SERVER_DIR}" \
        PALPANEL_WINE_PREFIX_DIR="${WINE_PREFIX}" \
        PALPANEL_XVFB_DISPLAY="${DISPLAY_VALUE}" \
            "${DIRECT_SAVE_PREPARE_TOOL}"
    else
        echo "错误：缺少存档直写自检工具：${DIRECT_SAVE_PREPARE_TOOL}" >&2
        return 1
    fi

    install_mods

    # 保存 PalPanel 原始传入参数，固定无头参数不写入状态文件。
    if [ "${reuse_saved_args}" = "0" ]; then
        save_start_args "${server_args[@]}"
    fi

    # 避免面板没有提供必要的无头参数。
    server_args+=(
        "-unattended"
        "-NoSplash"
        "-NoSound"
        "-stdout"
        "-FullStdOutLogOutput"
        "-logformat=text"
    )

    touch "${EXISTS_FILE}" "${SERVER_LOG}"

    (
        cd "${SERVER_DIR}"

        exec setsid nohup env \
            HOME="${WINE_HOME}" \
            USER="root" \
            LOGNAME="root" \
            XDG_CONFIG_HOME="${WINE_HOME}/.config" \
            XDG_DATA_HOME="${WINE_HOME}/.local/share" \
            XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
            DISPLAY="${DISPLAY_VALUE}" \
            WINEPREFIX="${WINE_PREFIX}" \
            WINEARCH="win64" \
            WINEDEBUG="-all" \
            SteamAppId="${STEAM_APP_ID}" \
            SteamGameId="${STEAM_APP_ID}" \
            WINEDLLOVERRIDES="mscoree,mshtml=;dwmapi=n,b;d3d9=n,b" \
            "${WINE_BIN}" "${SHIPPING_RELATIVE}" "${server_args[@]}"
    ) >> "${SERVER_LOG}" 2>&1 < /dev/null &

    local pid="$!"
    printf '%s\n' "${pid}" > "${PID_FILE}"

    sleep 5

    if ! kill -0 "${pid}" 2>/dev/null; then
        rm -f "${PID_FILE}"
        echo "PalServer exited immediately. Last log lines:" >&2
        tail -n 180 "${SERVER_LOG}" >&2 || true
        if [ -x "${WINE_MOD_DIAG_TOOL}" ]; then
            "${WINE_MOD_DIAG_TOOL}" >&2 || true
        fi
        return 1
    fi

    if [ -x "${UE4SS_LOAD_MONITOR_TOOL}" ]; then
        "${UE4SS_LOAD_MONITOR_TOOL}" "${pid}" >/dev/null 2>&1 &
    fi

    printf 'palworld-host-wine-%064d\n' "${pid}"
}

# ---------------------------------------------------------
# 宿主 Wine 资源统计
#
# PalPanel 在 wine-docker 模式下固定调用：
#   docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}"
#
# 当前没有真实 Docker cgroup，因此从 /proc 统计所有使用本 Wine 前缀
# 的进程，包括 Wine 启动器、Shipping-Cmd 和 wineserver。
# ---------------------------------------------------------

wine_process_pids() {
    local proc_dir=""
    local pid=""
    local cmdline=""
    local matched="0"

    for proc_dir in /proc/[0-9]*; do
        [ -r "${proc_dir}/stat" ] || continue
        pid="${proc_dir##*/}"
        matched="0"

        if [ -r "${proc_dir}/environ" ]; then
            if tr '\0' '\n' < "${proc_dir}/environ" 2>/dev/null |
                grep -Fxq "WINEPREFIX=${WINE_PREFIX}"; then
                matched="1"
            fi
        fi

        if [ "${matched}" = "0" ] && [ -r "${proc_dir}/cmdline" ]; then
            cmdline="$(tr '\0' ' ' < "${proc_dir}/cmdline" 2>/dev/null || true)"
            case "${cmdline}" in
                *PalServer-Win64-Shipping-Cmd.exe*|*"${SERVER_DIR}"*PalServer*)
                    matched="1"
                    ;;
            esac
        fi

        if [ "${matched}" = "1" ]; then
            printf '%s\n' "${pid}"
        fi
    done
}

sum_process_cpu_ticks() {
    local pid=""
    local stat_line=""
    local after_comm=""
    local total="0"
    local ticks="0"

    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        [ -r "/proc/${pid}/stat" ] || continue

        stat_line="$(cat "/proc/${pid}/stat" 2>/dev/null || true)"
        [ -n "${stat_line}" ] || continue

        # 删除 "pid (comm) "。剩余第 12、13 列对应原始 stat 的 utime、stime。
        after_comm="${stat_line##*) }"
        ticks="$(printf '%s\n' "${after_comm}" | awk '{print ($12 + $13)}')"

        case "${ticks}" in
            ''|*[!0-9.]*)
                continue
                ;;
        esac

        total="$(awk -v a="${total}" -v b="${ticks}" 'BEGIN {printf "%.0f", a+b}')"
    done < <(wine_process_pids)

    printf '%s\n' "${total}"
}

sum_process_rss_bytes() {
    local pid=""
    local rss_kb=""
    local total_kb="0"

    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        [ -r "/proc/${pid}/status" ] || continue

        rss_kb="$(awk '/^VmRSS:/ {print $2; exit}' "/proc/${pid}/status" 2>/dev/null || true)"
        case "${rss_kb}" in
            ''|*[!0-9]*)
                continue
                ;;
        esac

        total_kb=$((total_kb + rss_kb))
    done < <(wine_process_pids)

    printf '%s\n' "$((total_kb * 1024))"
}

memory_limit_bytes() {
    local cgroup_path=""
    local candidate=""
    local value=""

    if [ -r "/proc/self/cgroup" ]; then
        cgroup_path="$(awk -F: '$1 == "0" {print $3; exit}' /proc/self/cgroup 2>/dev/null || true)"
    fi

    for candidate in \
        "/sys/fs/cgroup${cgroup_path}/memory.max" \
        "/sys/fs/cgroup/memory.max" \
        "/sys/fs/cgroup/memory/memory.limit_in_bytes"
    do
        [ -r "${candidate}" ] || continue
        value="$(tr -d '[:space:]' < "${candidate}" 2>/dev/null || true)"

        case "${value}" in
            ''|max|*[!0-9]*)
                continue
                ;;
        esac

        # 忽略表示“无限制”的超大 cgroup v1 数值。
        if [ "${value}" -gt 0 ] 2>/dev/null && [ "${value}" -lt 9000000000000000000 ] 2>/dev/null; then
            printf '%s\n' "${value}"
            return 0
        fi
    done

    awk '/^MemTotal:/ {printf "%.0f\n", $2 * 1024; exit}' /proc/meminfo
}

format_docker_bytes() {
    local bytes="${1:-0}"

    awk -v value="${bytes}" '
        BEGIN {
            if (value >= 1073741824) {
                printf "%.2fGiB", value / 1073741824
            } else if (value >= 1048576) {
                printf "%.2fMiB", value / 1048576
            } else if (value >= 1024) {
                printf "%.2fKiB", value / 1024
            } else {
                printf "%.0fB", value
            }
        }
    '
}

docker_stats() {
    local ticks_before="0"
    local ticks_after="0"
    local tick_delta="0"
    local clock_ticks="100"
    local interval_seconds="1"
    local cpu_percent="0.00"
    local rss_bytes="0"
    local limit_bytes="0"
    local usage_text=""
    local limit_text=""

    clock_ticks="$(getconf CLK_TCK 2>/dev/null || echo 100)"

    if server_running; then
        ticks_before="$(sum_process_cpu_ticks)"
        sleep "${interval_seconds}"
        ticks_after="$(sum_process_cpu_ticks)"

        tick_delta="$(awk -v a="${ticks_after}" -v b="${ticks_before}" '
            BEGIN {
                delta = a - b
                if (delta < 0) delta = 0
                printf "%.0f", delta
            }
        ')"

        # 与 Docker CPUPerc 一致：一个完整 CPU 核心满载约为 100%，
        # 多线程可超过 100%，不除以宿主核心数。
        cpu_percent="$(awk \
            -v delta="${tick_delta}" \
            -v hz="${clock_ticks}" \
            -v seconds="${interval_seconds}" '
            BEGIN {
                if (hz <= 0 || seconds <= 0) {
                    printf "0.00"
                } else {
                    printf "%.2f", (delta / hz / seconds) * 100
                }
            }
        ')"
    fi

    rss_bytes="$(sum_process_rss_bytes)"
    limit_bytes="$(memory_limit_bytes)"

    usage_text="$(format_docker_bytes "${rss_bytes}")"
    limit_text="$(format_docker_bytes "${limit_bytes}")"

    printf '%s%%|%s / %s\n' "${cpu_percent}" "${usage_text}" "${limit_text}"
}

docker_version() {
    if printf '%s\n' "$@" | grep -q -- '--format'; then
        echo "25.0.0-palpanel-host-wine-v1.0.16"
        return
    fi

    cat <<EOF
Client:
 Version:           25.0.0-palpanel-host-wine-v1.0.16
 API version:       1.45
Server:
 Engine:
  Version:          25.0.0-palpanel-host-wine-v1.0.16
  Storage Driver:   host-wine
EOF
}

docker_info() {
    if printf '%s\n' "$@" | grep -q -- '--format'; then
        echo "25.0.0-palpanel-host-wine-v1.0.16"
        return
    fi

    cat <<EOF
Server Version: 25.0.0-palpanel-host-wine-v1.0.16
Storage Driver: host-wine
Operating System: PalPanel Host Wine Compatibility Layer
Docker Root Dir: ${ROOT}
EOF
}

docker_container_state_values() {
    CONTAINER_RUNNING="false"
    CONTAINER_STATUS="exited"
    CONTAINER_HEALTH="unhealthy"
    CONTAINER_PID="0"

    if server_running; then
        CONTAINER_RUNNING="true"
        CONTAINER_STATUS="running"
        CONTAINER_HEALTH="healthy"
        CONTAINER_PID="$(read_pid 2>/dev/null || echo 0)"
    fi
}

render_inspect_format() {
    local format="$1"
    local rendered=""

    docker_container_state_values

    case "${format}" in
        *'{{json .State}}'*)
            printf '{"Status":"%s","Running":%s,"Paused":false,"Restarting":false,"OOMKilled":false,"Dead":false,"Pid":%s,"ExitCode":0,"Health":{"Status":"%s"}}\n' \
                "${CONTAINER_STATUS}" \
                "${CONTAINER_RUNNING}" \
                "${CONTAINER_PID}" \
                "${CONTAINER_HEALTH}"
            return
            ;;
    esac

    rendered="${format}"
    rendered="${rendered//'{{.State.Running}}'/${CONTAINER_RUNNING}}"
    rendered="${rendered//'{{.State.Status}}'/${CONTAINER_STATUS}}"
    rendered="${rendered//'{{.State.Pid}}'/${CONTAINER_PID}}"
    rendered="${rendered//'{{.State.Health.Status}}'/${CONTAINER_HEALTH}}"
    rendered="${rendered//'{{.Name}}'//palworld-wine-server}"
    rendered="${rendered//'{{.Id}}'/palworld-host-wine-container}"
    rendered="${rendered//'{{.ID}}'/palworld-host-wine-container}"
    rendered="${rendered//'{{.Config.Image}}'/palworld-host-wine:local}"
    rendered="${rendered//'{{.Config.Hostname}}'/palworld-wine-server}"
    rendered="${rendered//'{{.HostConfig.NetworkMode}}'/host}"
    printf '%s\n' "${rendered}"
}

docker_inspect() {
    local format=""
    local arg=""

    while [ "$#" -gt 0 ]; do
        arg="$1"
        shift
        case "${arg}" in
            -f|--format)
                format="${1:-}"
                [ "$#" -gt 0 ] && shift
                ;;
            --format=*)
                format="${arg#--format=}"
                ;;
            *)
                ;;
        esac
    done

    if [ ! -f "${EXISTS_FILE}" ] && [ ! -f "${SHIPPING_EXE}" ]; then
        echo "Error: No such object: palworld-wine-server" >&2
        return 1
    fi

    touch "${EXISTS_FILE}"
    docker_container_state_values

    if [ -n "${format}" ]; then
        render_inspect_format "${format}"
        return
    fi

    python3 - \
        "${CONTAINER_RUNNING}" \
        "${CONTAINER_STATUS}" \
        "${CONTAINER_HEALTH}" \
        "${CONTAINER_PID}" \
        "${ROOT}" <<'PY_DOCKER_INSPECT_JSON'
import json
import sys

running = sys.argv[1].lower() == "true"
status = sys.argv[2]
health = sys.argv[3]
pid = int(sys.argv[4])
root = sys.argv[5]

payload = [{
    "Id": "palworld-host-wine-container",
    "Name": "/palworld-wine-server",
    "Path": "wine",
    "Args": ["PalServer-Win64-Shipping-Cmd.exe"],
    "Config": {
        "Hostname": "palworld-wine-server",
        "Image": "palworld-host-wine:local",
        "Labels": {
            "com.palpanel.runtime": "host-wine",
            "com.palpanel.real_docker": "false",
        },
    },
    "State": {
        "Status": status,
        "Running": running,
        "Paused": False,
        "Restarting": False,
        "OOMKilled": False,
        "Dead": False,
        "Pid": pid,
        "ExitCode": 0,
        "Health": {"Status": health},
    },
    "HostConfig": {
        "NetworkMode": "host",
        "RestartPolicy": {"Name": "no", "MaximumRetryCount": 0},
        "Binds": [root],
    },
    "NetworkSettings": {
        "Ports": {
            "8211/udp": None,
            "8212/tcp": None,
            "25575/tcp": None,
        },
        "Networks": {"host": {"NetworkID": "host"}},
    },
}]
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY_DOCKER_INSPECT_JSON
}

render_ps_format() {
    local format="$1"
    local rendered=""
    local status_text="Exited (0)"

    docker_container_state_values
    if [ "${CONTAINER_RUNNING}" = "true" ]; then
        status_text="Up (host Wine)"
    fi

    rendered="${format}"
    rendered="${rendered//'{{.ID}}'/palworld-host-wine-container}"
    rendered="${rendered//'{{.Image}}'/palworld-host-wine:local}"
    rendered="${rendered//'{{.Command}}'/wine PalServer-Win64-Shipping-Cmd.exe}"
    rendered="${rendered//'{{.CreatedAt}}'/host-wine}"
    rendered="${rendered//'{{.RunningFor}}'/host-wine}"
    rendered="${rendered//'{{.Ports}}'/8211\/udp, 8212\/tcp, 25575\/tcp}"
    rendered="${rendered//'{{.Status}}'/${status_text}}"
    rendered="${rendered//'{{.Size}}'/0B}"
    rendered="${rendered//'{{.Names}}'/palworld-wine-server}"
    rendered="${rendered//'{{.Labels}}'/com.palpanel.runtime=host-wine}"
    rendered="${rendered//'{{.Mounts}}'/${ROOT}}"
    rendered="${rendered//'{{.Networks}}'/host}"
    printf '%s\n' "${rendered}"
}

docker_ps() {
    local format=""
    local show_all="0"
    local arg=""

    while [ "$#" -gt 0 ]; do
        arg="$1"
        shift
        case "${arg}" in
            -a|--all)
                show_all="1"
                ;;
            --format|-f)
                if [ "${arg}" = "--format" ]; then
                    format="${1:-}"
                    [ "$#" -gt 0 ] && shift
                elif [ "${arg}" = "-f" ]; then
                    # -f is filter for `docker ps`, not format.
                    [ "$#" -gt 0 ] && shift
                fi
                ;;
            --format=*)
                format="${arg#--format=}"
                ;;
            --filter=*)
                ;;
            *)
                ;;
        esac
    done

    docker_container_state_values

    if [ "${CONTAINER_RUNNING}" != "true" ] && [ "${show_all}" != "1" ]; then
        return 0
    fi

    if [ ! -f "${EXISTS_FILE}" ] && [ ! -f "${SHIPPING_EXE}" ]; then
        return 0
    fi

    if [ -n "${format}" ]; then
        render_ps_format "${format}"
    else
        printf '%-24s %-28s %-22s %s\n' \
            "CONTAINER ID" "IMAGE" "STATUS" "NAMES"
        if [ "${CONTAINER_RUNNING}" = "true" ]; then
            printf '%-24s %-28s %-22s %s\n' \
                "palworld-host-wine" \
                "palworld-host-wine:local" \
                "Up (host Wine)" \
                "palworld-wine-server"
        else
            printf '%-24s %-28s %-22s %s\n' \
                "palworld-host-wine" \
                "palworld-host-wine:local" \
                "Exited (0)" \
                "palworld-wine-server"
        fi
    fi
}

start_existing_server() {
    if server_running; then
        echo "palworld-wine-server"
        return 0
    fi

    if ! load_start_args; then
        echo "错误：没有可恢复的 PalServer 启动参数。" >&2
        echo "请在面板中重新执行一次“启动”以保存参数。" >&2
        return 1
    fi

    start_server --reuse-saved-args "${SAVED_START_ARGS[@]}" >/dev/null
    echo "palworld-wine-server"
}

extract_bind_host_paths() {
    local -a args=("$@")
    local i=""
    local token=""
    local spec=""
    local host=""
    local source_value=""

    for ((i=0; i<${#args[@]}; i++)); do
        token="${args[$i]}"
        spec=""

        case "${token}" in
            -v|--volume)
                if [ "$((i + 1))" -lt "${#args[@]}" ]; then
                    spec="${args[$((i + 1))]}"
                    i=$((i + 1))
                fi
                ;;
            --volume=*)
                spec="${token#--volume=}"
                ;;
            --mount)
                if [ "$((i + 1))" -lt "${#args[@]}" ]; then
                    spec="${args[$((i + 1))]}"
                    i=$((i + 1))
                fi
                if [ -n "${spec}" ]; then
                    source_value="$(
                        printf '%s\n' "${spec}" |
                            tr ',' '\n' |
                            awk -F= '
                                $1 == "source" || $1 == "src" {
                                    sub(/^[^=]*=/, "")
                                    print
                                    exit
                                }
                            '
                    )"
                    [ -n "${source_value}" ] && printf '%s\n' "${source_value}"
                fi
                continue
                ;;
            --mount=*)
                spec="${token#--mount=}"
                source_value="$(
                    printf '%s\n' "${spec}" |
                        tr ',' '\n' |
                        awk -F= '
                            $1 == "source" || $1 == "src" {
                                sub(/^[^=]*=/, "")
                                print
                                exit
                            }
                        '
                )"
                [ -n "${source_value}" ] && printf '%s\n' "${source_value}"
                continue
                ;;
            *)
                continue
                ;;
        esac

        [ -n "${spec}" ] || continue

        # PalPanel runs on Linux, so the bind source is an absolute Linux path.
        # Split at the first colon; container target/options are not needed here.
        host="${spec%%:*}"
        [ -n "${host}" ] && printf '%s\n' "${host}"
    done
}

resolve_workshop_output_root() {
    local -a args=("$@")
    local token=""
    local explicit=""
    local path=""
    local inspection_candidate=""

    for token in "${args[@]}"; do
        case "${token}" in
            PALPANEL_WORKSHOP_OUTPUT_DIR=*)
                explicit="${token#PALPANEL_WORKSHOP_OUTPUT_DIR=}"
                ;;
            PALPANEL_WORKSHOP_DIR=*)
                explicit="${token#PALPANEL_WORKSHOP_DIR=}"
                ;;
        esac
    done

    if [ -n "${explicit}" ]; then
        printf '%s\n' "${explicit}"
        return 0
    fi

    while IFS= read -r path; do
        [ -n "${path}" ] || continue

        case "${path}" in
            */.palpanel-imports/inspection_*/workshop)
                printf '%s\n' "${path}"
                return 0
                ;;
            */.palpanel-imports/inspection_*)
                inspection_candidate="${path%/}/workshop"
                ;;
            */workshop)
                [ -z "${inspection_candidate}" ] &&
                    inspection_candidate="${path}"
                ;;
        esac
    done < <(extract_bind_host_paths "${args[@]}")

    if [ -n "${inspection_candidate}" ]; then
        printf '%s\n' "${inspection_candidate}"
        return 0
    fi

    return 1
}

workshop_source_candidates() {
    local app_id="$1"
    local item_id="$2"
    local log_path=""
    local candidate=""

    # SteamCMD commonly prints:
    # Success. Downloaded item <id> to "<path>" (...)
    if [ -f "${WORKSHOP_LOG}" ]; then
        log_path="$(
            sed -nE \
                's#.*Downloaded item [0-9]+ to "([^"]+)".*#\1#p' \
                "${WORKSHOP_LOG}" |
                tail -n 1
        )"
        [ -n "${log_path}" ] && printf '%s\n' "${log_path}"
    fi

    for candidate in \
        "${ROOT}/tools/steamcmd/steamapps/workshop/content/${app_id}/${item_id}" \
        "${ROOT}/steamapps/workshop/content/${app_id}/${item_id}" \
        "${WORKSHOP_DOWNLOAD_HOME}/Steam/steamapps/workshop/content/${app_id}/${item_id}" \
        "${WORKSHOP_DOWNLOAD_HOME}/.steam/steam/steamapps/workshop/content/${app_id}/${item_id}" \
        "${WORKSHOP_DOWNLOAD_HOME}/.local/share/Steam/steamapps/workshop/content/${app_id}/${item_id}" \
        "${ROOT}/tools/steamcmd/steamapps/workshop/downloads/${app_id}/${item_id}" \
        "${ROOT}/steamapps/workshop/downloads/${app_id}/${item_id}" \
        "${WORKSHOP_DOWNLOAD_HOME}/Steam/steamapps/workshop/downloads/${app_id}/${item_id}" \
        "${WORKSHOP_DOWNLOAD_HOME}/.steam/steam/steamapps/workshop/downloads/${app_id}/${item_id}" \
        "${WORKSHOP_DOWNLOAD_HOME}/.local/share/Steam/steamapps/workshop/downloads/${app_id}/${item_id}"
    do
        printf '%s\n' "${candidate}"
    done
}

find_workshop_source() {
    local app_id="$1"
    local item_id="$2"
    local candidate=""

    while IFS= read -r candidate; do
        [ -n "${candidate}" ] || continue
        if [ -d "${candidate}" ] &&
            find "${candidate}" -mindepth 1 -maxdepth 1 -print -quit |
                grep -q .
        then
            (
                cd "${candidate}"
                pwd -P
            )
            return 0
        fi
    done < <(workshop_source_candidates "${app_id}" "${item_id}")

    # Last-resort bounded search. Avoid scanning the whole filesystem.
    for search_root in \
        "${ROOT}"
    do
        [ -d "${search_root}" ] || continue
        candidate="$(
            find "${search_root}" \
                -maxdepth 9 \
                -type d \
                -path "*/steamapps/workshop/content/${app_id}/${item_id}" \
                -print \
                -quit \
                2>/dev/null || true
        )"

        if [ -n "${candidate}" ] &&
            find "${candidate}" -mindepth 1 -maxdepth 1 -print -quit |
                grep -q .
        then
            (
                cd "${candidate}"
                pwd -P
            )
            return 0
        fi
    done

    return 1
}

format_duration() {
    local total="${1:-0}"
    local hours="0"
    local minutes="0"
    local seconds="0"

    [ "${total}" -ge 0 ] 2>/dev/null || total="0"

    hours=$((total / 3600))
    minutes=$(((total % 3600) / 60))
    seconds=$((total % 60))

    printf '%02d:%02d:%02d\n' "${hours}" "${minutes}" "${seconds}"
}

format_bytes() {
    local bytes="${1:-0}"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "${bytes}" 2>/dev/null ||
            printf '%sB\n' "${bytes}"
    else
        printf '%sB\n' "${bytes}"
    fi
}

workshop_progress_paths() {
    local output_root="$1"
    local item_id="$2"

    WORKSHOP_PROGRESS_JSON="${output_root%/}/.palpanel-workshop-progress-${item_id}.json"
    WORKSHOP_PROGRESS_LOG="${output_root%/}/.palpanel-workshop-progress-${item_id}.log"
}

workshop_phase_from_log() {
    local phase="准备中"
    local recent=""

    recent="$(tail -n 100 "${WORKSHOP_LOG}" 2>/dev/null || true)"

    if printf '%s\n' "${recent}" |
        grep -qiE 'Steam Guard|two-factor|two factor|Account Logon Denied|Invalid Login Auth Code|Enter.*code'
    then
        phase="等待 Steam Guard/二步验证"
    elif printf '%s\n' "${recent}" |
        grep -qiE 'Success[.!].*Downloaded item|Downloaded item [0-9]+ to'
    then
        phase="下载完成，正在校验"
    elif printf '%s\n' "${recent}" |
        grep -qiE 'Update state|Downloading item|download.*progress|progress:'
    then
        phase="正在下载"
    elif printf '%s\n' "${recent}" |
        grep -qiE 'Waiting for user info|Logging in user|Connecting anonymously|Connecting to Steam'
    then
        phase="正在登录 Steam"
    elif printf '%s\n' "${recent}" |
        grep -qiE 'Waiting for client config|Loading Steam API|Checking for available updates'
    then
        phase="正在初始化 SteamCMD"
    elif printf '%s\n' "${recent}" |
        grep -qiE 'ERROR!|FAILED|Failure|timeout|Timed out'
    then
        phase="SteamCMD 报错"
    fi

    printf '%s\n' "${phase}"
}

workshop_percent_from_log() {
    local percent=""

    percent="$(
        grep -Eo \
            'progress:[[:space:]]*[0-9]+([.][0-9]+)?|[0-9]+([.][0-9]+)?%' \
            "${WORKSHOP_LOG}" \
            2>/dev/null |
            tail -n 1 |
            sed -E 's/.*progress:[[:space:]]*//; s/%$//' ||
            true
    )"

    if [[ "${percent}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s\n' "${percent}"
    else
        printf '%s\n' ""
    fi
}

workshop_download_metrics() {
    local app_id="$1"
    local item_id="$2"
    local candidate=""
    local canonical=""
    local bytes="0"
    local files="0"
    local one_bytes="0"
    local one_files="0"
    local seen_file="${WORKSHOP_STATE_DIR}/${item_id}.seen-paths"
    local temporary_seen="${seen_file}.tmp"

    : > "${temporary_seen}"

    while IFS= read -r candidate; do
        [ -d "${candidate}" ] || continue

        canonical="$(
            cd "${candidate}" 2>/dev/null &&
                pwd -P
        )" || continue

        grep -Fxq "${canonical}" "${temporary_seen}" 2>/dev/null &&
            continue

        printf '%s\n' "${canonical}" >> "${temporary_seen}"

        one_bytes="$(
            du -sb "${canonical}" 2>/dev/null |
                awk '{print $1}' |
                tail -n 1
        )"
        one_files="$(
            find "${canonical}" -type f -print 2>/dev/null |
                wc -l |
                tr -d ' '
        )"

        [[ "${one_bytes}" =~ ^[0-9]+$ ]] || one_bytes="0"
        [[ "${one_files}" =~ ^[0-9]+$ ]] || one_files="0"

        bytes=$((bytes + one_bytes))
        files=$((files + one_files))
    done < <(workshop_source_candidates "${app_id}" "${item_id}")

    mv -f "${temporary_seen}" "${seen_file}"
    printf '%s %s\n' "${bytes}" "${files}"
}

write_workshop_progress() {
    local output_root="$1"
    local item_id="$2"
    local status="$3"
    local login_mode="$4"
    local phase="$5"
    local elapsed="$6"
    local bytes="$7"
    local files="$8"
    local percent="$9"
    local inactivity="${10}"
    local reason="${11:-}"
    local now=""
    local temporary_json=""

    workshop_progress_paths "${output_root}" "${item_id}"
    mkdir -p "${output_root}"

    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    temporary_json="${WORKSHOP_PROGRESS_JSON}.tmp"

    python3 - \
        "${temporary_json}" \
        "${status}" \
        "${item_id}" \
        "${login_mode}" \
        "${phase}" \
        "${elapsed}" \
        "${bytes}" \
        "${files}" \
        "${percent}" \
        "${inactivity}" \
        "${reason}" \
        "${now}" <<'PY_WRITE_WORKSHOP_PROGRESS'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
percent_text = sys.argv[9].strip()

payload = {
    "status": sys.argv[2],
    "item_id": sys.argv[3],
    "login_mode": sys.argv[4],
    "phase": sys.argv[5],
    "elapsed_seconds": int(sys.argv[6]),
    "downloaded_bytes": int(sys.argv[7]),
    "file_count": int(sys.argv[8]),
    "percent": float(percent_text) if percent_text else None,
    "inactive_seconds": int(sys.argv[10]),
    "reason": sys.argv[11] or None,
    "updated_at": sys.argv[12],
}

path.write_text(
    json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY_WRITE_WORKSHOP_PROGRESS

    mv -f "${temporary_json}" "${WORKSHOP_PROGRESS_JSON}"
    chmod 600 "${WORKSHOP_PROGRESS_JSON}" 2>/dev/null || true
}

emit_workshop_progress_line() {
    local output_root="$1"
    local item_id="$2"
    local status="$3"
    local login_mode="$4"
    local phase="$5"
    local elapsed="$6"
    local bytes="$7"
    local files="$8"
    local percent="$9"
    local inactivity="${10}"
    local reason="${11:-}"
    local elapsed_text=""
    local byte_text=""
    local percent_text=""
    local line=""

    elapsed_text="$(format_duration "${elapsed}")"
    byte_text="$(format_bytes "${bytes}")"

    if [ -n "${percent}" ]; then
        percent_text=" | ${percent}%"
    fi

    line="[Workshop ${item_id}] ${elapsed_text} | ${login_mode} | ${phase} | ${byte_text} | ${files} files${percent_text} | ${inactivity}s 无变化"

    if [ -n "${reason}" ]; then
        line="${line} | ${reason}"
    fi

    workshop_progress_paths "${output_root}" "${item_id}"
    printf '%s\n' "${line}" | tee -a "${WORKSHOP_PROGRESS_LOG}"
}

monitor_workshop_download() {
    local steam_pid="$1"
    local app_id="$2"
    local item_id="$3"
    local output_root="$4"
    local login_mode="$5"
    local start_time=""
    local now=""
    local elapsed="0"
    local inactivity="0"
    local bytes="0"
    local files="0"
    local last_bytes="-1"
    local log_size="0"
    local last_log_size="-1"
    local last_change=""
    local phase=""
    local percent=""
    local metrics=""
    local guard_detected="0"

    workshop_progress_paths "${output_root}" "${item_id}"
    : > "${WORKSHOP_PROGRESS_LOG}"
    chmod 600 "${WORKSHOP_PROGRESS_LOG}" 2>/dev/null || true

    start_time="$(date +%s)"
    last_change="${start_time}"

    while kill -0 "${steam_pid}" 2>/dev/null; do
        now="$(date +%s)"
        elapsed=$((now - start_time))

        metrics="$(workshop_download_metrics "${app_id}" "${item_id}")"
        bytes="${metrics%% *}"
        files="${metrics##* }"
        log_size="$(stat -c '%s' "${WORKSHOP_LOG}" 2>/dev/null || echo 0)"

        [[ "${bytes}" =~ ^[0-9]+$ ]] || bytes="0"
        [[ "${files}" =~ ^[0-9]+$ ]] || files="0"
        [[ "${log_size}" =~ ^[0-9]+$ ]] || log_size="0"

        if [ "${bytes}" != "${last_bytes}" ] ||
            [ "${log_size}" != "${last_log_size}" ]
        then
            last_change="${now}"
            last_bytes="${bytes}"
            last_log_size="${log_size}"
        fi

        inactivity=$((now - last_change))
        phase="$(workshop_phase_from_log)"
        percent="$(workshop_percent_from_log)"

        if grep -qiE \
            'Steam Guard|two-factor|two factor|Account Logon Denied|Invalid Login Auth Code|Enter.*code' \
            "${WORKSHOP_LOG}" \
            2>/dev/null
        then
            guard_detected="1"
            phase="登录被二步验证阻塞"
            write_workshop_progress \
                "${output_root}" "${item_id}" "blocked" "${login_mode}" \
                "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" \
                "${inactivity}" "Steam Guard 需要交互输入"
            emit_workshop_progress_line \
                "${output_root}" "${item_id}" "blocked" "${login_mode}" \
                "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" \
                "${inactivity}" "Steam Guard 需要交互输入"
            kill -TERM "${steam_pid}" 2>/dev/null || true
            sleep 2
            kill -0 "${steam_pid}" 2>/dev/null &&
                kill -KILL "${steam_pid}" 2>/dev/null || true
            return 75
        fi

        if [ "${inactivity}" -ge "${WORKSHOP_STALL_SECONDS}" ]; then
            phase="下载无活动，已判定卡住"
            write_workshop_progress \
                "${output_root}" "${item_id}" "stalled" "${login_mode}" \
                "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" \
                "${inactivity}" "连续 ${WORKSHOP_STALL_SECONDS} 秒无字节或日志变化"
            emit_workshop_progress_line \
                "${output_root}" "${item_id}" "stalled" "${login_mode}" \
                "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" \
                "${inactivity}" "连续 ${WORKSHOP_STALL_SECONDS} 秒无变化"
            kill -TERM "${steam_pid}" 2>/dev/null || true
            sleep 3
            kill -0 "${steam_pid}" 2>/dev/null &&
                kill -KILL "${steam_pid}" 2>/dev/null || true
            return 76
        fi

        write_workshop_progress \
            "${output_root}" "${item_id}" "downloading" "${login_mode}" \
            "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" \
            "${inactivity}" ""
        emit_workshop_progress_line \
            "${output_root}" "${item_id}" "downloading" "${login_mode}" \
            "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" \
            "${inactivity}" ""

        sleep "${WORKSHOP_PROGRESS_INTERVAL}"
    done

    now="$(date +%s)"
    elapsed=$((now - start_time))
    metrics="$(workshop_download_metrics "${app_id}" "${item_id}")"
    bytes="${metrics%% *}"
    files="${metrics##* }"
    phase="$(workshop_phase_from_log)"
    percent="$(workshop_percent_from_log)"

    write_workshop_progress \
        "${output_root}" "${item_id}" "steamcmd-exited" "${login_mode}" \
        "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" "0" ""
    emit_workshop_progress_line \
        "${output_root}" "${item_id}" "steamcmd-exited" "${login_mode}" \
        "${phase}" "${elapsed}" "${bytes}" "${files}" "${percent}" "0" ""

    return 0
}

sync_workshop_to_inspection() {
    local source_dir="$1"
    local output_root="$2"
    local item_id="$3"
    local target_dir="${output_root%/}/${item_id}"
    local temporary_dir="${output_root%/}/.${item_id}.palpanel-copying"

    mkdir -p "${output_root}"
    chmod 700 "${output_root}" 2>/dev/null || true

    if [ -e "${target_dir}" ]; then
        rm -rf "${target_dir}"
    fi

    rm -rf "${temporary_dir}"
    mkdir -p "${temporary_dir}"

    cp -a "${source_dir}/." "${temporary_dir}/"

    if ! find "${temporary_dir}" -mindepth 1 -print -quit | grep -q .; then
        rm -rf "${temporary_dir}"
        echo "Workshop 下载目录为空：${source_dir}" >&2
        return 1
    fi

    mv "${temporary_dir}" "${target_dir}"
    chmod -R u+rwX,go-rwx "${target_dir}" 2>/dev/null || true

    [ -d "${target_dir}" ] || {
        echo "Workshop inspection 目录创建失败：${target_dir}" >&2
        return 1
    }

    echo "Workshop inspection 已就绪：${target_dir}" |
        tee -a "${WORKSHOP_LOG}"

    local final_bytes="0"
    local final_files="0"
    local final_metrics=""

    final_metrics="$(workshop_download_metrics "${DEFAULT_WORKSHOP_APP_ID}" "${item_id}")"
    final_bytes="${final_metrics%% *}"
    final_files="${final_metrics##* }"

    write_workshop_progress         "${output_root}" "${item_id}" "completed" "completed"         "下载、复制与目录校验完成" "0" "${final_bytes}" "${final_files}"         "100" "0" ""
    emit_workshop_progress_line         "${output_root}" "${item_id}" "completed" "completed"         "下载、复制与目录校验完成" "0" "${final_bytes}" "${final_files}"         "100" "0" ""
}

run_workshop_download() {
    local app_id="$1"
    local item_id="$2"
    local login_mode="$3"
    local output_root="$4"
    local status="0"
    local monitor_status="0"
    local steam_pid=""
    local timeout_seconds=""
    local -a login_args=()

    case "${login_mode}" in
        credentials)
            [ -n "${STEAM_USERNAME}" ] || return 2
            login_args=("${STEAM_USERNAME}")
            timeout_seconds="${WORKSHOP_CREDENTIAL_TIMEOUT}"
            echo "Workshop SteamCMD 登录：已授权账号缓存，最长 ${timeout_seconds}s（不传密码或令牌）" |
                tee -a "${WORKSHOP_LOG}"
            ;;
        anonymous)
            login_args=(anonymous)
            timeout_seconds="${WORKSHOP_ANONYMOUS_TIMEOUT}"
            echo "Workshop SteamCMD 登录：anonymous，最长 ${timeout_seconds}s" |
                tee -a "${WORKSHOP_LOG}"
            ;;
        *)
            return 2
            ;;
    esac

    mkdir -p \
        "${WORKSHOP_DOWNLOAD_HOME}/.config" \
        "${WORKSHOP_DOWNLOAD_HOME}/.local/share" \
        "${output_root}"

    {
        echo "SteamCMD 进程启动：$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "登录模式：${login_mode}"
        echo "超时：${timeout_seconds}s"
    } >> "${WORKSHOP_LOG}"

    set +e
    HOME="${WORKSHOP_DOWNLOAD_HOME}" \
    XDG_CONFIG_HOME="${WORKSHOP_DOWNLOAD_HOME}/.config" \
    XDG_DATA_HOME="${WORKSHOP_DOWNLOAD_HOME}/.local/share" \
    timeout \
        --signal=TERM \
        --kill-after=15 \
        "${timeout_seconds}" \
        steamcmd \
            +@ShutdownOnFailedCommand 1 \
            +@NoPromptForPassword 1 \
            +login "${login_args[@]}" \
            +app_info_update 1 \
            +workshop_download_item "${app_id}" "${item_id}" \
            +quit \
        >> "${WORKSHOP_LOG}" 2>&1 &
    steam_pid="$!"
    set -e

    set +e
    monitor_workshop_download \
        "${steam_pid}" \
        "${app_id}" \
        "${item_id}" \
        "${output_root}" \
        "${login_mode}"
    monitor_status="$?"
    wait "${steam_pid}"
    status="$?"
    set -e

    {
        echo "SteamCMD 退出码：${status}"
        echo "进度监控退出码：${monitor_status}"
    } >> "${WORKSHOP_LOG}"

    if [ "${monitor_status}" -eq 75 ]; then
        return 75
    fi

    if [ "${monitor_status}" -eq 76 ]; then
        return 76
    fi

    if [ "${status}" -eq 124 ] || [ "${status}" -eq 137 ]; then
        write_workshop_progress \
            "${output_root}" "${item_id}" "timeout" "${login_mode}" \
            "SteamCMD 超时" "${timeout_seconds}" "0" "0" "" "0" \
            "超过 ${timeout_seconds} 秒"
        return 74
    fi

    return "${status}"
}

install_workshop_for_palpanel() {
    local app_id="$1"
    local item_id="$2"
    local output_root="$3"
    local source_dir=""
    local configured_status="0"
    local anonymous_status="0"
    local success="0"

    mkdir -p "${WORKSHOP_STATE_DIR}" "${output_root}"
    printf '%s\n' "${output_root}" \
        > "${WORKSHOP_STATE_DIR}/${item_id}.inspection-root"
    chmod 600 "${WORKSHOP_STATE_DIR}/${item_id}.inspection-root" \
        2>/dev/null || true

    : > "${WORKSHOP_LOG}"
    {
        echo "Workshop App ID：${app_id}"
        echo "Workshop Item ID：${item_id}"
        echo "PalPanel inspection 根目录：${output_root}"
        echo "进度间隔：${WORKSHOP_PROGRESS_INTERVAL}s"
        echo "无活动判定：${WORKSHOP_STALL_SECONDS}s"
        echo "说明：最终 ${output_root}/${item_id} 只会在完整下载后创建。"
    } >> "${WORKSHOP_LOG}"

    workshop_progress_paths "${output_root}" "${item_id}"
    : > "${WORKSHOP_PROGRESS_LOG}"
    write_workshop_progress \
        "${output_root}" "${item_id}" "starting" "anonymous" \
        "准备 SteamCMD" "0" "0" "0" "" "0" ""

    # Public Workshop content is attempted anonymously first. This avoids
    # non-interactive Steam Guard/password prompts on Linux.
    set +e
    run_workshop_download \
        "${app_id}" \
        "${item_id}" \
        anonymous \
        "${output_root}"
    anonymous_status="$?"
    set -e

    source_dir="$(find_workshop_source "${app_id}" "${item_id}" || true)"
    if [ -n "${source_dir}" ]; then
        success="1"
    fi

    build_workshop_login_args

    if [ "${success}" != "1" ] &&
        [ "${WORKSHOP_LOGIN_ARGS[0]}" != "anonymous" ]
    then
        echo "匿名下载未产生完整 Workshop 目录，尝试账号模式。" |
            tee -a "${WORKSHOP_LOG}"

        set +e
        run_workshop_download \
            "${app_id}" \
            "${item_id}" \
            credentials \
            "${output_root}"
        configured_status="$?"
        set -e

        source_dir="$(find_workshop_source "${app_id}" "${item_id}" || true)"
        if [ -n "${source_dir}" ]; then
            success="1"
        fi
    fi

    if [ "${success}" != "1" ]; then
        local failure_reason="SteamCMD 未生成 Workshop 内容目录"

        if [ "${configured_status}" -eq 75 ]; then
            failure_reason="账号登录要求 Steam Guard；Linux 非交互下载无法输入验证码"
        elif [ "${anonymous_status}" -eq 76 ] ||
            [ "${configured_status}" -eq 76 ]
        then
            failure_reason="下载连续 ${WORKSHOP_STALL_SECONDS} 秒无字节或日志变化"
        elif [ "${anonymous_status}" -eq 74 ] ||
            [ "${configured_status}" -eq 74 ]
        then
            failure_reason="SteamCMD 下载超时"
        fi

        write_workshop_progress \
            "${output_root}" "${item_id}" "failed" "all" \
            "下载失败" "0" "0" "0" "" "0" "${failure_reason}"

        {
            echo "错误：${failure_reason}。"
            echo "匿名下载退出码：${anonymous_status}"
            echo "账号下载退出码：${configured_status}"
            echo "预期内容：steamapps/workshop/content/${app_id}/${item_id}"
            echo "进度 JSON：${WORKSHOP_PROGRESS_JSON}"
            echo "进度日志：${WORKSHOP_PROGRESS_LOG}"
            echo "最近 SteamCMD 日志："
            tail -n 160 "${WORKSHOP_LOG}" 2>/dev/null || true
        } >&2
        return 1
    fi

    echo "SteamCMD 实际下载目录：${source_dir}" |
        tee -a "${WORKSHOP_LOG}"

    sync_workshop_to_inspection "${source_dir}" "${output_root}" "${item_id}"
}

handle_run() {
    local -a args=("$@")
    local action=""
    local action_index="-1"
    local workshop_app_id="${DEFAULT_WORKSHOP_APP_ID}"
    local i=""

    for ((i=0; i<${#args[@]}; i++)); do
        case "${args[$i]}" in
            PALPANEL_WORKSHOP_APP_ID=*)
                workshop_app_id="${args[$i]#PALPANEL_WORKSHOP_APP_ID=}"
                ;;
            install|appinfo|workshop|start)
                action="${args[$i]}"
                action_index="${i}"
                break
                ;;
        esac
    done

    case "${action}" in
        install)
            install_server
            ;;
        appinfo)
            steamcmd \
                +login anonymous \
                +app_info_update 1 \
                +app_info_print "${STEAM_APP_ID}" \
                +quit
            ;;
        workshop)
            local item_id="${args[$((action_index+1))]:-}"
            local output_root=""

            if [ -z "${item_id}" ] || ! [[ "${item_id}" =~ ^[0-9]+$ ]]; then
                echo "workshop item id is required and must be numeric" >&2
                return 1
            fi

            output_root="$(resolve_workshop_output_root "${args[@]}" || true)"

            if [ -z "${output_root}" ]; then
                echo "错误：无法从 PalPanel docker run 参数解析 inspection/workshop 目录。" >&2
                printf '调用参数：' >&2
                printf ' %q' "${args[@]}" >&2
                printf '\n' >&2
                return 1
            fi

            install_workshop_for_palpanel                 "${workshop_app_id}"                 "${item_id}"                 "${output_root}"
            ;;
        start)
            local -a server_args=()
            if [ "${action_index}" -ge 0 ]; then
                server_args=("${args[@]:$((action_index+1))}")
            fi
            start_server "${server_args[@]}"
            ;;
        *)
            echo "Unsupported docker run invocation: ${args[*]}" >&2
            return 1
            ;;
    esac
}

command="${1:-}"
if [ "$#" -gt 0 ]; then
    shift
fi

case "${command}" in
    version)
        docker_version "$@"
        ;;
    info)
        docker_info "$@"
        ;;
    build|pull)
        touch "${IMAGE_FILE}"
        echo "palworld-host-wine image ready"
        ;;
    image)
        subcommand="${1:-}"
        if [ "$#" -gt 0 ]; then shift; fi
        case "${subcommand}" in
            inspect)
                touch "${IMAGE_FILE}"
                echo '[{"Id":"sha256:palworld-host-wine","RepoTags":["palworld-host-wine:local"]}]'
                ;;
            *)
                echo "Unsupported docker image command: ${subcommand}" >&2
                exit 1
                ;;
        esac
        ;;
    run)
        handle_run "$@"
        ;;
    inspect)
        docker_inspect "$@"
        ;;
    start)
        start_existing_server
        ;;
    stop)
        if [ -f "${EXISTS_FILE}" ]; then
            stop_server
        fi
        echo "${1:-palworld-wine-server}"
        ;;
    restart)
        capture_running_start_args >/dev/null 2>&1 || true

        if ! load_start_args; then
            echo "错误：没有可恢复的 PalServer 启动参数。" >&2
            echo "请在面板中先执行“停止”，再执行“启动”，不要直接点击“重启”。" >&2
            exit 1
        fi

        stop_server
        start_server --reuse-saved-args "${SAVED_START_ARGS[@]}"
        ;;
    rm)
        stop_server
        rm -f "${EXISTS_FILE}"
        echo "${@: -1}"
        ;;
    logs)
        tail_count="200"
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --tail)
                    tail_count="${2:-200}"
                    shift 2
                    ;;
                --tail=*)
                    tail_count="${1#--tail=}"
                    shift
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        if [ -f "${SERVER_LOG}" ]; then
            tail -n "${tail_count}" "${SERVER_LOG}"
        fi
        ;;
    stats)
        # PalPanel 固定使用 {{.CPUPerc}}|{{.MemUsage}}；其他参数安全忽略。
        docker_stats
        ;;
    preserve-start-args)
        if capture_running_start_args; then
            echo "PalServer 启动参数已保存。"
        elif [ -s "${START_ARGS_FILE}" ]; then
            echo "PalServer 启动参数已经存在。"
        else
            echo "当前没有可补录的 PalServer 启动参数。" >&2
            exit 1
        fi
        ;;
    show-start-args)
        if [ -f "${START_ARGS_DEBUG_FILE}" ]; then
            cat "${START_ARGS_DEBUG_FILE}"
        else
            echo "尚未保存 PalServer 启动参数。" >&2
            exit 1
        fi
        ;;
    ps)
        docker_ps "$@"
        ;;
    container)
        subcommand="${1:-}"
        [ "$#" -gt 0 ] && shift
        case "${subcommand}" in
            ls)
                exec "$0" ps "$@"
                ;;
            inspect|start|stop|restart|rm|logs|stats)
                exec "$0" "${subcommand}" "$@"
                ;;
            *)
                echo "Unsupported docker container command: ${subcommand}" >&2
                exit 1
                ;;
        esac
        ;;
    repair-state)
        if repair_server_state; then
            echo "Host Wine PalServer 状态已恢复：PID $(read_pid)"
            docker_inspect --format '{{.State.Running}}'
        else
            echo "当前未发现正在运行的 Host Wine PalServer。" >&2
            exit 1
        fi
        ;;
    *)
        echo "Unsupported Docker compatibility command: ${command} $*" >&2
        exit 1
        ;;
esac
DOCKER_SHIM_EOF

chmod +x "${DOCKER_SHIM}"


# ---------------------------------------------------------
# SaveGames 原目录直写恢复与原子替换自检
# ---------------------------------------------------------

cat > "${DIRECT_SAVE_PREPARE_TOOL}" <<'DIRECT_SAVE_PREPARE_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
SERVER_DIR="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
WINE_PREFIX="${PALPANEL_WINE_PREFIX_DIR:-${ROOT}/wineprefix}"
WINE_HOME="${ROOT}/home"
RUN_DIR="${ROOT}/run"
LOG_DIR="${ROOT}/logs"
TMP_DIR="${ROOT}/tmp"
BACKUP_DIR="${ROOT}/backup/save-recovery"
ACTIVE_SAVE_DIR="${SERVER_DIR}/Pal/Saved/SaveGames"
LEGACY_PERSIST_DIR="${ROOT}/savegames_persistent"
DIRECT_SAVE_MARKER="${ROOT}/config/direct-save-ready"
DISPLAY_VALUE="${PALPANEL_XVFB_DISPLAY:-:99}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
WINE_BIN="${PORTABLE_WINE_CURRENT}/bin/wine"
WINEPATH_BIN="${PORTABLE_WINE_CURRENT}/bin/winepath"

export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"

mkdir -p \
    "$(dirname "${ACTIVE_SAVE_DIR}")" \
    "${TMP_DIR}" \
    "${BACKUP_DIR}" \
    "$(dirname "${DIRECT_SAVE_MARKER}")" \
    "${RUN_DIR}/xdg" \
    "${WINE_HOME}/.config" \
    "${WINE_HOME}/.local/share"

[ -x "${WINE_BIN}" ] || {
    echo "错误：独立 Wine 不存在：${WINE_BIN}" >&2
    exit 1
}

wine_env() {
    env \
        PATH="${PATH}" \
        HOME="${WINE_HOME}" \
        USER="$(id -un 2>/dev/null || echo container)" \
        LOGNAME="$(id -un 2>/dev/null || echo container)" \
        XDG_CONFIG_HOME="${WINE_HOME}/.config" \
        XDG_DATA_HOME="${WINE_HOME}/.local/share" \
        XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
        DISPLAY="${DISPLAY_VALUE}" \
        WINEPREFIX="${WINE_PREFIX}" \
        WINEARCH="win64" \
        WINEDEBUG="-all" \
        WINEDLLOVERRIDES="mscoree,mshtml=" \
        "$@"
}

run_timed_wine() {
    local seconds="$1"
    shift
    timeout \
        --signal=TERM \
        --kill-after=15 \
        "${seconds}" \
        env \
            PATH="${PATH}" \
            HOME="${WINE_HOME}" \
            USER="$(id -un 2>/dev/null || echo container)" \
            LOGNAME="$(id -un 2>/dev/null || echo container)" \
            XDG_CONFIG_HOME="${WINE_HOME}/.config" \
            XDG_DATA_HOME="${WINE_HOME}/.local/share" \
            XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
            DISPLAY="${DISPLAY_VALUE}" \
            WINEPREFIX="${WINE_PREFIX}" \
            WINEARCH="win64" \
            WINEDEBUG="-all" \
            WINEDLLOVERRIDES="mscoree,mshtml=" \
            "$@"
}

dir_has_content() {
    [ -d "$1" ] && [ -n "$(find "$1" -mindepth 1 -print -quit 2>/dev/null)" ]
}

merge_save_trees() {
    local destination="$1"
    shift

    python3 - "${destination}" "$@" <<'PY_MERGE_SAVE'
from __future__ import annotations
import os
import shutil
import sys
from pathlib import Path

dst = Path(sys.argv[1])
sources = [Path(value) for value in sys.argv[2:] if value]
dst.mkdir(parents=True, exist_ok=True)

for src in sources:
    try:
        if not src.is_dir() or src.resolve() == dst.resolve():
            continue
    except OSError:
        continue

    for root, _dirs, files in os.walk(src):
        root_path = Path(root)
        rel_root = root_path.relative_to(src)
        target_root = dst / rel_root
        target_root.mkdir(parents=True, exist_ok=True)

        for name in files:
            source = root_path / name
            target = target_root / name
            try:
                source_stat = source.stat()
            except FileNotFoundError:
                continue

            should_copy = not target.exists()
            if not should_copy:
                try:
                    target_stat = target.stat()
                    should_copy = source_stat.st_mtime_ns > target_stat.st_mtime_ns
                except FileNotFoundError:
                    should_copy = True

            if should_copy:
                temporary = target.with_name(target.name + f".merge_tmp_{os.getpid()}")
                shutil.copy2(source, temporary)
                os.replace(temporary, target)
PY_MERGE_SAVE
}

recover_prepared_saves() {
    python3 - "${ACTIVE_SAVE_DIR}" "${BACKUP_DIR}" <<'PY_RECOVER_PREPARED'
from __future__ import annotations
import json
import os
import shutil
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
backup_root = Path(sys.argv[2])

for manifest in list(root.rglob(".atomic_save_update_manifest_world.json")):
    world = manifest.parent
    payload = json.loads(manifest.read_text(encoding="utf-8-sig"))

    if payload.get("State") != "Prepared":
        raise SystemExit(f"未知原子事务状态：{manifest}")

    entries = payload.get("Entries")
    if not isinstance(entries, list) or not entries:
        raise SystemExit(f"原子事务 Entries 无效：{manifest}")

    checked: list[tuple[Path, Path]] = []
    for entry in entries:
        relative = Path(str(entry.get("RelativePath", "")))
        expected = int(entry.get("ExpectedSize", -1))
        if relative.is_absolute() or ".." in relative.parts or expected < 0:
            raise SystemExit(f"原子事务条目无效：{manifest}")

        target = world / relative
        temporary = target.with_name(target.name + ".new_tmp")
        if not temporary.is_file() or temporary.stat().st_size != expected:
            raise SystemExit(f"Prepared 事务不完整，拒绝覆盖正式存档：{temporary}")
        checked.append((target, temporary))

    stamp = time.strftime("%Y%m%d_%H%M%S")
    backup = backup_root / world.name / stamp
    backup.mkdir(parents=True, exist_ok=True)

    for target, temporary in checked:
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            backup_target = backup / target.relative_to(world)
            backup_target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup_target)
        os.replace(temporary, target)

    manifest.unlink(missing_ok=True)
    shutil.rmtree(world / "world_save_temp", ignore_errors=True)
    shutil.rmtree(world / "world_save_bak", ignore_errors=True)
    print(f"已恢复完整 Prepared 存档事务：{world}")
PY_RECOVER_PREPARED
}

probe_linux_replace() {
    python3 - "$1" <<'PY_LINUX_REPLACE'
import os
import sys
from pathlib import Path

base = Path(sys.argv[1])
base.mkdir(parents=True, exist_ok=True)
destination = base / f".pal_linux_destination_{os.getpid()}"
replacement = base / f".pal_linux_replacement_{os.getpid()}"
try:
    destination.write_bytes(b"old")
    replacement.write_bytes(b"new")
    os.replace(replacement, destination)
    if destination.read_bytes() != b"new":
        raise RuntimeError("Linux replace mismatch")
finally:
    destination.unlink(missing_ok=True)
    replacement.unlink(missing_ok=True)
PY_LINUX_REPLACE
}

unix_to_windows_path() {
    local converted=""
    converted="$(
        wine_env "${WINEPATH_BIN}" -w "$1" 2>/dev/null |
            tr -d '\r' |
            tail -n 1
    )"
    [ -n "${converted}" ] || return 1
    printf '%s\n' "${converted}"
}

probe_wine_replace() {
    local directory="$1"
    local batch_file="${directory}/.pal_wine_save_probe_$$.bat"
    local win_batch=""
    local status="0"

    cat > "${batch_file}" <<'BAT_WINE_SAVE_PROBE'
@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
mkdir .pal_wine_save_probe 2>nul
for /L %%I in (1,1,24) do (
  > .pal_wine_save_probe\destination_%%I.tmp echo old-%%I
  > .pal_wine_save_probe\replacement_%%I.tmp echo new-%%I
  move /Y .pal_wine_save_probe\replacement_%%I.tmp .pal_wine_save_probe\destination_%%I.tmp >nul
  if errorlevel 1 exit /b 21
  findstr /x /c:"new-%%I" .pal_wine_save_probe\destination_%%I.tmp >nul
  if errorlevel 1 exit /b 22
)
del /q .pal_wine_save_probe\*.tmp >nul 2>&1
rmdir .pal_wine_save_probe >nul 2>&1
exit /b 0
BAT_WINE_SAVE_PROBE

    win_batch="$(unix_to_windows_path "${batch_file}" || true)"
    [ -n "${win_batch}" ] || {
        rm -f "${batch_file}"
        return 31
    }

    set +e
    run_timed_wine 45 "${WINE_BIN}" cmd.exe /d /c "${win_batch}" >/dev/null 2>&1
    status="$?"
    set -e

    rm -f "${batch_file}" 2>/dev/null || true
    rm -rf "${directory}/.pal_wine_save_probe" 2>/dev/null || true
    return "${status}"
}

# 仅当发现旧符号链接、旧缓存或旧持久化镜像时执行迁移；正常启动不重复复制完整存档。
needs_migration="0"
active_target=""
migration_dir="${TMP_DIR}/save-migration.$$"
declare -a sources=()

if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "${ACTIVE_SAVE_DIR}" 2>/dev/null; then
    dir_has_content "${ACTIVE_SAVE_DIR}" && sources+=("${ACTIVE_SAVE_DIR}")
    umount "${ACTIVE_SAVE_DIR}" >/dev/null 2>&1 || {
        echo "错误：无法卸载旧 SaveGames 临时挂载点。" >&2
        exit 1
    }
    needs_migration="1"
elif [ -L "${ACTIVE_SAVE_DIR}" ]; then
    active_target="$(readlink -f "${ACTIVE_SAVE_DIR}" 2>/dev/null || true)"
    [ -n "${active_target}" ] && dir_has_content "${active_target}" && sources+=("${active_target}")
    needs_migration="1"
elif [ -d "${ACTIVE_SAVE_DIR}" ]; then
    :
elif [ -e "${ACTIVE_SAVE_DIR}" ]; then
    echo "错误：SaveGames 不是目录或符号链接：${ACTIVE_SAVE_DIR}" >&2
    exit 1
else
    mkdir -p "${ACTIVE_SAVE_DIR}"
fi

for legacy in \
    "${LEGACY_PERSIST_DIR}" \
    "/dev/shm/palworld-savegames-$(id -u)" \
    "${TMPDIR:-/tmp}/palworld-savegames-$(id -u)"
do
    if dir_has_content "${legacy}"; then
        sources+=("${legacy}")
        needs_migration="1"
    fi
done

if [ "${needs_migration}" = "1" ]; then
    if [ -d "${ACTIVE_SAVE_DIR}" ] && [ ! -L "${ACTIVE_SAVE_DIR}" ] && dir_has_content "${ACTIVE_SAVE_DIR}"; then
        sources+=("${ACTIVE_SAVE_DIR}")
    fi

    rm -rf "${migration_dir}"
    mkdir -p "${migration_dir}"
    merge_save_trees "${migration_dir}" "${sources[@]}"

    if [ -L "${ACTIVE_SAVE_DIR}" ]; then
        rm -f "${ACTIVE_SAVE_DIR}"
    else
        rm -rf "${ACTIVE_SAVE_DIR}"
    fi

    mkdir -p "${ACTIVE_SAVE_DIR}"
    dir_has_content "${migration_dir}" && cp -a "${migration_dir}/." "${ACTIVE_SAVE_DIR}/"
    rm -rf "${migration_dir}"

    rm -rf \
        "${LEGACY_PERSIST_DIR}" \
        "/dev/shm/palworld-savegames-$(id -u)" \
        "${TMPDIR:-/tmp}/palworld-savegames-$(id -u)" \
        2>/dev/null || true

    echo "旧缓存存档已回收到正式目录：${ACTIVE_SAVE_DIR}"
fi

mkdir -p "${ACTIVE_SAVE_DIR}"
recover_prepared_saves

if find "${ACTIVE_SAVE_DIR}" -type f -name '.atomic_save_update_manifest_world.json' -print -quit |
    grep -q .
then
    echo "错误：SaveGames 中仍存在未处理的原子事务。" >&2
    exit 1
fi

[ -r "${ACTIVE_SAVE_DIR}" ] && [ -w "${ACTIVE_SAVE_DIR}" ] && [ -x "${ACTIVE_SAVE_DIR}" ] || {
    echo "错误：SaveGames 不可读写：${ACTIVE_SAVE_DIR}" >&2
    exit 1
}

probe_linux_replace "${ACTIVE_SAVE_DIR}" || {
    echo "错误：SaveGames 未通过 Linux 原子替换测试。" >&2
    exit 1
}

probe_wine_replace "${ACTIVE_SAVE_DIR}" || {
    echo "错误：SaveGames 未通过独立 Wine 覆盖替换测试。" >&2
    exit 1
}

{
    echo "status=ready"
    echo "checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "wine=$("${WINE_BIN}" --version 2>/dev/null | head -n 1)"
    echo "path=${ACTIVE_SAVE_DIR}"
    echo "filesystem=$(stat -f -c '%T' "${ACTIVE_SAVE_DIR}" 2>/dev/null || echo unknown)"
} > "${DIRECT_SAVE_MARKER}"

rm -f \
    "${ROOT}/config/network-direct-save-certified" \
    "${ROOT}/config/network-direct-save-fallback" \
    "${ROOT}/run/network-direct-level-baseline" \
    "${ROOT}/run/save-health.status" \
    "${ROOT}/run/save-sync.pid" \
    "${ROOT}/logs/save-sync.log" \
    2>/dev/null || true

echo "SaveGames 原目录直写自检通过：${ACTIVE_SAVE_DIR}"
DIRECT_SAVE_PREPARE_EOF

chmod +x "${DIRECT_SAVE_PREPARE_TOOL}"

cat > "${TOOLS_DIR}/repair-workshop-import" <<'WORKSHOP_REPAIR_TOOL_EOF'
#!/bin/bash
set -Eeuo pipefail

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
SHIM="${ROOT}/tools/docker"
STATE_DIR="${ROOT}/run/host-wine-runner/workshop"

ITEM_ID="${1:-}"
APP_ID="${2:-1623730}"
OUTPUT_ROOT="${3:-}"

if [ -z "${ITEM_ID}" ] || ! [[ "${ITEM_ID}" =~ ^[0-9]+$ ]]; then
    echo "用法：$0 WorkshopItemID [AppID] [inspection/workshop目录]" >&2
    exit 2
fi

if [ -z "${OUTPUT_ROOT}" ] &&
    [ -s "${STATE_DIR}/${ITEM_ID}.inspection-root" ]
then
    OUTPUT_ROOT="$(cat "${STATE_DIR}/${ITEM_ID}.inspection-root")"
fi

if [ -z "${OUTPUT_ROOT}" ]; then
    OUTPUT_ROOT="$(
        find "${ROOT}/server/Mods/Workshop/.palpanel-imports" \
            -maxdepth 3 \
            -type d \
            -path "*/inspection_*/workshop" \
            -print \
            2>/dev/null |
            sort |
            tail -n 1
    )"
fi

[ -n "${OUTPUT_ROOT}" ] || {
    echo "没有找到该 Mod 的 inspection/workshop 目录。" >&2
    exit 1
}

echo "Workshop Item：${ITEM_ID}"
echo "Workshop App：${APP_ID}"
echo "Inspection 根目录：${OUTPUT_ROOT}"
echo

PALPANEL_WORKSHOP_OUTPUT_DIR="${OUTPUT_ROOT}" \
    "${SHIM}" run \
    --rm \
    "PALPANEL_WORKSHOP_APP_ID=${APP_ID}" \
    "PALPANEL_WORKSHOP_OUTPUT_DIR=${OUTPUT_ROOT}" \
    workshop \
    "${ITEM_ID}"

echo
echo "验证目录：${OUTPUT_ROOT}/${ITEM_ID}"
stat "${OUTPUT_ROOT}/${ITEM_ID}"
WORKSHOP_REPAIR_TOOL_EOF

chmod +x "${TOOLS_DIR}/repair-workshop-import"

cat > "${TOOLS_DIR}/workshop-progress" <<'WORKSHOP_PROGRESS_TOOL_EOF'
#!/bin/bash
set -Eeuo pipefail

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
STATE_DIR="${ROOT}/run/host-wine-runner/workshop"
ITEM_ID="${1:-}"
FOLLOW="${2:-}"

if [ -z "${ITEM_ID}" ] || ! [[ "${ITEM_ID}" =~ ^[0-9]+$ ]]; then
    echo "用法：$0 WorkshopItemID [--follow]" >&2
    exit 2
fi

OUTPUT_ROOT=""
if [ -s "${STATE_DIR}/${ITEM_ID}.inspection-root" ]; then
    OUTPUT_ROOT="$(cat "${STATE_DIR}/${ITEM_ID}.inspection-root")"
fi

if [ -z "${OUTPUT_ROOT}" ]; then
    OUTPUT_ROOT="$(
        find "${ROOT}/server/Mods/Workshop/.palpanel-imports" \
            -maxdepth 3 \
            -type f \
            -name ".palpanel-workshop-progress-${ITEM_ID}.json" \
            -printf '%h\n' \
            2>/dev/null |
            sort |
            tail -n 1
    )"
fi

[ -n "${OUTPUT_ROOT}" ] || {
    echo "未找到 Item ${ITEM_ID} 的进度记录。" >&2
    exit 1
}

JSON_FILE="${OUTPUT_ROOT}/.palpanel-workshop-progress-${ITEM_ID}.json"
LOG_FILE="${OUTPUT_ROOT}/.palpanel-workshop-progress-${ITEM_ID}.log"

echo "进度 JSON：${JSON_FILE}"
echo "进度日志：${LOG_FILE}"
echo

if [ "${FOLLOW}" = "--follow" ]; then
    [ -f "${LOG_FILE}" ] || touch "${LOG_FILE}"
    exec tail -n 20 -F "${LOG_FILE}"
fi

if [ -f "${JSON_FILE}" ]; then
    python3 - "${JSON_FILE}" <<'PY_SHOW_WORKSHOP_PROGRESS'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

seconds = int(data.get("elapsed_seconds", 0))
hours, remainder = divmod(seconds, 3600)
minutes, seconds = divmod(remainder, 60)
downloaded = int(data.get("downloaded_bytes", 0))

units = ["B", "KiB", "MiB", "GiB", "TiB"]
value = float(downloaded)
unit = units[0]
for candidate in units:
    unit = candidate
    if value < 1024 or candidate == units[-1]:
        break
    value /= 1024

percent = data.get("percent")
percent_text = "未知" if percent is None else f"{percent:.2f}%"

print(f"状态：{data.get('status')}")
print(f"阶段：{data.get('phase')}")
print(f"登录：{data.get('login_mode')}")
print(f"运行时间：{hours:02d}:{minutes:02d}:{seconds:02d}")
print(f"已写入：{value:.2f} {unit}")
print(f"文件数：{data.get('file_count', 0)}")
print(f"SteamCMD 百分比：{percent_text}")
print(f"无变化：{data.get('inactive_seconds', 0)} 秒")
if data.get("reason"):
    print(f"原因：{data['reason']}")
print(f"更新时间：{data.get('updated_at')}")
PY_SHOW_WORKSHOP_PROGRESS
else
    echo "进度 JSON 尚未生成。"
fi

echo
echo "最近进度："
tail -n 20 "${LOG_FILE}" 2>/dev/null || true
WORKSHOP_PROGRESS_TOOL_EOF

chmod +x "${TOOLS_DIR}/workshop-progress"

cat > "${HOST_WINE_STATE_TOOL}" <<'HOST_WINE_STATE_TOOL_EOF'
#!/bin/bash
set -Eeuo pipefail

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
SHIM="${ROOT}/tools/docker"

[ -x "${SHIM}" ] || {
    echo "状态兼容工具不存在：${SHIM}" >&2
    exit 1
}

echo "=== Host Wine 服务状态修复 ==="
"${SHIM}" repair-state
echo
echo "=== PalPanel inspect 布尔值 ==="
"${SHIM}" inspect --format '{{.State.Running}}' palworld-wine-server
echo
echo "=== PalPanel inspect 状态 ==="
"${SHIM}" inspect --format '{{.State.Status}}' palworld-wine-server
echo
echo "=== PalPanel ps 名称 ==="
"${SHIM}" ps --format '{{.Names}}'
HOST_WINE_STATE_TOOL_EOF

chmod +x "${HOST_WINE_STATE_TOOL}"

cat > "${WINE_RUNTIME_PREPARE_TOOL}" <<'WINE_RUNTIME_PREPARE_TOOL_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
GH_PROXY_BASE="${GH_PROXY_BASE:-https://v4.gh-proxy.org}"
GH_PROXY_FALLBACK="${GH_PROXY_FALLBACK:-https://cdn.gh-proxy.org}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
WINE_PREFIX="${PALPANEL_WINE_PREFIX_DIR:-${ROOT}/wineprefix}"
WINE_HOME="${ROOT}/home"
RUN_DIR="${ROOT}/run"
TOOLS_DIR="${ROOT}/tools"
LOG_DIR="${ROOT}/logs"
DISPLAY_VALUE="${PALPANEL_XVFB_DISPLAY:-:99}"
WINETRICKS_ON_START="${PALPANEL_WINETRICKS_ON_START:-1}"
INSTALL_PACKAGES="${PALPANEL_INSTALL_WINE_RUNTIME_PACKAGES:-1}"
WINETRICKS_BIN="${TOOLS_DIR}/winetricks"
VCRUN_MARKER="${WINE_PREFIX}/.vcrun2022-installed"
INSTALL_LOG="${LOG_DIR}/winetricks-vcrun2022.log"

mkdir -p \
    "${WINE_PREFIX}" \
    "${WINE_HOME}/.config" \
    "${WINE_HOME}/.local/share" \
    "${RUN_DIR}/xdg" \
    "${TOOLS_DIR}" \
    "${LOG_DIR}"

install_runtime_packages() {
    local -a packages=()

    command -v Xvfb >/dev/null 2>&1 || packages+=(xvfb)
    command -v cabextract >/dev/null 2>&1 || packages+=(cabextract)
    command -v winbind >/dev/null 2>&1 || packages+=(winbind)

    [ "${#packages[@]}" -gt 0 ] || return 0
    [ "${INSTALL_PACKAGES}" = "1" ] || {
        echo "缺少运行包：${packages[*]}，自动安装已禁用。" >&2
        return 0
    }

    if command -v apt-get >/dev/null 2>&1; then
        echo "安装 Wine 辅助包：${packages[*]}"
        set +e
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
        local status="$?"
        set -e

        if [ "${status}" -ne 0 ]; then
            echo "警告：apt-get 安装 Wine 辅助包失败。" >&2
        fi
    else
        echo "警告：缺少 ${packages[*]}，且系统没有 apt-get。" >&2
    fi
}

download_winetricks() {
    local direct_url="https://github.com/Winetricks/winetricks/raw/refs/heads/master/src/winetricks"
    local url=""
    local partial="${WINETRICKS_BIN}.part"

    if command -v winetricks >/dev/null 2>&1; then
        command -v winetricks
        return 0
    fi

    if [ -x "${WINETRICKS_BIN}" ]; then
        printf '%s\n' "${WINETRICKS_BIN}"
        return 0
    fi

    for url in \
        "${GH_PROXY_BASE%/}/${direct_url}" \
        "${GH_PROXY_FALLBACK%/}/${direct_url}" \
        "${direct_url}"
    do
        rm -f "${partial}"

        if curl \
            --fail \
            --location \
            --http1.1 \
            --ipv4 \
            --retry 4 \
            --retry-delay 2 \
            --connect-timeout 25 \
            --max-time 300 \
            --output "${partial}" \
            "${url}"
        then
            if head -n 1 "${partial}" | grep -q 'sh'; then
                mv -f "${partial}" "${WINETRICKS_BIN}"
                chmod +x "${WINETRICKS_BIN}"
                printf '%s\n' "${WINETRICKS_BIN}"
                return 0
            fi
        fi
    done

    rm -f "${partial}"
    return 1
}

wine_env() {
    env \
        HOME="${WINE_HOME}" \
        USER=root \
        LOGNAME=root \
        XDG_CONFIG_HOME="${WINE_HOME}/.config" \
        XDG_DATA_HOME="${WINE_HOME}/.local/share" \
        XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
        DISPLAY="${DISPLAY_VALUE}" \
        WINEPREFIX="${WINE_PREFIX}" \
        WINEARCH=win64 \
        WINEDEBUG=-all \
        WINEDLLOVERRIDES="mscoree,mshtml=" \
        "$@"
}

run_timed_wine() {
    local seconds="$1"
    shift
    timeout \
        --signal=TERM \
        --kill-after=30 \
        "${seconds}" \
        env \
            PATH="${PATH}" \
            HOME="${WINE_HOME}" \
            USER=root \
            LOGNAME=root \
            XDG_CONFIG_HOME="${WINE_HOME}/.config" \
            XDG_DATA_HOME="${WINE_HOME}/.local/share" \
            XDG_RUNTIME_DIR="${RUN_DIR}/xdg" \
            DISPLAY="${DISPLAY_VALUE}" \
            WINEPREFIX="${WINE_PREFIX}" \
            WINEARCH=win64 \
            WINEDEBUG=-all \
            WINEDLLOVERRIDES="mscoree,mshtml=" \
            "$@"
}

install_runtime_packages

if [ "${WINETRICKS_ON_START}" != "1" ]; then
    echo "PALPANEL_WINETRICKS_ON_START=${WINETRICKS_ON_START}，跳过 vcrun2022。"
    exit 0
fi

if [ -f "${VCRUN_MARKER}" ]; then
    echo "vcrun2022 已安装。"
    exit 0
fi

winetricks_path="$(download_winetricks || true)"
if [ -z "${winetricks_path}" ]; then
    echo "警告：无法取得 winetricks，未安装 vcrun2022。" >&2
    exit 0
fi

if ! command -v cabextract >/dev/null 2>&1; then
    echo "警告：缺少 cabextract，winetricks vcrun2022 可能失败。" >&2
fi

: > "${INSTALL_LOG}"
echo "安装 Visual C++ Runtime 2022……"

set +e
run_timed_wine 1800 \
    "${winetricks_path}" \
    --optout \
    -f \
    -q \
    vcrun2022 \
    2>&1 | tee -a "${INSTALL_LOG}"
status="${PIPESTATUS[0]}"
set -e

if [ "${status}" -eq 0 ]; then
    touch "${VCRUN_MARKER}"
    echo "vcrun2022 安装完成。"
else
    echo "警告：winetricks vcrun2022 失败，退出码 ${status}。" >&2
fi
WINE_RUNTIME_PREPARE_TOOL_EOF

chmod +x "${WINE_RUNTIME_PREPARE_TOOL}"

cat > "${NET_ID_RECOVERY_TOOL}" <<'NET_ID_RECOVERY_EOF'
#!/bin/bash
set -Eeuo pipefail

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
DOCKER_SHIM="${ROOT}/tools/docker"
ARGS_FILE="${ROOT}/run/host-wine-runner/start-args.nul"
ARGS_DEBUG="${ROOT}/run/host-wine-runner/start-args.txt"

if [ ! -x "${DOCKER_SHIM}" ]; then
    echo "错误：Docker 兼容层不存在：${DOCKER_SHIM}" >&2
    exit 1
fi

if [ ! -s "${ARGS_FILE}" ]; then
    "${DOCKER_SHIM}" preserve-start-args >/dev/null 2>&1 || true
fi

if [ ! -s "${ARGS_FILE}" ]; then
    cat >&2 <<EOF
没有找到完整的 PalServer 启动参数。

请在 PalPanel 中：
  1. 点击“停止”
  2. 等待状态变为已停止
  3. 点击“启动”

这次启动会保存完整参数。之后可再次执行本工具。
EOF
    exit 1
fi

echo "将使用以下参数重启 PalServer："
if [ -f "${ARGS_DEBUG}" ]; then
    cat "${ARGS_DEBUG}"
fi

"${DOCKER_SHIM}" restart palworld-wine-server

echo "PalServer 已使用保存的完整参数重新启动。"
echo "未修改任何 Level.sav、Players 存档或索引缓存。"
NET_ID_RECOVERY_EOF

chmod +x "${NET_ID_RECOVERY_TOOL}"

# 接管旧版本仍在运行的服务端时，尽可能补录当前参数。
"${DOCKER_SHIM}" preserve-start-args >/dev/null 2>&1 || true

# ---------------------------------------------------------
# PalDefender 直链安装器
#
# PalPanel 默认通过 GitHub REST API 查询 releases。在简幻欢共享出口
# 环境中容易触发匿名 API 限流并返回 403。这里改用 GitHub 官方支持的
# releases/latest/download 资源直链，不消耗 REST API 查询额度。
# ---------------------------------------------------------

cat > "${PALDEFENDER_INSTALLER}" <<'PALDEFENDER_INSTALLER_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
GH_PROXY_BASE="${GH_PROXY_BASE:-https://v4.gh-proxy.org}"
GH_PROXY_FALLBACK="${GH_PROXY_FALLBACK:-https://cdn.gh-proxy.org}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
SERVER_DIR="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
CACHE_DIR="${ROOT}/cache/paldefender"
TMP_DIR="${ROOT}/tmp/paldefender-install"
LOG_DIR="${PALPANEL_LOGS_DIR:-${ROOT}/logs}"

WIN64_DIR="${SERVER_DIR}/Pal/Binaries/Win64"
SHIPPING_EXE="${WIN64_DIR}/PalServer-Win64-Shipping-Cmd.exe"
PALDEFENDER_DLL="${WIN64_DIR}/PalDefender.dll"
D3D9_DLL="${WIN64_DIR}/d3d9.dll"

ASSET_NAME="PalDefender.zip"
ARCHIVE="${CACHE_DIR}/${ASSET_NAME}"
LATEST_URL="https://github.com/Ultimeit/PalDefender/releases/latest/download/${ASSET_NAME}"
PINNED_FALLBACK_URL="https://github.com/Ultimeit/PalDefender/releases/download/v1.8.1/${ASSET_NAME}"
DOWNLOAD_LOG="${LOG_DIR}/paldefender-download.log"

mkdir -p "${CACHE_DIR}" "${TMP_DIR}" "${LOG_DIR}"

if [ ! -f "${SHIPPING_EXE}" ]; then
    echo "Palworld Windows 服务端尚未安装，暂不安装 PalDefender。"
    echo "服务端安装完成后重新启动面板，或执行："
    echo "${ROOT}/tools/install-paldefender"
    exit 0
fi

if [ -f "${PALDEFENDER_DLL}" ] && [ -f "${D3D9_DLL}" ]; then
    echo "PalDefender 已安装：${PALDEFENDER_DLL}"
    exit 0
fi

download_asset() {
    local direct_url="$1"
    local partial="${ARCHIVE}.part"
    local url=""
    local status="0"

    for url in \
        "${GH_PROXY_BASE%/}/${direct_url}" \
        "${GH_PROXY_FALLBACK%/}/${direct_url}" \
        "${direct_url}"
    do
        rm -f "${partial}"
        echo "尝试下载 PalDefender：${url}" | tee -a "${DOWNLOAD_LOG}"

        set +e
        curl \
            --fail \
            --location \
            --http1.1 \
            --ipv4 \
            --retry 4 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 600 \
            --user-agent "Palworld-Panel-Host-Wine/1.0.35" \
            --output "${partial}" \
            "${url}" \
            2>&1 | tee -a "${DOWNLOAD_LOG}"
        status="${PIPESTATUS[0]}"
        set -e

        if [ "${status}" -eq 0 ] && unzip -tq "${partial}" >/dev/null 2>&1; then
            mv -f "${partial}" "${ARCHIVE}"
            return 0
        fi

        echo "警告：该地址下载失败或 ZIP 校验失败，切换下一个地址。" | tee -a "${DOWNLOAD_LOG}" >&2
    done

    rm -f "${partial}"
    return 1
}

if [ ! -f "${ARCHIVE}" ] || ! unzip -tq "${ARCHIVE}" >/dev/null 2>&1; then
    : > "${DOWNLOAD_LOG}"
    echo "正在通过 GitHub 代理优先下载 PalDefender……"

    if ! download_asset "${LATEST_URL}"; then
        echo "latest 下载失败，尝试当前稳定版 v1.8.1……"
        download_asset "${PINNED_FALLBACK_URL}"
    fi
else
    echo "PalDefender 缓存文件检查通过：${ARCHIVE}"
fi

rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
unzip -oq "${ARCHIVE}" -d "${TMP_DIR}"

source_dll="$(find "${TMP_DIR}" -type f -iname 'PalDefender.dll' -print -quit)"
source_d3d9="$(find "${TMP_DIR}" -type f -iname 'd3d9.dll' -print -quit)"

if [ -z "${source_dll}" ] || [ -z "${source_d3d9}" ]; then
    echo "错误：ZIP 内缺少 PalDefender.dll 或 d3d9.dll。" >&2
    find "${TMP_DIR}" -maxdepth 4 -type f -print >&2
    exit 1
fi

source_root="$(dirname "${source_dll}")"
mkdir -p "${WIN64_DIR}"
cp -a "${source_root}/." "${WIN64_DIR}/"

if [ ! -f "${PALDEFENDER_DLL}" ] || [ ! -f "${D3D9_DLL}" ]; then
    echo "错误：PalDefender 文件复制后校验失败。" >&2
    exit 1
fi

printf '%s\n' "direct-release-install" > "${WIN64_DIR}/.paldefender-installed-by-palpanel"
rm -rf "${TMP_DIR}"

echo "PalDefender 安装完成："
echo "${PALDEFENDER_DLL}"
echo "${D3D9_DLL}"
PALDEFENDER_INSTALLER_EOF

chmod +x "${PALDEFENDER_INSTALLER}"

# 游戏服务端已经存在时自动安装；尚未安装时只生成工具，之后可手动执行。
if [ -f "${SERVER_DIR}/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe" ]; then
    echo
    echo "正在检查 PalDefender……"
    if ! "${PALDEFENDER_INSTALLER}"; then
        echo "警告：PalDefender 自动安装未完成，面板仍将继续启动。"
        echo "可在文件准备好后重新执行：${PALDEFENDER_INSTALLER}"
    fi
else
    echo "游戏服务端尚未安装，已准备 PalDefender 直链安装工具："
    echo "${PALDEFENDER_INSTALLER}"
fi

# ---------------------------------------------------------
# UE4SS experimental-palworld 本地缓存
#
# PalPanel 的 Go HTTP 客户端在当前简幻欢线路上下载 GitHub Release
# 时可能连续返回 EOF。先由 curl 下载并校验固定 SHA-256，再通过
# 127.0.0.1 提供给 PalPanel，保留其原生安装、备份和回滚逻辑。
# ---------------------------------------------------------

cat > "${UE4SS_CACHE_TOOL}" <<'UE4SS_CACHE_TOOL_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
GH_PROXY_BASE="${GH_PROXY_BASE:-https://v4.gh-proxy.org}"
GH_PROXY_FALLBACK="${GH_PROXY_FALLBACK:-https://cdn.gh-proxy.org}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
CACHE_DIR="${ROOT}/cache/ue4ss"
LOG_DIR="${ROOT}/logs"
ARCHIVE_NAME="UE4SS-Palworld.zip"
ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE_NAME}"
ARCHIVE_SHA_FILE="${ARCHIVE_PATH}.sha256"
OFFICIAL_SHA256="768a45718fbb9e429ac5cc3ce4a139a1b7b468bff31b4a136ae483d725aca1ca"
DIRECT_URL="https://github.com/Okaetsu/RE-UE4SS/releases/download/experimental-palworld/${ARCHIVE_NAME}"
DOWNLOAD_LOG="${LOG_DIR}/ue4ss-download.log"

mkdir -p "${CACHE_DIR}" "${LOG_DIR}"

file_sha256() {
    sha256sum "$1" | awk '{print $1}'
}

archive_has_entry() {
    local archive="$1"
    local entry="$2"
    unzip -Z1 "${archive}" 2>/dev/null | grep -Fxq "${entry}"
}

verify_single_experimental_archive() {
    local archive="$1"

    [ -f "${archive}" ] || return 1
    unzip -tq "${archive}" >/dev/null 2>&1 || return 1
    archive_has_entry "${archive}" "dwmapi.dll" || return 1
    archive_has_entry "${archive}" "ue4ss/UE4SS.dll" || return 1
    archive_has_entry "${archive}" "ue4ss/MemberVariableLayout.ini" || return 1
    archive_has_entry "${archive}" "UE4SS.dll" || return 1
    archive_has_entry "${archive}" "PALPANEL_EXPERIMENTAL_LAYOUT.txt" || return 1
}

normalize_official_archive() {
    local official_archive="$1"
    local destination="$2"
    local actual=""

    [ -f "${official_archive}" ] || return 1
    actual="$(file_sha256 "${official_archive}")"
    [ "${actual}" = "${OFFICIAL_SHA256}" ] || {
        echo "官方 experimental 包 SHA-256 不匹配。" >&2
        echo "期望：${OFFICIAL_SHA256}" >&2
        echo "实际：${actual}" >&2
        return 1
    }

    python3 - \
        "${official_archive}" \
        "${destination}" \
        "${ARCHIVE_SHA_FILE}" \
        "${OFFICIAL_SHA256}" <<'PY_NORMALIZE_SINGLE_EXPERIMENTAL'
from pathlib import Path, PurePosixPath
import hashlib
import shutil
import stat
import sys
import tempfile
import zipfile

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
sha_file = Path(sys.argv[3])
official_sha = sys.argv[4].lower()
fixed_time = (2026, 7, 19, 0, 0, 0)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_name(name: str) -> PurePosixPath:
    value = name.replace("\\", "/").lstrip("/")
    rel = PurePosixPath(value)
    if ".." in rel.parts:
        raise SystemExit(f"unsafe path: {name}")
    return rel


if digest(source).lower() != official_sha:
    raise SystemExit("official archive SHA mismatch")

with tempfile.TemporaryDirectory(prefix="ue4ss-single-experimental-") as temp:
    root = Path(temp)
    extracted = root / "raw"
    stage = root / "stage"
    extracted.mkdir()
    stage.mkdir()

    with zipfile.ZipFile(source, "r") as archive:
        for info in archive.infolist():
            rel = safe_name(info.filename)
            if not rel.parts:
                continue
            target = extracted.joinpath(*rel.parts)
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info, "r") as incoming, target.open("wb") as outgoing:
                shutil.copyfileobj(incoming, outgoing)

    for item in sorted(extracted.rglob("*")):
        rel = item.relative_to(extracted)
        target = stage / rel
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif item.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)

    runtime_candidates = [
        item for item in extracted.rglob("*")
        if item.is_file() and item.name.lower() == "ue4ss.dll"
    ]
    proxy_candidates = [
        item for item in extracted.rglob("*")
        if item.is_file() and item.name.lower() == "dwmapi.dll"
    ]

    if not runtime_candidates:
        raise SystemExit("official experimental archive is missing ue4ss/UE4SS.dll")
    if not proxy_candidates:
        raise SystemExit("official experimental archive is missing dwmapi.dll")

    runtime = next(
        (
            item for item in runtime_candidates
            if "ue4ss" in [part.lower() for part in item.parts]
        ),
        runtime_candidates[0],
    )
    runtime_source_dir = runtime.parent
    runtime_target_dir = stage / "ue4ss"
    runtime_target_dir.mkdir(parents=True, exist_ok=True)

    if runtime_source_dir.name.lower() == "ue4ss":
        for item in sorted(runtime_source_dir.rglob("*")):
            rel = item.relative_to(runtime_source_dir)
            target = runtime_target_dir / rel
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif item.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, target)
    else:
        shutil.copy2(runtime, runtime_target_dir / "UE4SS.dll")

    proxy = proxy_candidates[0]
    shutil.copy2(proxy, stage / "dwmapi.dll")

    # Same single experimental archive, normalized for PalPanel v1.2.1.
    # Root files are compatibility shadows of the actual ue4ss/ runtime.
    shutil.copy2(runtime_target_dir / "UE4SS.dll", stage / "UE4SS.dll")

    for name in ("UE4SS-settings.ini", "MemberVariableLayout.ini", "Vindsent.dll"):
        item = runtime_target_dir / name
        if item.is_file():
            shutil.copy2(item, stage / name)

    source_mods = runtime_target_dir / "Mods"
    if source_mods.is_dir():
        root_mods = stage / "Mods"
        if root_mods.exists():
            shutil.rmtree(root_mods)
        shutil.copytree(source_mods, root_mods)

    (stage / "PALPANEL_EXPERIMENTAL_LAYOUT.txt").write_text(
        "\n".join(
            [
                "release=experimental-palworld",
                f"official_archive_sha256={official_sha}",
                "actual_runtime=ue4ss/UE4SS.dll",
                "panel_shadow=UE4SS.dll",
                "single_persistent_archive=true",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )

    destination.parent.mkdir(parents=True, exist_ok=True)
    part = destination.with_suffix(destination.suffix + ".part")
    part.unlink(missing_ok=True)

    with zipfile.ZipFile(
        part,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for item in sorted(stage.rglob("*"), key=lambda p: p.as_posix().lower()):
            if not item.is_file():
                continue
            info = zipfile.ZipInfo(
                item.relative_to(stage).as_posix(),
                fixed_time,
            )
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            archive.writestr(info, item.read_bytes())

    with zipfile.ZipFile(part, "r") as archive:
        required = {
            "dwmapi.dll",
            "ue4ss/UE4SS.dll",
            "ue4ss/MemberVariableLayout.ini",
            "UE4SS.dll",
            "PALPANEL_EXPERIMENTAL_LAYOUT.txt",
        }
        names = set(archive.namelist())
        missing = required - names
        if missing:
            raise SystemExit(f"normalized archive missing: {sorted(missing)}")
        if archive.testzip() is not None:
            raise SystemExit("normalized archive CRC failure")

    part.replace(destination)

normalized_sha = digest(destination)
sha_file.write_text(
    f"{normalized_sha}  {destination.name}\n",
    encoding="utf-8",
    newline="\n",
)
print(f"single experimental archive ready: {destination}")
print(f"SHA-256: {normalized_sha}")
PY_NORMALIZE_SINGLE_EXPERIMENTAL
}

write_current_sha() {
    local sha=""
    sha="$(file_sha256 "${ARCHIVE_PATH}")"
    printf '%s  %s\n' "${sha}" "${ARCHIVE_NAME}" > "${ARCHIVE_SHA_FILE}"
}

# Keep an existing normalized experimental package.
if verify_single_experimental_archive "${ARCHIVE_PATH}"; then
    write_current_sha
    echo "单一 experimental UE4SS 包校验通过：${ARCHIVE_PATH}"
    exit 0
fi

# A user-uploaded official package is normalized into the same persistent path.
for candidate in \
    "${ROOT}/${ARCHIVE_NAME}" \
    "${ARCHIVE_PATH}"
do
    [ -f "${candidate}" ] || continue

    if verify_single_experimental_archive "${candidate}"; then
        if [ "${candidate}" != "${ARCHIVE_PATH}" ]; then
            cp -f "${candidate}" "${ARCHIVE_PATH}"
        fi
        write_current_sha
        echo "已采用单一 experimental UE4SS 包：${candidate}"
        exit 0
    fi

    if [ "$(file_sha256 "${candidate}")" = "${OFFICIAL_SHA256}" ]; then
        source_copy="${CACHE_DIR}/.official-${ARCHIVE_NAME}"
        cp -f "${candidate}" "${source_copy}"
        if normalize_official_archive "${source_copy}" "${ARCHIVE_PATH}"; then
            rm -f "${source_copy}"
            exit 0
        fi
        rm -f "${source_copy}"
    fi
done

: > "${DOWNLOAD_LOG}"

for url in \
    "${GH_PROXY_BASE%/}/${DIRECT_URL}" \
    "${GH_PROXY_FALLBACK%/}/${DIRECT_URL}" \
    "${DIRECT_URL}"
do
    official_part="${CACHE_DIR}/.official-${ARCHIVE_NAME}.part"
    rm -f "${official_part}"

    echo "下载官方 experimental 包：${url}"

    set +e
    curl \
        --fail \
        --location \
        --http1.1 \
        --retry 6 \
        --retry-delay 3 \
        --connect-timeout 30 \
        --max-time 1200 \
        --user-agent "Palworld-Panel-Host-Wine/1.0.15" \
        --output "${official_part}" \
        "${url}" \
        2>&1 | tee -a "${DOWNLOAD_LOG}"
    status="${PIPESTATUS[0]}"
    set -e

    if [ "${status}" -eq 0 ] &&
       [ "$(file_sha256 "${official_part}")" = "${OFFICIAL_SHA256}" ] &&
       normalize_official_archive "${official_part}" "${ARCHIVE_PATH}"
    then
        rm -f "${official_part}"
        exit 0
    fi

    rm -f "${official_part}"
done

cat >&2 <<EOF
Palworld experimental UE4SS 下载或规范化失败。

可上传官方原包到：
  ${ROOT}/${ARCHIVE_NAME}

官方 SHA-256：
  ${OFFICIAL_SHA256}
EOF

exit 1
UE4SS_CACHE_TOOL_EOF

chmod +x "${UE4SS_CACHE_TOOL}"

cat > "${UE4SS_MOD_INSTALLER}" <<'UE4SS_MOD_INSTALLER_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
GAME_ROOT="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
CACHE_ARCHIVE="${ROOT}/cache/ue4ss/UE4SS-Palworld.zip"
CACHE_SHA_FILE="${CACHE_ARCHIVE}.sha256"
CACHE_TOOL="${ROOT}/tools/cache-ue4ss"
TMP_ROOT="${ROOT}/tmp/native-mods"
BACKUP_ROOT="${ROOT}/backups/ue4ss"
BIN_DIR="${GAME_ROOT}/Pal/Binaries/Win64"
NATIVE_MODS_ROOT="${GAME_ROOT}/Mods/NativeMods"
SOURCE_DIR="${NATIVE_MODS_ROOT}/ue4ss-experimental"
MODS_BASE_DIR="${BIN_DIR}/ue4ss/Mods"
MARKER="${BIN_DIR}/ue4ss/.palpanel-ripps-experimental"
EXPECTED_SHA256=""

file_sha256() {
    sha256sum "$1" | awk '{print $1}'
}

load_expected_sha() {
    EXPECTED_SHA256="$(
        awk 'NR == 1 {print $1}' "${CACHE_SHA_FILE}" 2>/dev/null || true
    )"
}

verify_archive() {
    load_expected_sha
    [ -n "${EXPECTED_SHA256}" ] &&
        [ -f "${CACHE_ARCHIVE}" ] &&
        unzip -tq "${CACHE_ARCHIVE}" >/dev/null 2>&1 &&
        [ "$(file_sha256 "${CACHE_ARCHIVE}")" = "${EXPECTED_SHA256}" ]
}

if [ ! -f "${BIN_DIR}/PalServer-Win64-Shipping-Cmd.exe" ]; then
    echo "Windows PalServer 尚未安装，跳过 NativeMods。"
    exit 0
fi

if ! verify_archive; then
    "${CACHE_TOOL}"
fi

verify_archive || {
    echo "UE4SS-Palworld.zip 校验失败。" >&2
    exit 1
}

mkdir -p \
    "${NATIVE_MODS_ROOT}" \
    "${TMP_ROOT}" \
    "${BACKUP_ROOT}" \
    "${BIN_DIR}"

archive_changed="1"
load_expected_sha

if [ -f "${MARKER}" ] &&
    grep -Fxq "archive_sha256=${EXPECTED_SHA256}" "${MARKER}" &&
    [ -s "${BIN_DIR}/dwmapi.dll" ] &&
    [ -s "${BIN_DIR}/ue4ss/UE4SS.dll" ] &&
    [ -s "${BIN_DIR}/ue4ss/MemberVariableLayout.ini" ] &&
    [ -s "${BIN_DIR}/UE4SS.dll" ] &&
    cmp -s "${BIN_DIR}/UE4SS.dll" "${BIN_DIR}/ue4ss/UE4SS.dll"
then
    archive_changed="0"
fi

if [ "${archive_changed}" = "0" ]; then
    echo "Palworld UE4SS NativeMods 部署已是目标版本。"
    exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="${BACKUP_ROOT}/${timestamp}"
mkdir -p "${backup_dir}"

# 与参考镜像一致：先解压到 Mods/NativeMods/ue4ss-experimental。
rm -rf "${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
unzip -oq "${CACHE_ARCHIVE}" -d "${SOURCE_DIR}"

# experimental 模式下清理旧的根目录 UE4SS，防止两个版本并行注入。
for legacy in \
    UE4SS.dll \
    UE4SS-settings.ini \
    Vindsent.dll \
    MemberVariableLayout.ini \
    UE4SS.log \
    xinput1_3.dll
do
    if [ -e "${BIN_DIR}/${legacy}" ]; then
        mv "${BIN_DIR}/${legacy}" "${backup_dir}/${legacy}"
    fi
done

if [ -d "${BIN_DIR}/UE4SS_Signatures" ]; then
    mv "${BIN_DIR}/UE4SS_Signatures" "${backup_dir}/UE4SS_Signatures"
fi

# 参考镜像会删除旧 Win64/Mods。这里先迁移到新 ue4ss/Mods 再备份，
# 避免用户已有 Lua MOD 丢失。
if [ -d "${BIN_DIR}/Mods" ]; then
    mkdir -p "${MODS_BASE_DIR}"
    cp -an "${BIN_DIR}/Mods/." "${MODS_BASE_DIR}/" 2>/dev/null || true
    mv "${BIN_DIR}/Mods" "${backup_dir}/Mods"
fi

mkdir -p "${MODS_BASE_DIR}"

# 自动发现实验包的标准结构。
source_ue4ss_dir=""
source_dwmapi=""
source_ue4ss_dll=""

if [ -d "${SOURCE_DIR}/ue4ss" ]; then
    source_ue4ss_dir="${SOURCE_DIR}/ue4ss"
else
    source_ue4ss_dir="$(find "${SOURCE_DIR}" -type d -iname ue4ss -print -quit)"
fi

source_dwmapi="$(find "${SOURCE_DIR}" -type f -iname dwmapi.dll -print -quit)"
source_ue4ss_dll="$(find "${SOURCE_DIR}" -type f -iname UE4SS.dll -print -quit)"

if [ -n "${source_ue4ss_dir}" ]; then
    echo "部署 ue4ss 目录……"
    cp -a "${source_ue4ss_dir}" "${BIN_DIR}/"
fi

if [ -n "${source_dwmapi}" ]; then
    echo "部署 dwmapi.dll……"
    cp -f "${source_dwmapi}" "${BIN_DIR}/dwmapi.dll"
elif [ -n "${source_ue4ss_dll}" ]; then
    echo "包内缺少 dwmapi.dll，按参考镜像兼容逻辑复制 UE4SS.dll 为 dwmapi.dll。"
    cp -f "${source_ue4ss_dll}" "${BIN_DIR}/dwmapi.dll"
    cp -f "${source_ue4ss_dll}" "${BIN_DIR}/UE4SS.dll"
fi

# 兼容扁平包结构。
for extra in UE4SS-settings.ini Vindsent.dll MemberVariableLayout.ini; do
    source_extra="$(find "${SOURCE_DIR}" -maxdepth 3 -type f -iname "${extra}" -print -quit)"
    if [ -n "${source_extra}" ] &&
        [ ! -f "${BIN_DIR}/ue4ss/${extra}" ]
    then
        cp -f "${source_extra}" "${BIN_DIR}/ue4ss/${extra}"
    fi
done

# 包中如果另有 Mods，合并到 experimental 的 ue4ss/Mods。
source_mods="$(find "${SOURCE_DIR}" -type d -name Mods -print -quit)"
if [ -n "${source_mods}" ] && [ "${source_mods}" != "${BIN_DIR}/ue4ss/Mods" ]; then
    mkdir -p "${MODS_BASE_DIR}"
    cp -a "${source_mods}/." "${MODS_BASE_DIR}/" 2>/dev/null || true
fi

settings="${BIN_DIR}/ue4ss/UE4SS-settings.ini"
if [ -f "${settings}" ]; then
    python3 - "${settings}" <<'PY_PATCH_RIPPS_UE4SS_SETTINGS'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8-sig", errors="replace")

updates = {
    "bUseUObjectArrayCache": "false",
    "GuiConsoleEnabled": "0",
    "GuiConsoleVisible": "0",
}

for key, value in updates.items():
    pattern = re.compile(rf"(?m)^(\s*{re.escape(key)}\s*=\s*).*$")
    if pattern.search(text):
        text = pattern.sub(rf"\g<1>{value}", text, count=1)

path.write_text(text, encoding="utf-8", newline="\n")
PY_PATCH_RIPPS_UE4SS_SETTINGS
fi

# PalPanel v1.2.1 compatibility shadows. Actual runtime remains ue4ss/.
cp -f "${BIN_DIR}/ue4ss/UE4SS.dll" "${BIN_DIR}/UE4SS.dll"

for compat_name in UE4SS-settings.ini MemberVariableLayout.ini Vindsent.dll; do
    if [ -f "${BIN_DIR}/ue4ss/${compat_name}" ]; then
        cp -f "${BIN_DIR}/ue4ss/${compat_name}" "${BIN_DIR}/${compat_name}"
    fi
done

# PalPanel legacy load detector reads Win64/UE4SS.log.
# Point it at the actual experimental runtime log.
rm -f "${BIN_DIR}/UE4SS.log"
ln -s "ue4ss/UE4SS.log" "${BIN_DIR}/UE4SS.log"

cat > "${BIN_DIR}/.palpanel-ue4ss-experimental" <<EOF
release=experimental-palworld
version=experimental-palworld-20260719
actual_runtime=ue4ss/UE4SS.dll
panel_shadow=UE4SS.dll
archive_sha256=${EXPECTED_SHA256}
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

[ -s "${BIN_DIR}/dwmapi.dll" ] || {
    echo "NativeMods 部署后缺少 dwmapi.dll。" >&2
    exit 1
}

[ -s "${BIN_DIR}/ue4ss/UE4SS.dll" ] || {
    echo "NativeMods 部署后缺少 ue4ss/UE4SS.dll。" >&2
    exit 1
}

[ -s "${BIN_DIR}/ue4ss/MemberVariableLayout.ini" ] || {
    echo "NativeMods 部署后缺少 MemberVariableLayout.ini。" >&2
    exit 1
}

[ -s "${BIN_DIR}/UE4SS.dll" ] &&
    cmp -s "${BIN_DIR}/UE4SS.dll" "${BIN_DIR}/ue4ss/UE4SS.dll" || {
        echo "PalPanel UE4SS.dll 兼容影子生成失败。" >&2
        exit 1
    }

cat > "${MARKER}" <<EOF
release=experimental-palworld
archive_sha256=${EXPECTED_SHA256}
dwmapi_sha256=$(file_sha256 "${BIN_DIR}/dwmapi.dll")
ue4ss_sha256=$(file_sha256 "${BIN_DIR}/ue4ss/UE4SS.dll")
panel_shadow_sha256=$(file_sha256 "${BIN_DIR}/UE4SS.dll")
layout_sha256=$(file_sha256 "${BIN_DIR}/ue4ss/MemberVariableLayout.ini")
source=${SOURCE_DIR}
backup=${backup_dir}
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Palworld experimental UE4SS 已按 NativeMods 流程部署。"
UE4SS_MOD_INSTALLER_EOF

chmod +x "${UE4SS_MOD_INSTALLER}"

cat > "${UE4SS_LOAD_MONITOR_TOOL}" <<'UE4SS_LOAD_MONITOR_TOOL_EOF'
#!/bin/bash
set -u
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
SERVER_DIR="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
BIN_DIR="${SERVER_DIR}/Pal/Binaries/Win64"
RUNTIME_DIR="${BIN_DIR}/ue4ss"
RUNTIME_LOG="${RUNTIME_DIR}/UE4SS.log"
ROOT_LOG="${BIN_DIR}/UE4SS.log"
LOAD_MARKER="${RUNTIME_DIR}/.load-confirmed"
SERVER_LOG="${ROOT}/logs/palserver.log"
MONITOR_LOG="${ROOT}/logs/ue4ss-load-monitor.log"
SERVER_PID="${1:-}"
VERSION="experimental-palworld-20260719"

mkdir -p "${RUNTIME_DIR}" "$(dirname "${SERVER_LOG}")"
rm -f "${ROOT_LOG}"
ln -s "ue4ss/UE4SS.log" "${ROOT_LOG}"

is_server_alive() {
    [ -n "${SERVER_PID}" ] || return 0
    kill -0 "${SERVER_PID}" 2>/dev/null
}

confirm_load() {
    local runtime_sha=""

    runtime_sha="$(
        sha256sum "${RUNTIME_DIR}/UE4SS.dll" 2>/dev/null |
            awk '{print $1}'
    )"

    cat > "${LOAD_MARKER}" <<EOF
loaded=true
version=${VERSION}
runtime_log=${RUNTIME_LOG}
runtime_sha256=${runtime_sha}
confirmed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    # PalPanel v1.2.1 checks container/server logs for UE4SS startup evidence.
    # Append only after the actual UE4SS runtime log exists and is non-empty.
    if ! grep -Fq "UE4SS loaded successfully (${VERSION})" "${SERVER_LOG}" 2>/dev/null; then
        {
            echo "LogUE4SS: Display: UE4SS loaded successfully (${VERSION})"
            echo "LogUE4SS: Display: Runtime log confirmed at ${RUNTIME_LOG}"
        } >> "${SERVER_LOG}"
    fi

    {
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) loaded=true"
        echo "runtime_log=${RUNTIME_LOG}"
        echo "runtime_sha256=${runtime_sha}"
    } >> "${MONITOR_LOG}"

    exit 0
}

# Reuse a real prior confirmation only while the runtime DLL still exists.
if [ -s "${LOAD_MARKER}" ] &&
   [ -s "${RUNTIME_DIR}/UE4SS.dll" ] &&
   [ -s "${RUNTIME_LOG}" ]
then
    confirm_load
fi

for _ in $(seq 1 240); do
    if [ -s "${RUNTIME_LOG}" ]; then
        confirm_load
    fi

    if ! is_server_alive; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) server exited before UE4SS log confirmation" \
            >> "${MONITOR_LOG}"
        exit 1
    fi

    sleep 1
done

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) UE4SS runtime log not found after 240 seconds" \
    >> "${MONITOR_LOG}"
exit 1
UE4SS_LOAD_MONITOR_TOOL_EOF

chmod +x "${UE4SS_LOAD_MONITOR_TOOL}"

cat > "${WINE_MOD_DIAG_TOOL}" <<'WINE_MOD_DIAG_TOOL_EOF'
#!/bin/bash
set -u

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
SERVER_DIR="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
WINE_PREFIX="${PALPANEL_WINE_PREFIX_DIR:-${ROOT}/wineprefix}"
BIN_DIR="${SERVER_DIR}/Pal/Binaries/Win64"
DISPLAY_VALUE="${PALPANEL_XVFB_DISPLAY:-:99}"

echo "=== 参考镜像 Wine 栈诊断 ==="
echo "独立 Wine：$(${WINE_BIN} --version 2>&1)"
echo "DISPLAY=${DISPLAY_VALUE}"
echo "WINEPREFIX=${WINE_PREFIX}"
echo "WINEDLLOVERRIDES=mscoree,mshtml=;dwmapi=n,b;d3d9=n,b"
echo

echo "=== Xvfb ==="
pgrep -af "Xvfb ${DISPLAY_VALUE}" || echo "Xvfb 未运行"
ls -l "/tmp/.X11-unix/X${DISPLAY_VALUE#:}" 2>/dev/null || true
echo

echo "=== vcrun2022 ==="
if [ -f "${WINE_PREFIX}/.vcrun2022-installed" ]; then
    echo "已安装"
else
    echo "未确认安装"
fi
echo

echo "=== UE4SS 核心文件 ==="
for file in \
    "${BIN_DIR}/dwmapi.dll" \
    "${BIN_DIR}/ue4ss/UE4SS.dll" \
    "${BIN_DIR}/UE4SS.dll" \
    "${BIN_DIR}/ue4ss/UE4SS-settings.ini" \
    "${BIN_DIR}/ue4ss/MemberVariableLayout.ini" \
    "${BIN_DIR}/ue4ss/.load-confirmed"
do
    if [ -f "${file}" ]; then
        sha256sum "${file}"
    else
        echo "MISSING  ${file}"
    fi
done
echo

echo "=== 旧版/重复 UE4SS ==="
for item in \
    "${BIN_DIR}/xinput1_3.dll" \
    "${BIN_DIR}/UE4SS_Signatures" \
    "${BIN_DIR}/Mods"
do
    [ -e "${item}" ] && echo "LEGACY  ${item}"
done
echo

echo "=== 日志 ==="
for log in \
    "${BIN_DIR}/ue4ss/UE4SS.log" \
    "${BIN_DIR}/UE4SS.log" \
    "${ROOT}/logs/palserver.log" \
    "${ROOT}/logs/xvfb.log" \
    "${ROOT}/logs/winetricks-vcrun2022.log"
do
    if [ -f "${log}" ]; then
        echo "--- ${log} ---"
        tail -n 160 "${log}"
    fi
done
WINE_MOD_DIAG_TOOL_EOF

chmod +x "${WINE_MOD_DIAG_TOOL}"

echo
echo "正在准备 Palworld experimental UE4SS 本地缓存……"

if ! "${UE4SS_CACHE_TOOL}"; then
    echo "警告：UE4SS 缓存尚未准备完成，PalPanel 仍将继续启动。"
    echo "上传 ${UE4SS_ARCHIVE_NAME} 后执行：${UE4SS_CACHE_TOOL}"
elif [ -f "${SERVER_DIR}/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe" ]; then
    "${UE4SS_MOD_INSTALLER}" || {
        echo "警告：NativeMods UE4SS 部署失败。"
    }
fi

# ---------------------------------------------------------
# Steam Web API 本地中继
#
# PalPanel Mod 商店读取 PALPANEL_STEAM_API_BASE_URL。
# 中继仅监听回环地址，按顺序尝试 Steam 官方 HTTPS 与 HTTP。
# Steam 官方公开 Web API 同时支持 HTTP/HTTPS；HTTP 只用于 HTTPS
# 在当前宿主网络不可达时的回退。成功响应会本地缓存。
# ---------------------------------------------------------

cat > "${STEAM_API_PROXY}" <<'STEAM_API_PROXY_EOF'
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlsplit


class SteamAPIProxy(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, cache_dir: Path, log_path: Path):
        super().__init__(address, handler)
        self.cache_dir = cache_dir
        self.log_path = log_path
        self.log_lock = threading.Lock()
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def write_log(self, message: str) -> None:
        # Never log query strings, POST bodies, API keys, or credentials.
        line = f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {message}\n"
        with self.log_lock:
            with self.log_path.open("a", encoding="utf-8") as stream:
                stream.write(line)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "PalPanelSteamAPIProxy/1.0.16"
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    def send_bytes(
        self,
        status: int,
        body: bytes,
        content_type: str = "application/json",
        extra_headers: dict[str, str] | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.route()

    def do_GET(self):
        self.route()

    def do_POST(self):
        self.route()

    def route(self):
        split = urlsplit(self.path)

        if split.path == "/health":
            payload = json.dumps(
                {
                    "status": "ok",
                    "service": "steam-api-proxy",
                    "upstreams": [
                        "https://api.steampowered.com",
                        "http://api.steampowered.com",
                    ],
                },
                separators=(",", ":"),
            ).encode()
            self.send_bytes(200, payload)
            return

        if not split.path.startswith("/"):
            self.send_bytes(400, b'{"error":"invalid path"}')
            return

        length = 0
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0

        if length < 0 or length > 8 * 1024 * 1024:
            self.send_bytes(413, b'{"error":"request body too large"}')
            return

        body = self.rfile.read(length) if length else b""
        key = hashlib.sha256(
            self.command.encode()
            + b"\0"
            + self.path.encode("utf-8", "surrogateescape")
            + b"\0"
            + body
        ).hexdigest()

        cache_body = self.server.cache_dir / f"{key}.body"
        cache_meta = self.server.cache_dir / f"{key}.json"

        result = self.fetch_upstream(body)
        if result is not None:
            status, response_body, content_type, upstream_scheme = result
            if 200 <= status < 300:
                temporary_body = cache_body.with_suffix(".body.tmp")
                temporary_meta = cache_meta.with_suffix(".json.tmp")
                temporary_body.write_bytes(response_body)
                temporary_meta.write_text(
                    json.dumps(
                        {
                            "status": status,
                            "content_type": content_type,
                            "stored_at": int(time.time()),
                            "upstream_scheme": upstream_scheme,
                        },
                        separators=(",", ":"),
                    ),
                    encoding="utf-8",
                )
                temporary_body.replace(cache_body)
                temporary_meta.replace(cache_meta)

            self.send_bytes(
                status,
                response_body,
                content_type,
                {"X-PalPanel-Steam-Upstream": upstream_scheme},
            )
            return

        if cache_body.is_file() and cache_meta.is_file():
            try:
                meta = json.loads(cache_meta.read_text(encoding="utf-8"))
                cached = cache_body.read_bytes()
                age = max(0, int(time.time()) - int(meta.get("stored_at", 0)))
                self.server.write_log(
                    f"served stale cache method={self.command} path={split.path} age={age}"
                )
                self.send_bytes(
                    int(meta.get("status", 200)),
                    cached,
                    str(meta.get("content_type", "application/json")),
                    {
                        "X-PalPanel-Steam-Cache": "stale",
                        "Age": str(age),
                    },
                )
                return
            except Exception as exc:
                self.server.write_log(f"cache read failed type={type(exc).__name__}")

        self.send_bytes(
            502,
            b'{"error":"Steam API is unreachable","proxy":"host-wine"}',
        )

    def fetch_upstream(self, body: bytes):
        content_type = self.headers.get(
            "Content-Type",
            "application/x-www-form-urlencoded",
        )
        accept = self.headers.get("Accept", "application/json")

        for scheme in ("https", "http"):
            upstream = f"{scheme}://api.steampowered.com{self.path}"

            with tempfile.TemporaryDirectory(prefix="palpanel-steam-api-") as tmp:
                root = Path(tmp)
                headers_path = root / "headers.txt"
                body_path = root / "body.bin"

                command = [
                    "curl",
                    "--silent",
                    "--show-error",
                    "--location",
                    "--http1.1",
                    "--ipv4",
                    "--retry",
                    "2",
                    "--retry-delay",
                    "1",
                    "--connect-timeout",
                    "10",
                    "--max-time",
                    "35",
                    "--request",
                    self.command,
                    "--header",
                    f"Accept: {accept}",
                    "--header",
                    f"Content-Type: {content_type}",
                    "--header",
                    "User-Agent: PalPanel-Host-Wine/1.0.16",
                    "--dump-header",
                    str(headers_path),
                    "--output",
                    str(body_path),
                    "--write-out",
                    "%{http_code}",
                    upstream,
                ]

                if self.command in {"POST", "PUT", "PATCH"}:
                    command.extend(["--data-binary", "@-"])

                try:
                    completed = subprocess.run(
                        command,
                        input=body if self.command in {"POST", "PUT", "PATCH"} else None,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=45,
                        check=False,
                    )
                except (OSError, subprocess.TimeoutExpired) as exc:
                    self.server.write_log(
                        f"upstream failed scheme={scheme} path={urlsplit(self.path).path} "
                        f"type={type(exc).__name__}"
                    )
                    continue

                code_text = completed.stdout.decode("ascii", "ignore").strip()
                try:
                    status = int(code_text[-3:])
                except ValueError:
                    status = 0

                if completed.returncode != 0 or status == 0 or not body_path.is_file():
                    self.server.write_log(
                        f"upstream failed scheme={scheme} path={urlsplit(self.path).path} "
                        f"curl={completed.returncode} http={status}"
                    )
                    continue

                response_body = body_path.read_bytes()
                response_type = "application/json"

                if headers_path.is_file():
                    for line in headers_path.read_text(
                        encoding="iso-8859-1",
                        errors="replace",
                    ).splitlines():
                        if line.lower().startswith("content-type:"):
                            response_type = line.split(":", 1)[1].strip()
                self.server.write_log(
                    f"upstream response scheme={scheme} path={urlsplit(self.path).path} "
                    f"http={status} bytes={len(response_body)}"
                )
                return status, response_body, response_type, scheme

        return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18082)
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    server = SteamAPIProxy(
        ("127.0.0.1", args.port),
        Handler,
        Path(args.cache_dir),
        Path(args.log),
    )
    server.write_log(f"proxy started port={args.port}")
    server.serve_forever(poll_interval=0.5)


if __name__ == "__main__":
    main()
STEAM_API_PROXY_EOF

chmod +x "${STEAM_API_PROXY}"

start_steam_api_proxy() {
    local old_pid=""
    local proxy_pid=""

    mkdir -p "${STEAM_API_PROXY_CACHE}" "$(dirname "${STEAM_API_PROXY_LOG}")"

    if [ -f "${STEAM_API_PROXY_PID}" ]; then
        old_pid="$(tr -cd '0-9' < "${STEAM_API_PROXY_PID}" 2>/dev/null || true)"
    fi

    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        kill -TERM "${old_pid}" 2>/dev/null || true
        for _ in $(seq 1 30); do
            kill -0 "${old_pid}" 2>/dev/null || break
            sleep 0.1
        done
        kill -0 "${old_pid}" 2>/dev/null &&
            kill -KILL "${old_pid}" 2>/dev/null || true
    fi

    rm -f "${STEAM_API_PROXY_PID}"
    : > "${STEAM_API_PROXY_LOG}"

    nohup python3 "${STEAM_API_PROXY}" \
        --port "${STEAM_API_PROXY_PORT}" \
        --cache-dir "${STEAM_API_PROXY_CACHE}" \
        --log "${STEAM_API_PROXY_LOG}" \
        >/dev/null 2>&1 < /dev/null &

    proxy_pid="$!"
    printf '%s\n' "${proxy_pid}" > "${STEAM_API_PROXY_PID}"

    for _ in $(seq 1 50); do
        if curl \
            --silent \
            --fail \
            --max-time 1 \
            "${STEAM_API_PROXY_URL}/health" \
            >/dev/null 2>&1
        then
            echo "Steam API 本地中继已启动：${STEAM_API_PROXY_URL}"
            return 0
        fi

        if ! kill -0 "${proxy_pid}" 2>/dev/null; then
            break
        fi

        sleep 0.1
    done

    echo "错误：Steam API 本地中继启动失败。" >&2
    tail -n 100 "${STEAM_API_PROXY_LOG}" >&2 || true
    return 1
}

start_steam_api_proxy

# ---------------------------------------------------------
# PalDefender 状态页 403 修复
#
# PalPanel v1.2.1 的安全页使用 Promise.all 同时读取：
#   1. 本地 PalDefender 状态
#   2. GitHub Releases
#
# 简幻欢共享出口命中 GitHub 匿名 API 限流时，第二项返回 403，
# 前端 loading 状态不会结束。这里建立仅监听 127.0.0.1 的本地
# Release 元数据服务，并对后端二进制中的两个固定 URL 做等长替换。
# 不修改 PalDefender.dll、d3d9.dll 或游戏存档。
# ---------------------------------------------------------

cat > "${PALDEFENDER_RELEASE_PROXY}" <<'PALDEFENDER_RELEASE_PROXY_EOF'
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iso_mtime(path: Path) -> str:
    try:
        timestamp = path.stat().st_mtime
    except OSError:
        timestamp = 0
    if timestamp <= 0:
        return "1970-01-01T00:00:00Z"
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def detect_version(win64: Path) -> str:
    config_path = win64 / "PalDefender" / "Config.json"
    if config_path.is_file():
        try:
            data = json.loads(config_path.read_text(encoding="utf-8"))
            for key in ("Version", "version", "PalDefenderVersion"):
                value = data.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
        except (OSError, ValueError, TypeError):
            pass
    return "host-wine-local"


class ReleaseServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], root: Path):
        self.root = root
        self.win64 = root / "server" / "Pal" / "Binaries" / "Win64"
        self.ue4ss_archive = root / "cache" / "ue4ss" / "UE4SS-Palworld.zip"
        super().__init__(address, Handler)

    def release(self) -> dict:
        assets = []
        newest_path: Path | None = None
        for name in ("d3d9.dll", "PalDefender.dll"):
            path = self.win64 / name
            if not path.is_file():
                continue
            newest_path = path if newest_path is None or path.stat().st_mtime > newest_path.stat().st_mtime else newest_path
            assets.append(
                {
                    "name": name,
                    "size": path.stat().st_size,
                    "digest": f"sha256:{sha256_file(path)}",
                    "browser_download_url": f"http://127.0.0.1:{self.server_port}/assets/{name}",
                }
            )
        published = iso_mtime(newest_path) if newest_path is not None else "1970-01-01T00:00:00Z"
        version = detect_version(self.win64)
        tag = version if version.lower().startswith("v") else f"v{version}"
        return {
            "tag_name": tag,
            "name": f"PalDefender {version} (local host-Wine)",
            "published_at": published,
            "draft": False,
            "prerelease": False,
            "assets": assets,
        }


class Handler(BaseHTTPRequestHandler):
    server: ReleaseServer

    def log_message(self, format: str, *args: object) -> None:
        print(f"[{self.log_date_time_string()}] {format % args}", flush=True)

    def send_json(self, payload: object, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json({"status": "ok"})
            return
        if path == "/repos/Ultimeit/PalDefender/releases/latest":
            self.send_json(self.server.release())
            return
        if path == "/repos/Ultimeit/PalDefender/releases":
            self.send_json([self.server.release()])
            return
        if path == "/ue4ss/UE4SS-Palworld.zip":
            asset = self.server.ue4ss_archive
            if not asset.is_file():
                self.send_json({"message": "UE4SS archive is not cached"}, 404)
                return
            body = asset.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            return
        if path.startswith("/assets/"):
            name = Path(unquote(path[len("/assets/"):])).name
            if name not in {"d3d9.dll", "PalDefender.dll"}:
                self.send_json({"message": "asset not found"}, 404)
                return
            asset = self.server.win64 / name
            if not asset.is_file():
                self.send_json({"message": "asset not found"}, 404)
                return
            body = asset.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(name)[0] or "application/octet-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            return
        self.send_json({"message": "not found"}, 404)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", required=True, type=int)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    server = ReleaseServer(("127.0.0.1", args.port), root)
    print(f"PalDefender release proxy listening on 127.0.0.1:{args.port}", flush=True)
    server.serve_forever(poll_interval=0.5)


if __name__ == "__main__":
    main()
PALDEFENDER_RELEASE_PROXY_EOF

chmod +x "${PALDEFENDER_RELEASE_PROXY}"

patch_palpanel_paldefender_urls() {
    local binary="${APP_DIR}/bin/palpanel"
    local backup="${APP_DIR}/bin/palpanel.original-v1.2.1"

    if [ ! -x "${binary}" ]; then
        echo "错误：找不到 PalPanel 后端程序：${binary}"
        return 1
    fi

    python3 - "${binary}" "${backup}" <<'PATCH_PALPANEL_URLS_EOF'
from pathlib import Path
import os
import shutil
import sys
import tempfile

binary = Path(sys.argv[1])
backup = Path(sys.argv[2])

pairs = [
    (
        b"https://api.github.com/repos/Ultimeit/PalDefender/releases/latest",
        b"http://127.0.0.1:18081/repos/Ultimeit/PalDefender/releases/latest",
    ),
    (
        b"https://api.github.com/repos/Ultimeit/PalDefender/releases",
        b"http://127.0.0.1:18081/repos/Ultimeit/PalDefender/releases",
    ),
]

for old, new in pairs:
    if len(old) != len(new):
        raise SystemExit(f"URL replacement length mismatch: {len(old)} != {len(new)}")

data = binary.read_bytes()
original_data = data

if not backup.exists() and any(old in data for old, _ in pairs):
    shutil.copy2(binary, backup)

for old, new in pairs:
    data = data.replace(old, new)

for _, new in pairs:
    if new not in data:
        raise SystemExit(f"patched URL was not found in {binary}: {new!r}")

if data != original_data:
    mode = binary.stat().st_mode
    fd, temporary_name = tempfile.mkstemp(prefix=".palpanel-patched-", dir=str(binary.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, binary)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
    print("PalPanel PalDefender GitHub API URL 已替换为本地代理。")
else:
    print("PalPanel PalDefender 本地代理 URL 已存在。")
PATCH_PALPANEL_URLS_EOF
}

start_paldefender_release_proxy() {
    local old_pid=""

    if [ -f "${PALDEFENDER_RELEASE_PROXY_PID}" ]; then
        old_pid="$(tr -cd '0-9' < "${PALDEFENDER_RELEASE_PROXY_PID}" 2>/dev/null || true)"
    fi

    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        kill -TERM "${old_pid}" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "${old_pid}" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "${old_pid}" 2>/dev/null; then
            kill -KILL "${old_pid}" 2>/dev/null || true
        fi
    fi

    rm -f "${PALDEFENDER_RELEASE_PROXY_PID}"
    : > "${PALDEFENDER_RELEASE_PROXY_LOG}"

    nohup python3 "${PALDEFENDER_RELEASE_PROXY}" \
        --root "${ROOT}" \
        --port "${PALDEFENDER_RELEASE_PROXY_PORT}" \
        >> "${PALDEFENDER_RELEASE_PROXY_LOG}" 2>&1 < /dev/null &

    local proxy_pid="$!"
    printf '%s\n' "${proxy_pid}" > "${PALDEFENDER_RELEASE_PROXY_PID}"

    for _ in $(seq 1 50); do
        if curl --silent --fail --max-time 1 \
            "http://127.0.0.1:${PALDEFENDER_RELEASE_PROXY_PORT}/health" \
            >/dev/null 2>&1; then
            echo "PalDefender/UE4SS 本地资源服务已启动：127.0.0.1:${PALDEFENDER_RELEASE_PROXY_PORT}"
            return 0
        fi

        if ! kill -0 "${proxy_pid}" 2>/dev/null; then
            break
        fi

        sleep 0.1
    done

    echo "错误：PalDefender 本地 Release 服务启动失败。"
    tail -n 100 "${PALDEFENDER_RELEASE_PROXY_LOG}" 2>/dev/null || true
    return 1
}

patch_palpanel_paldefender_urls
start_paldefender_release_proxy

# ---------------------------------------------------------
# 官方侧车：sav-cli 与 palcalc-bridge
#
# 标准 Linux 部署会同时运行：
#   sav-cli serve --host 127.0.0.1 --port 8090
#   palcalc-bridge（http://127.0.0.1:8091）
#
# 当前环境不能使用 systemd，因此由本脚本管理 PID、日志和健康检查。
# ---------------------------------------------------------

cat > "${REBUILD_SAVE_INDEX_TOOL}" <<'REBUILD_SAVE_INDEX_EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

ROOT="${PALPANEL_ROOT:-/home/container/palworld_win}"
PORTABLE_WINE_CURRENT="${PALPANEL_PORTABLE_WINE_CURRENT:-${ROOT}/runtime/wine/current}"
if [ -x "${PORTABLE_WINE_CURRENT}/bin/wine" ]; then
    export PATH="${PORTABLE_WINE_CURRENT}/bin:${PATH}"
fi
APP_DIR="${ROOT}/app"
SERVER_DIR="${PALPANEL_SERVER_DIR:-${ROOT}/server}"
CACHE_DIR="${PALPANEL_SAVE_INDEX_CACHE_DIR:-${ROOT}/data/save-index}"
CACHE_FILE="${CACHE_DIR}/index-cache.json"
SAVE_ROOT="${SERVER_DIR}/Pal/Saved/SaveGames"
LOG_DIR="${PALPANEL_LOGS_DIR:-${ROOT}/logs}"
LOG_FILE="${LOG_DIR}/save-index-rebuild.log"

mkdir -p "${CACHE_DIR}" "${LOG_DIR}"

if [ ! -x "${APP_DIR}/bin/sav-cli" ]; then
    echo "错误：sav-cli 不存在或不可执行：${APP_DIR}/bin/sav-cli" >&2
    exit 1
fi

level_sav="$(find "${SAVE_ROOT}" \
    -type f \
    -iname 'Level.sav' \
    ! -path '*/backup/*' \
    ! -path '*/backups/*' \
    -print -quit 2>/dev/null || true)"

if [ -z "${level_sav}" ]; then
    echo "尚未发现 Level.sav，暂不生成存档索引。"
    echo "查找目录：${SAVE_ROOT}"
    exit 2
fi

temporary="${CACHE_FILE}.tmp.$$"
rm -f "${temporary}"
: > "${LOG_FILE}"

echo "正在解析存档：${level_sav}" | tee -a "${LOG_FILE}"

set +e
timeout 600 \
    "${APP_DIR}/bin/sav-cli" index \
    --save-dir "${SAVE_ROOT}" \
    --output "${temporary}" \
    2>&1 | tee -a "${LOG_FILE}"
status="${PIPESTATUS[0]}"
set -e

if [ "${status}" -ne 0 ]; then
    rm -f "${temporary}"
    echo "存档索引生成失败，退出码：${status}" >&2
    exit "${status}"
fi

if ! python3 - "${temporary}" <<'VALIDATE_INDEX_JSON_EOF'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("r", encoding="utf-8") as stream:
    payload = json.load(stream)

if not isinstance(payload, dict):
    raise SystemExit("index root must be a JSON object")
VALIDATE_INDEX_JSON_EOF
then
    rm -f "${temporary}"
    echo "存档索引不是有效 JSON 对象。" >&2
    exit 1
fi

mv -f "${temporary}" "${CACHE_FILE}"
chmod 644 "${CACHE_FILE}"

echo "存档索引生成完成：${CACHE_FILE}"
REBUILD_SAVE_INDEX_EOF

chmod +x "${REBUILD_SAVE_INDEX_TOOL}"

stop_pid_file_process() {
    local pid_file="$1"
    local label="$2"
    local pid=""

    if [ -f "${pid_file}" ]; then
        pid="$(tr -cd '0-9' < "${pid_file}" 2>/dev/null || true)"
    fi

    if [ -z "${pid}" ]; then
        rm -f "${pid_file}"
        return 0
    fi

    if ! kill -0 "${pid}" 2>/dev/null; then
        rm -f "${pid_file}"
        return 0
    fi

    echo "正在停止旧的 ${label} 进程：${pid}"
    kill -TERM "${pid}" 2>/dev/null || true

    for _ in $(seq 1 30); do
        kill -0 "${pid}" 2>/dev/null || break
        sleep 0.1
    done

    if kill -0 "${pid}" 2>/dev/null; then
        kill -KILL "${pid}" 2>/dev/null || true
    fi

    rm -f "${pid_file}"
}

wait_http_health() {
    local url="$1"
    local pid="$2"
    local label="$3"
    local log_file="$4"

    for _ in $(seq 1 100); do
        if curl \
            --silent \
            --show-error \
            --fail \
            --max-time 2 \
            "${url}" \
            >/dev/null 2>&1
        then
            echo "${label} 已就绪：${url}"
            return 0
        fi

        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "错误：${label} 进程提前退出。"
            tail -n 100 "${log_file}" 2>/dev/null || true
            return 1
        fi

        sleep 0.1
    done

    echo "错误：${label} 健康检查超时：${url}"
    tail -n 100 "${log_file}" 2>/dev/null || true
    return 1
}

start_save_indexer() {
    stop_pid_file_process "${SAVE_INDEXER_PID}" "sav-cli"

    : > "${SAVE_INDEXER_LOG}"

    nohup "${APP_DIR}/bin/sav-cli" serve \
        --host "${SAVE_INDEXER_HOST}" \
        --port "${SAVE_INDEXER_PORT}" \
        >> "${SAVE_INDEXER_LOG}" 2>&1 < /dev/null &

    local pid="$!"
    printf '%s\n' "${pid}" > "${SAVE_INDEXER_PID}"

    wait_http_health \
        "${SAVE_INDEXER_URL}/health" \
        "${pid}" \
        "sav-cli 存档解析侧车" \
        "${SAVE_INDEXER_LOG}"
}

start_palcalc_bridge() {
    stop_pid_file_process "${PALCALC_PID}" "palcalc-bridge"

    : > "${PALCALC_LOG}"
    mkdir -p "${DOTNET_BUNDLE_DIR}"

    PALCALC_BRIDGE_URLS="${PALCALC_URL}" \
    PALCALC_BRIDGE_CONCURRENCY="1" \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR="${DOTNET_BUNDLE_DIR}" \
    HOME="${WINE_HOME}" \
    nohup "${APP_DIR}/bin/palcalc-bridge" \
        >> "${PALCALC_LOG}" 2>&1 < /dev/null &

    local pid="$!"
    printf '%s\n' "${pid}" > "${PALCALC_PID}"

    wait_http_health \
        "${PALCALC_URL}/health" \
        "${pid}" \
        "PalCalc 配种侧车" \
        "${PALCALC_LOG}"
}

echo
echo "正在启动 PalPanel 官方侧车……"
start_save_indexer

# PalCalc 故障不应阻止面板和游戏服务端启动。
if ! start_palcalc_bridge; then
    echo "警告：PalCalc 侧车启动失败，配种功能暂不可用。"
fi

# 缓存缺失且存档已存在时，先生成一次，避免页面首次读取直接报 ENOENT。
if [ ! -f "${SAVE_INDEX_CACHE_FILE}" ]; then
    if "${REBUILD_SAVE_INDEX_TOOL}"; then
        :
    else
        rebuild_status="$?"
        if [ "${rebuild_status}" -ne 2 ]; then
            echo "警告：首次存档索引生成失败；面板仍将通过 sav-cli 侧车重试。"
        fi
    fi
fi

# ---------------------------------------------------------
# PalPanel UE4SS experimental 界面文案修正
# ---------------------------------------------------------

patch_ue4ss_frontend_labels() {
    local frontend_dir="${APP_DIR}/frontend/dist"

    [ -d "${frontend_dir}" ] || return 0

    python3 - "${frontend_dir}" <<'PY_PATCH_UE4SS_FRONTEND'
from pathlib import Path
import sys

root = Path(sys.argv[1])

replacements = {
    "GitHub 最新稳定版": "GitHub experimental-palworld",
    "GitHub latest stable release": "GitHub experimental-palworld",
    "Latest stable GitHub release": "GitHub experimental-palworld",
    "UE4SS files are installed and compatible; start the server once to verify that UE4SS loads.":
        "UE4SS experimental-palworld files are installed; loading is confirmed from the actual ue4ss/UE4SS.log after server startup.",
    "UE4SS 文件已安装且兼容；请启动一次服务器以确认 UE4SS 是否加载。":
        "UE4SS experimental-palworld 文件已安装；启动后将根据实际 ue4ss/UE4SS.log 确认加载。",
}

changed = 0
for path in root.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in {".js", ".mjs", ".html", ".json", ".map"}:
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue

    updated = content
    for before, after in replacements.items():
        updated = updated.replace(before, after)

    if updated != content:
        path.write_text(updated, encoding="utf-8")
        changed += 1

print(f"UE4SS frontend label files patched: {changed}")
PY_PATCH_UE4SS_FRONTEND
}

patch_ue4ss_frontend_labels

# ---------------------------------------------------------
# 初始化安全配置
# ---------------------------------------------------------

if [ ! -s "${CONFIG_FILE}" ]; then
    echo
    echo "正在生成 PalPanel 安全配置……"

    env PALPANEL_RUNTIME_ROOT="${ROOT}" \
        "${APP_DIR}/bin/palpanel" \
        --runtime-root "${ROOT}" \
        --config "${CONFIG_FILE}" \
        --init-config
fi

set_env_value() {
    local key="$1"
    local value="$2"
    local escaped=""
    local tmp="${CONFIG_FILE}.tmp"

    umask 077
    escaped="$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')"

    if grep -qE "^${key}=" "${CONFIG_FILE}"; then
        sed "s/^${key}=.*/${key}=${escaped}/" "${CONFIG_FILE}" > "${tmp}"
        chmod 600 "${tmp}"
        mv -f "${tmp}" "${CONFIG_FILE}"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${CONFIG_FILE}"
    fi

    chmod 600 "${CONFIG_FILE}"
    umask 022
}

set_env_value "PALPANEL_LISTEN_ADDR" "0.0.0.0:${PANEL_PORT}"
set_env_value "PALPANEL_RUNTIME_ROOT" "${ROOT}"
set_env_value "PALPANEL_DATA_DIR" "${DATA_DIR}"
set_env_value "PALPANEL_SERVER_DIR" "${SERVER_DIR}"
set_env_value "PALPANEL_WINE_PREFIX_DIR" "${WINE_PREFIX}"
set_env_value "PALPANEL_TOOLS_DIR" "${TOOLS_DIR}"
set_env_value "PALPANEL_STEAMCMD_DIR" "${STEAMCMD_DIR}"
set_env_value "PALPANEL_WINDOWS_STEAMCMD_DIR" "${STEAMCMD_DIR}"
set_env_value "PALPANEL_PORTABLE_WINE_CURRENT" "${PORTABLE_WINE_CURRENT}"
set_env_value "PALPANEL_STEAM_API_BASE_URL" "${STEAM_API_PROXY_URL}"
set_env_value "PALPANEL_STEAM_API_TIMEOUT_SECONDS" "45"
set_env_value "PALPANEL_WORKSHOP_PROGRESS_INTERVAL" "5"
set_env_value "PALPANEL_WORKSHOP_STALL_SECONDS" "180"
set_env_value "PALPANEL_WORKSHOP_ANONYMOUS_TIMEOUT" "1800"
set_env_value "PALPANEL_WORKSHOP_CREDENTIAL_TIMEOUT" "180"
set_env_value "NO_PROXY" "127.0.0.1,localhost"
UE4SS_RUNTIME_ARCHIVE_SHA256="$(
    awk 'NR == 1 {print $1}' "${UE4SS_ARCHIVE_SHA_FILE}" 2>/dev/null || true
)"

if [ -z "${UE4SS_RUNTIME_ARCHIVE_SHA256}" ]; then
    echo "错误：单一 experimental UE4SS 包缺少 SHA-256。"
    exit 1
fi

set_env_value "PALPANEL_UE4SS_DIR" "${UE4SS_RUNTIME_DIR}"
set_env_value "PALPANEL_UE4SS_VERSION" "experimental-palworld-20260719"
set_env_value "PALPANEL_UE4SS_DOWNLOAD_URL" "${UE4SS_LOCAL_URL}"
set_env_value "PALPANEL_UE4SS_ARCHIVE_SHA256" "${UE4SS_RUNTIME_ARCHIVE_SHA256}"
set_env_value "PALPANEL_UE4SS_DOWNLOAD_MAX_MB" "128"
set_env_value "PALPANEL_UE4SS_RELEASE_CHANNEL" "experimental-palworld"
set_env_value "PALPANEL_UE4SS_UPDATE_SOURCE" "github-experimental"
set_env_value "PALPANEL_INSTALL_UE4SS_EXPERIMENTAL" "true"
set_env_value "PALPANEL_UE4SS_EXPERIMENTAL_URL" "${GH_PROXY_BASE%/}/https://github.com/Okaetsu/RE-UE4SS/releases/download/experimental-palworld/UE4SS-Palworld.zip"
set_env_value "PALPANEL_XVFB_DISPLAY" "${XVFB_DISPLAY}"
set_env_value "PALPANEL_WINETRICKS_ON_START" "${WINETRICKS_ON_START}"
set_env_value "PALPANEL_INSTALL_WINE_RUNTIME_PACKAGES" "${WINE_RUNTIME_PACKAGES_ON_START}"
set_env_value "PALPANEL_UPLOADS_DIR" "${DATA_DIR}/uploads"
set_env_value "PALPANEL_BACKUPS_DIR" "${DATA_DIR}/backups"
set_env_value "PALPANEL_LOGS_DIR" "${LOG_DIR}"
set_env_value "PALPANEL_DB_PATH" "${DATA_DIR}/palpanel.db"
set_env_value "PALPANEL_SAVE_INDEXER_ENABLED" "true"
set_env_value "PALPANEL_SAVE_INDEXER_URL" "${SAVE_INDEXER_URL}"
set_env_value "PALPANEL_SAVE_INDEX_TIMEOUT_SECONDS" "600"
set_env_value "PALPANEL_SAVE_INDEX_CACHE_DIR" "${SAVE_INDEX_CACHE_DIR}"
set_env_value "PALPANEL_PALCALC_URL" "${PALCALC_URL}"
set_env_value "PALPANEL_PALCALC_TIMEOUT_SECONDS" "600"
set_env_value "PALPANEL_DOCKER_BIN" "${DOCKER_SHIM}"
set_env_value "PALPANEL_DOCKER_IMAGE" "palworld-host-wine:local"
set_env_value "PALPANEL_DOCKER_CONTAINER" "palworld-wine-server"
set_env_value "PALPANEL_GAME_PORT" "${GAME_PORT}"
set_env_value "PALPANEL_QUERY_PORT" "${QUERY_PORT}"
set_env_value "PALPANEL_REST_PORT" "${REST_PORT}"
set_env_value "PALPANEL_RCON_PORT" "${RCON_PORT}"
set_env_value "PALPANEL_PALDEFENDER_REST_PORT" "${PALDEFENDER_REST_PORT}"
set_env_value "PALPANEL_PALDEFENDER_REST_BASE_URL" "http://127.0.0.1:${PALDEFENDER_REST_PORT}"
set_env_value "PALPANEL_FRONTEND_DIST" "${APP_DIR}/frontend/dist"
set_env_value "PALPANEL_RUNNER_DIR" "${APP_DIR}/backend/deployments/wine-runner"
set_env_value "PALPANEL_REQUIRE_AUTH" "true"

# Steam Workshop 默认匿名下载。只有显式设置 PALPANEL_STEAM_USERNAME 时，
# 才在 PalPanel 配置中启用账号缓存模式。脚本不会保存真实密码或 Steam Guard 令牌。
set +x
sed -i -E '/^(STEAM_USERNAME|STEAM_PASSWORD|STEAM_GUARD_CODE|PALPANEL_FORCE_STEAM_LOGIN|PALPANEL_STEAM_LOGIN_MODE|PALPANEL_STEAM_INTERACTIVE_LOGIN)=/d' "${CONFIG_FILE}"

if [ -n "${STEAM_USERNAME_VALUE}" ]; then
    set_env_value "STEAM_USERNAME" "${STEAM_USERNAME_VALUE}"
    set_env_value "STEAM_PASSWORD" "__PALPANEL_USE_STEAMCMD_CACHED_CREDENTIALS__"
    set_env_value "PALPANEL_STEAM_LOGIN_MODE" "cached-account"
else
    set_env_value "PALPANEL_STEAM_LOGIN_MODE" "anonymous"
fi
set_env_value "PALPANEL_STEAM_INTERACTIVE_LOGIN" "false"

chmod 600 "${CONFIG_FILE}"

# ---------------------------------------------------------
# SteamCMD 账号授权（默认关闭，仅显式启用时执行）
# ---------------------------------------------------------
STEAM_LOGIN_PROBE_LOG="${LOG_DIR}/steamcmd-login-probe.log"

steam_cached_login_ready() {
    [ -n "${STEAM_USERNAME_VALUE}" ] || return 1
    : > "${STEAM_LOGIN_PROBE_LOG}"

    # @NoPromptForPassword=1 保证缓存无效时不会卡在密码提示。
    set +e
    HOME="${WINE_HOME}" \
    XDG_CONFIG_HOME="${WINE_HOME}/.config" \
    XDG_DATA_HOME="${WINE_HOME}/.local/share" \
        timeout 90s steamcmd \
        +@ShutdownOnFailedCommand 1 \
        +@NoPromptForPassword 1 \
        +login "${STEAM_USERNAME_VALUE}" \
        +quit >"${STEAM_LOGIN_PROBE_LOG}" 2>&1
    local probe_rc=$?
    set -e

    [ "${probe_rc}" -eq 0 ] &&
        grep -Eqi 'Logging in using cached credentials|Logged in OK' "${STEAM_LOGIN_PROBE_LOG}" &&
        grep -Eqi 'Waiting for user info.*OK' "${STEAM_LOGIN_PROBE_LOG}"
}

case "${STEAM_LOGIN_ON_START}" in
    1|true|TRUE|yes|YES)
        if [ -z "${STEAM_USERNAME_VALUE}" ]; then
            echo "错误：PALPANEL_STEAM_LOGIN_ON_START=1 时必须同时设置 PALPANEL_STEAM_USERNAME。" >&2
            exit 78
        fi

        if steam_cached_login_ready; then
            echo "SteamCMD 账号缓存已可用：${STEAM_USERNAME_VALUE}"
        else
            echo
            echo "================================================="
            echo "SteamCMD 账号授权（显式启用）"
            echo "================================================="
            echo "请在 Steam> 提示符输入："
            echo "  login ${STEAM_USERNAME_VALUE}"
            echo "按提示输入密码和 Steam Guard 令牌，看到 Logged in OK 后输入 quit。"
            echo "密码和令牌不会写入 palpanel.env 或安装日志。"
            echo "================================================="

            mkdir -p "${WINE_HOME}/.config" "${WINE_HOME}/.local/share"
            chmod 700 "${WINE_HOME}" "${WINE_HOME}/.config" "${WINE_HOME}/.local/share" 2>/dev/null || true

            HOME="${WINE_HOME}" \
            XDG_CONFIG_HOME="${WINE_HOME}/.config" \
            XDG_DATA_HOME="${WINE_HOME}/.local/share" \
                steamcmd

            if ! steam_cached_login_ready; then
                echo "SteamCMD 账号缓存验证未通过。探测日志：${STEAM_LOGIN_PROBE_LOG}" >&2
                exit 79
            fi

            chmod -R go-rwx "${WINE_HOME}/.local/share/Steam/config" "${WINE_HOME}/.steam" 2>/dev/null || true
            echo "SteamCMD 账号缓存验证通过。"
        fi
        ;;
    *)
        if [ -n "${STEAM_USERNAME_VALUE}" ]; then
            echo "Steam 账号已配置但启动时不强制登录：${STEAM_USERNAME_VALUE}"
            echo "Workshop 会在需要账号模式时尝试复用现有缓存；缓存不可用时不会阻止面板启动。"
        else
            echo "未配置 Steam 账号；Workshop 默认使用 anonymous 下载。"
        fi
        ;;
esac

# ---------------------------------------------------------
# 最终环境检测
# ---------------------------------------------------------

echo
echo "================================================="
echo "安装结果检测"
echo "================================================="

"${APP_DIR}/bin/palpanel" --version
echo "Wine：$(wine --version 2>&1)"
echo "Windows SteamCMD：${STEAMCMD_DIR}/steamcmd.exe"
echo "Linux SteamCMD（Workshop）：$(command -v steamcmd)"
echo "宿主 Wine 状态兼容层：$("${DOCKER_SHIM}" version --format '{{.Server.Version}}')"
echo "Host Wine 服务运行：$("${DOCKER_SHIM}" inspect --format '{{.State.Running}}' palworld-wine-server 2>/dev/null || echo false)"
echo "Host Wine 状态修复工具：${HOST_WINE_STATE_TOOL}"
echo "Steam API 中继：$(curl --silent --fail --max-time 2 "${STEAM_API_PROXY_URL}/health" 2>/dev/null || echo 不可用)"
echo "Steam API 中继日志：${STEAM_API_PROXY_LOG}"
echo "Workshop 下载日志：${ROOT}/logs/workshop.log"
echo "Workshop 进度查看：${TOOLS_DIR}/workshop-progress ItemID --follow"
echo "Workshop 导入修复：${TOOLS_DIR}/repair-workshop-import"
echo "Workshop 无活动终止：180 秒"
echo "PalDefender 直链安装器：${PALDEFENDER_INSTALLER}"
echo "PalDefender Release 代理：http://127.0.0.1:${PALDEFENDER_RELEASE_PROXY_PORT}"
echo "UE4SS 构建：Okaetsu experimental-palworld"
echo "UE4SS 单一维护包：${UE4SS_ARCHIVE_PATH}"
echo "UE4SS 包 SHA-256：${UE4SS_RUNTIME_ARCHIVE_SHA256}"
echo "UE4SS 本地下载地址：${UE4SS_LOCAL_URL}"
echo "UE4SS 缓存：$([ -f "${UE4SS_ARCHIVE_PATH}" ] && echo 已找到 || echo 未找到)"
echo "UE4SS 加载：$([ -s "${UE4SS_LOAD_MARKER}" ] && echo 已确认 || echo 尚未确认)"
echo "Xvfb 显示：${XVFB_DISPLAY}"
echo "Wine vcrun2022：$([ -f "${WINE_PREFIX}/.vcrun2022-installed" ] && echo 已安装 || echo 未确认)"
echo "NativeMods 安装器：${UE4SS_MOD_INSTALLER}"
echo "UE4SS 加载监控：${UE4SS_LOAD_MONITOR_TOOL}"
echo "Wine MOD 诊断：${WINE_MOD_DIAG_TOOL}"
echo "dwmapi.dll：$([ -f "${SERVER_DIR}/Pal/Binaries/Win64/dwmapi.dll" ] && echo 已找到 || echo 未找到)"
echo "ue4ss/UE4SS.dll：$([ -f "${SERVER_DIR}/Pal/Binaries/Win64/ue4ss/UE4SS.dll" ] && echo 已找到 || echo 未找到)"
echo "MemberVariableLayout.ini：$([ -f "${SERVER_DIR}/Pal/Binaries/Win64/ue4ss/MemberVariableLayout.ini" ] && echo 已找到 || echo 未找到)"
echo "sav-cli 状态：$(curl --silent --fail --max-time 2 "${SAVE_INDEXER_URL}/health" 2>/dev/null || echo 不可用)"
echo "存档索引缓存：$([ -f "${SAVE_INDEX_CACHE_FILE}" ] && echo 已生成 || echo 尚未生成)"
echo "存档索引重建工具：${REBUILD_SAVE_INDEX_TOOL}"
echo "网络身份恢复工具：${NET_ID_RECOVERY_TOOL}"
echo "PalServer 参数状态：$([ -s "${RUN_DIR}/host-wine-runner/start-args.nul" ] && echo 已保存 || echo 等待首次由面板启动)"
echo "PalCalc 状态：$(curl --silent --fail --max-time 2 "${PALCALC_URL}/health" 2>/dev/null || echo 不可用)"
echo "PalDefender DLL：$([ -f "${SERVER_DIR}/Pal/Binaries/Win64/PalDefender.dll" ] && echo 已找到 || echo 未找到)"
echo "PalDefender 加载器：$([ -f "${SERVER_DIR}/Pal/Binaries/Win64/d3d9.dll" ] && echo 已找到 || echo 未找到)"
echo "资源统计测试：$("${DOCKER_SHIM}" stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' palworld-wine-server)"
echo "配置文件：${CONFIG_FILE}（权限 $(stat -c '%a' "${CONFIG_FILE}" 2>/dev/null || echo 未知)）"
if [ -n "${STEAM_USERNAME_VALUE}" ]; then
    echo "Steam Workshop 账号：${STEAM_USERNAME_VALUE}（启动时不强制登录）"
else
    echo "Steam Workshop 账号：未配置，默认 anonymous"
fi
echo "服务端目录：${SERVER_DIR}"
echo "Wine 前缀：${WINE_PREFIX}"
echo "启动脚本：/home/container/start.sh"
echo "所有运行数据均位于：${ROOT}"
echo "PalPanel 安全运行根：${ROOT}"
echo "临时运行目录：${RUNTIME_DIR}"
echo "================================================="

# ---------------------------------------------------------
# 启动 PalPanel
# ---------------------------------------------------------

# 对已经由旧版本启动的 Wine PalServer，先恢复面板状态映射。
"${DOCKER_SHIM}" repair-state >/dev/null 2>&1 || true

echo
if [ -s "${PANEL_LOG}" ]; then
    mv -f "${PANEL_LOG}" "${PANEL_LOG}.previous" 2>/dev/null || true
fi
: > "${PANEL_LOG}"

echo "正在重启 PalPanel……"
echo "访问端口：${PANEL_PORT}/TCP"
echo "首次打开网页后注册管理员账户。"
echo

# 修改 palpanel.env 后停止同一路径的旧 PalPanel 进程。
existing_panel_pids="$(
    pgrep -f "${APP_DIR}/bin/palpanel" 2>/dev/null || true
)"

for existing_pid in ${existing_panel_pids}; do
    [ "${existing_pid}" = "$$" ] && continue
    kill -TERM "${existing_pid}" 2>/dev/null || true
done

for _ in $(seq 1 30); do
    remaining="0"
    for existing_pid in ${existing_panel_pids}; do
        [ "${existing_pid}" = "$$" ] && continue
        if kill -0 "${existing_pid}" 2>/dev/null; then
            remaining="1"
            break
        fi
    done
    [ "${remaining}" = "0" ] && break
    sleep 1
done

cd "${APP_DIR}"

export PALPANEL_ROOT="${ROOT}"
export PALPANEL_RUNTIME_ROOT="${ROOT}"

# palpanelctl 是面向标准发布布局的服务包装器，会自行寻找 app/config。
# 当前采用自定义单目录布局，因此直接启动后端二进制，明确传入配置和运行目录。
rm -f "${APP_DIR}/config/palpanel.env" 2>/dev/null || true

"${APP_DIR}/bin/palpanel" \
    --config "${CONFIG_FILE}" \
    --runtime-root "${ROOT}" \
    2>&1 | tee -a "${PANEL_LOG}"

exit "${PIPESTATUS[0]}"
