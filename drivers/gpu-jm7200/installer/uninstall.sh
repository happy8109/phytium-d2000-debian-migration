#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="mwv206"
PKG_VER="1.0.0"
KVER="$(uname -r)"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 请使用 root 权限运行: sudo $0" >&2
    exit 1
fi

rm -f /etc/lightdm/lightdm.conf.d/10-mwv206.conf
rm -f /etc/X11/xorg.conf.d/20-mwv206-fbdev.conf
rm -f /etc/modules-load.d/mwv206.conf

if command -v dkms >/dev/null 2>&1; then
    dkms remove -m "${PKG_NAME}" -v "${PKG_VER}" --all >/dev/null 2>&1 || true
fi

rm -rf "/usr/src/${PKG_NAME}-${PKG_VER}"
rm -f "/lib/modules/${KVER}/updates/mwv206.ko" \
      "/lib/modules/${KVER}/updates/mwv206.ko.xz"
depmod -a "${KVER}"

echo "=== 已卸载 mwv206 驱动及相关桌面配置（重启生效） ==="
