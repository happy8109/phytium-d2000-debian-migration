#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="dwmac-phytium"
PKG_VER="1.0.1"
KVER="$(uname -r)"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 请使用 root 权限运行: sudo $0" >&2
    exit 1
fi

IFACE="$(ls /sys/bus/platform/devices/PHYT0004:00/net/ 2>/dev/null | head -n 1 || true)"

if [ -n "${IFACE}" ]; then
    if command -v ifdown >/dev/null 2>&1; then
        ifdown "${IFACE}" 2>/dev/null || true
    fi
    ip link set "${IFACE}" down 2>/dev/null || true
    rm -f "/etc/network/interfaces.d/${IFACE}"
fi

if lsmod | grep -q '^dwmac_phytium\b'; then
    modprobe -r dwmac-phytium || true
fi

if command -v dkms >/dev/null 2>&1; then
    dkms remove -m "${PKG_NAME}" -v "${PKG_VER}" --all >/dev/null 2>&1 || true
fi

rm -rf "/usr/src/${PKG_NAME}-${PKG_VER}"
rm -f "/etc/modules-load.d/dwmac-phytium.conf"
rm -f "/lib/modules/${KVER}/updates/dwmac-phytium.ko" \
      "/lib/modules/${KVER}/updates/dwmac-phytium.ko.xz"
depmod -a "${KVER}"

echo "=== 已卸载 dwmac-phytium 驱动及配置 ==="
