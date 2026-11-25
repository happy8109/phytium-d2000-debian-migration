#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="mwv206"
PKG_VER="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "${SCRIPT_DIR}/src" ]; then
    SRC_DIR="${SCRIPT_DIR}/src"
    DEBS_DIR="${SCRIPT_DIR}/debs"
    PREBUILT_DIR="${SCRIPT_DIR}/prebuilt"
else
    REPO_GPU_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
    SRC_DIR="${REPO_GPU_DIR}/src"
    DEBS_DIR="${REPO_GPU_DIR}/debs"
    PREBUILT_DIR="${REPO_GPU_DIR}/prebuilt"
fi

if [ ! -d "${DEBS_DIR}" ] && [ -d "${SCRIPT_DIR}/../debs" ]; then
    DEBS_DIR="${SCRIPT_DIR}/../debs"
fi

KVER="$(uname -r)"

echo "=== 景嘉微 JM7200 (mwv206) 显卡驱动安装程序 ==="
echo "[INFO] 当前内核版本: ${KVER}"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 请使用 root 权限运行: sudo $0" >&2
    exit 1
fi

install_offline_debs() {
    if [ ! -d "${DEBS_DIR}" ] || ! ls "${DEBS_DIR}"/*.deb >/dev/null 2>&1; then
        return 0
    fi
    echo "[INFO] 正在从 ${DEBS_DIR} 离线安装所需依赖..."
    local to_install=()
    local kver_short="${KVER%%+*}"
    for deb in "${DEBS_DIR}"/*.deb; do
        local base
        base="$(basename "$deb")"
        if [[ "$base" == linux-headers-arm64_* ]]; then
            if [[ "$base" != "linux-headers-arm64_${kver_short}"* ]]; then
                continue
            fi
        elif [[ "$base" == linux-headers-* ]] && [[ "$base" != *"-common_"* ]]; then
            if [[ "$base" != "linux-headers-${KVER}_"* ]]; then
                continue
            fi
        fi
        if [[ "$base" == linux-kbuild-* ]] && [[ "$base" != "linux-kbuild-${kver_short}"* ]]; then
            continue
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
if ! command -v dkms >/dev/null 2>&1 || [ ! -d "/lib/modules/${KVER}/build" ] || ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
    need_deps=1
fi
if [ "$need_deps" -eq 1 ]; then
    install_offline_debs
fi

rm -f "/lib/modules/${KVER}/updates/mwv206.ko" \
      "/lib/modules/${KVER}/updates/mwv206.ko.xz"

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
    make -C "${SRC_DIR}" OS=deepin KERNELVER="${KVER}" clean || true
    make -C "${SRC_DIR}" OS=deepin KERNELVER="${KVER}" -j"$(nproc)"
    mkdir -p "/lib/modules/${KVER}/updates"
    cp -f "${SRC_DIR}/mwv206linuxdev/mwv206.ko" "/lib/modules/${KVER}/updates/mwv206.ko"
    INSTALLED_MODE="native"
elif [ -f "${PREBUILT_DIR}/${KVER}/mwv206.ko.xz" ]; then
    echo "[INFO] 检测到匹配的预编译模块，直接安装 prebuilt/${KVER}/mwv206.ko.xz..."
    mkdir -p "/lib/modules/${KVER}/updates"
    cp -f "${PREBUILT_DIR}/${KVER}/mwv206.ko.xz" "/lib/modules/${KVER}/updates/"
    INSTALLED_MODE="prebuilt"
else
    echo "[ERROR] 缺少编译环境且无匹配 ${KVER} 的预编译模块，无法继续安装。" >&2
    exit 1
fi

echo "[INFO] 更新模块依赖并配置开机自动加载..."
depmod -a "${KVER}"
echo "mwv206" > /etc/modules-load.d/mwv206.conf

if [ -d /etc/lightdm ]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/10-mwv206.conf << 'EOF'
[LightDM]
logind-check-graphical=false
EOF
    echo "[INFO] 已写入 /etc/lightdm/lightdm.conf.d/10-mwv206.conf"
fi

if [ -d /etc/X11 ]; then
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-mwv206-fbdev.conf << 'EOF'
Section "Device"
    Identifier "JM7200 MWV206 Framebuffer"
    Driver     "fbdev"
    Option     "fbdev" "/dev/fb0"
EndSection
EOF
    echo "[INFO] 已写入 /etc/X11/xorg.conf.d/20-mwv206-fbdev.conf"
fi

if ! lsmod | grep -q '^mwv206\b'; then
    echo "[INFO] 加载 mwv206 内核模块..."
    modprobe mwv206
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet lightdm 2>/dev/null; then
    echo "[INFO] 重启 lightdm 以应用图形配置..."
    systemctl restart lightdm || true
fi

echo "=== 安装完成 (模式: ${INSTALLED_MODE}) ==="
cat /proc/fb 2>/dev/null || true
