#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="dwmac-phytium"
PKG_VER="1.0.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
DEBS_DIR="${SCRIPT_DIR}/debs"
if [ ! -d "${DEBS_DIR}" ] && [ -d "${SCRIPT_DIR}/../debs" ]; then
    DEBS_DIR="${SCRIPT_DIR}/../debs"
fi
PREBUILT_DIR="${SCRIPT_DIR}/prebuilt"
KVER="$(uname -r)"
CONFIGURE_DHCP=1

for arg in "$@"; do
    case "$arg" in
        --no-dhcp)
            CONFIGURE_DHCP=0
            ;;
        -h|--help)
            echo "用法: sudo $0 [--no-dhcp]"
            exit 0
            ;;
        *)
            echo "未知参数: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 请使用 root 权限运行: sudo $0" >&2
    exit 1
fi

echo "=== 飞腾 D2000 板载网卡驱动离线安装程序 ==="
echo "[INFO] 当前内核版本: ${KVER}"

install_offline_debs() {
    if [ ! -d "${DEBS_DIR}" ] || ! ls "${DEBS_DIR}"/*.deb >/dev/null 2>&1; then
        echo "[WARN] 未找到离线依赖目录 ${DEBS_DIR}，跳过离线依赖安装"
        return 0
    fi

    echo "[INFO] 正在从 ${DEBS_DIR} 离线安装所需依赖..."
    # 仅安装缺失或同内核版本的 .deb，避免误装不匹配当前内核的 headers
    local to_install=()
    for deb in "${DEBS_DIR}"/*.deb; do
        local base
        base="$(basename "$deb")"
        if [[ "$base" == linux-headers-arm64_* ]]; then
            local kver_short="${KVER%%+*}"
            if [[ "$base" != "linux-headers-arm64_${kver_short}"* ]]; then
                echo "[INFO] 跳过不匹配当前内核(${KVER})的头文件元包: ${base}"
                continue
            fi
        elif [[ "$base" == linux-headers-* ]] && [[ "$base" != *"-common_"* ]]; then
            if [[ "$base" != "linux-headers-${KVER}_"* ]]; then
                echo "[INFO] 跳过不匹配当前内核(${KVER})的头文件包: ${base}"
                continue
            fi
        fi
        if [[ "$base" == linux-kbuild-* ]]; then
            local kver_short="${KVER%%+*}"
            if [[ "$base" != "linux-kbuild-${kver_short}"* ]]; then
                echo "[INFO] 跳过不匹配当前内核的 kbuild 包: ${base}"
                continue
            fi
        fi
        to_install+=("$deb")
    done

    if [ "${#to_install[@]}" -gt 0 ]; then
        if ! dpkg -i --skip-same-version "${to_install[@]}"; then
            echo "[WARN] dpkg 安装出现部分依赖问题，尝试使用 dpkg --configure -a 修复..."
            if ! dpkg --configure -a; then
                echo "[WARN] 部分离线依赖未能完成配置，将尝试回退到预编译模块（若有）..." >&2
            fi
        fi
    fi
}

need_deps=0
if ! command -v dkms >/dev/null 2>&1; then
    need_deps=1
fi
if [ ! -d "/lib/modules/${KVER}/build" ]; then
    need_deps=1
fi
if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
    need_deps=1
fi

if [ "$need_deps" -eq 1 ]; then
    install_offline_debs
else
    echo "[INFO] 编译环境与 DKMS 依赖已满足，无需安装离线 .deb"
fi

# 清理旧的手动安装模块，避免与 DKMS 冲突
rm -f "/lib/modules/${KVER}/updates/dwmac-phytium.ko" \
      "/lib/modules/${KVER}/updates/dwmac-phytium.ko.xz" \
      "/lib/modules/${KVER}/extra/dwmac-phytium.ko" \
      "/lib/modules/${KVER}/extra/dwmac-phytium.ko.xz"

INSTALLED_MODE=""

if command -v dkms >/dev/null 2>&1 && [ -d "/lib/modules/${KVER}/build" ] && command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    echo "[INFO] 使用 DKMS 编译并安装 ${PKG_NAME}/${PKG_VER}..."
    dkms remove -m "${PKG_NAME}" -v "${PKG_VER}" --all >/dev/null 2>&1 || true
    rm -rf "/usr/src/${PKG_NAME}-${PKG_VER}"
    mkdir -p "/usr/src/${PKG_NAME}-${PKG_VER}"
    cp -a "${SRC_DIR}/." "/usr/src/${PKG_NAME}-${PKG_VER}/"

    dkms add -m "${PKG_NAME}" -v "${PKG_VER}"
    dkms build -m "${PKG_NAME}" -v "${PKG_VER}"
    dkms install -m "${PKG_NAME}" -v "${PKG_VER}"
    INSTALLED_MODE="dkms"
elif [ -d "/lib/modules/${KVER}/build" ] && command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    echo "[INFO] 使用本地内核头文件直接编译安装..."
    make -C "${SRC_DIR}" clean || true
    make -C "${SRC_DIR}" KVER="${KVER}"
    make -C "/lib/modules/${KVER}/build" M="${SRC_DIR}" modules_install
    INSTALLED_MODE="native"
elif [ -f "${PREBUILT_DIR}/${KVER}/dwmac-phytium.ko.xz" ]; then
    echo "[INFO] 检测到匹配的预编译模块，直接安装 prebuilt/${KVER}/dwmac-phytium.ko.xz..."
    mkdir -p "/lib/modules/${KVER}/updates"
    cp -f "${PREBUILT_DIR}/${KVER}/dwmac-phytium.ko.xz" "/lib/modules/${KVER}/updates/"
    INSTALLED_MODE="prebuilt"
elif [ -f "${PREBUILT_DIR}/${KVER}/dwmac-phytium.ko" ]; then
    echo "[INFO] 检测到匹配的预编译模块，直接安装 prebuilt/${KVER}/dwmac-phytium.ko..."
    mkdir -p "/lib/modules/${KVER}/updates"
    cp -f "${PREBUILT_DIR}/${KVER}/dwmac-phytium.ko" "/lib/modules/${KVER}/updates/"
    INSTALLED_MODE="prebuilt"
else
    echo "[ERROR] 缺少 /lib/modules/${KVER}/build 且无匹配 ${KVER} 的预编译模块，无法继续安装。" >&2
    exit 1
fi

echo "[INFO] 更新模块依赖并配置开机自动加载..."
depmod -a "${KVER}"
echo "dwmac-phytium" > /etc/modules-load.d/dwmac-phytium.conf

echo "[INFO] 加载 dwmac-phytium 驱动模块..."
if lsmod | grep -q '^dwmac_phytium\b'; then
    modprobe -r dwmac-phytium || true
fi
modprobe dwmac-phytium

# 等待设备节点与网口就绪
sleep 1
IFACE=""
for _ in 1 2 3 4 5; do
    IFACE="$(ls /sys/bus/platform/devices/PHYT0004:00/net/ 2>/dev/null | head -n 1 || true)"
    if [ -n "${IFACE}" ]; then
        break
    fi
    sleep 1
done

if [ -z "${IFACE}" ]; then
    echo "[WARN] 驱动已加载，但未在 PHYT0004:00 下检测到网口，请检查 dmesg。"
    exit 0
fi

echo "[INFO] 检测到板载网卡接口: ${IFACE}"

if [ "${CONFIGURE_DHCP}" -eq 1 ]; then
    if [ -d /etc/network/interfaces.d ]; then
        if ! grep -rqE "(^|[[:space:]])${IFACE}([[:space:]]|$)" /etc/network/interfaces /etc/network/interfaces.d/ 2>/dev/null; then
            cat > "/etc/network/interfaces.d/${IFACE}" <<EOF
# Phytium D2000 onboard GMAC (auto-configured by dwmac-phytium installer)
allow-hotplug ${IFACE}
iface ${IFACE} inet dhcp
EOF
            echo "[INFO] 已写入 /etc/network/interfaces.d/${IFACE} (DHCP)"
        else
            echo "[INFO] /etc/network/interfaces* 中已存在 ${IFACE} 配置，保持不变"
        fi
    fi

    echo "[INFO] 正在拉起 ${IFACE} 并尝试获取 DHCP..."
    if command -v ifup >/dev/null 2>&1 && [ -f "/etc/network/interfaces.d/${IFACE}" ]; then
        ifup "${IFACE}" || ip link set "${IFACE}" up
    elif command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; then
        nmcli device set "${IFACE}" managed yes 2>/dev/null || true
        nmcli device connect "${IFACE}" 2>/dev/null || ip link set "${IFACE}" up
    else
        ip link set "${IFACE}" up
    fi
fi

echo "=== 安装完成 (模式: ${INSTALLED_MODE}, 网口: ${IFACE}) ==="
ip -br addr show "${IFACE}" || true
