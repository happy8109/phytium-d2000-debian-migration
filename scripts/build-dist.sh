#!/usr/bin/env bash
set -euo pipefail

# 在 Debian 13 (trixie) arm64 主机上复现生成网卡与显卡独立离线分发包
# 用法: ./scripts/build-dist.sh [--skip-debs]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_DIR}/dist"
NIC_DIR="${REPO_DIR}/drivers/nic-dwmac-phytium"
GPU_DIR="${REPO_DIR}/drivers/gpu-jm7200"

KVER="$(uname -r)"
KVER_SHORT="${KVER%%+*}"
NIC_VER="$(grep -E '^PACKAGE_VERSION=' "${NIC_DIR}/src/dkms.conf" | cut -d'"' -f2)"
GPU_VER="$(grep -E '^PACKAGE_VERSION=' "${GPU_DIR}/src/dkms.conf" | cut -d'"' -f2)"

SKIP_DEBS=0
for arg in "$@"; do
    case "$arg" in
        --skip-debs) SKIP_DEBS=1 ;;
        -h|--help)
            echo "用法: $0 [--skip-debs]"
            exit 0
            ;;
        *)
            echo "未知参数: $arg" >&2
            exit 1
            ;;
    esac
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

DEBS_CACHE="${WORK_DIR}/debs"
mkdir -p "${DEBS_CACHE}" "${DIST_DIR}"

if [ "${SKIP_DEBS}" -eq 0 ]; then
    echo "[INFO] 解析并下载完整递归离线 .deb 依赖（目标内核: ${KVER}）..."
    LC_ALL=C python3 - "${KVER}" "${KVER_SHORT}" "${WORK_DIR}/debs.list" << 'PY'
import sys, subprocess, re, os

kver, kver_short, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
env = dict(os.environ, LC_ALL="C")

seeds = [
    "dkms", "gcc", "make", "patch", "pahole", "dpkg-dev",
    f"linux-headers-{kver}",
    f"linux-headers-{kver_short}+deb13-common",
    f"linux-kbuild-{kver_short}+deb13",
    "linux-headers-arm64",
    "libdw1t64",
]

base_skip = {
    "systemd", "systemd-standalone-sysusers", "udev", "libsystemd0", "libsystemd-shared", "libudev1",
    "initramfs-tools", "initramfs-tools-core", "dracut", "dracut-core", "dracut-install",
    "tiny-initramfs", "tiny-initramfs-core", "klibc-utils", "libklibc",
    "e2fsprogs", "logsave", "libext2fs2t64", "libss2", "libcom-err2",
    "kmod", "cpio", "xz-utils", "liblzma5", "zlib1g", "libzstd1",
    "cdebconf", "debconf", "libdebconfclient0", "opensysusers",
    "libacl1", "libapparmor1", "libattr1", "libaudit-common", "libaudit1",
    "libblkid1", "libmount1", "libsmartcols1", "libuuid1",
    "libpam0g", "libpcre2-8-0", "libssl3t64", "openssl-provider-legacy",
    "libtinfo6", "libnewt0.52", "libslang2", "libreadline8t64", "readline-common",
}

def is_essential_or_required(pkg):
    out = subprocess.check_output(["apt-cache", "show", pkg], text=True, errors="replace", env=env)
    for line in out.splitlines():
        if line.startswith("Essential: yes") or line.startswith("Priority: required"):
            return True
        if line == "":
            break
    return False

visited, to_download, queue = set(), set(), list(seeds)
while queue:
    pkg = queue.pop(0)
    if pkg in visited:
        continue
    visited.add(pkg)
    if pkg.startswith("linux-image-") or pkg in base_skip:
        continue
    try:
        if is_essential_or_required(pkg):
            continue
    except subprocess.CalledProcessError:
        continue
    to_download.add(pkg)
    out = subprocess.check_output(
        ["apt-cache", "depends", "--no-recommends", "--no-suggests",
         "--no-conflicts", "--no-breaks", "--no-replaces", "--no-enhances", pkg],
        text=True, errors="replace", env=env,
    )
    lines = out.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"^\s*(?:Pre)?Depends:\s*(\S+)", line)
        if m:
            alt = m.group(1)
            if alt.startswith("<"):
                if i + 1 < len(lines) and lines[i + 1].startswith("    "):
                    alt = lines[i + 1].strip().split()[0]
                else:
                    continue
            if alt not in visited:
                queue.append(alt)

with open(out_path, "w") as f:
    for p in sorted(to_download):
        f.write(p + "\n")
print(f"Resolved {len(to_download)} packages")
PY
    (cd "${DEBS_CACHE}" && xargs -a "${WORK_DIR}/debs.list" apt-get download)
fi

echo "[INFO] 预编译网卡与显卡模块 (${KVER})..."
NIC_BUILD="${WORK_DIR}/nic-build"
cp -a "${NIC_DIR}/src" "${NIC_BUILD}"
make -C "/lib/modules/${KVER}/build" M="${NIC_BUILD}" modules
xz -f -k "${NIC_BUILD}/dwmac-phytium.ko"

GPU_BUILD="${WORK_DIR}/gpu-build"
cp -a "${GPU_DIR}/src" "${GPU_BUILD}"
env -u KERNELRELEASE make -C "${GPU_BUILD}" OS=deepin KERNELVER="${KVER}" -j"$(nproc)"
xz -f -k "${GPU_BUILD}/mwv206linuxdev/mwv206.ko"

echo "[INFO] 打包网卡离线套件..."
NIC_STAGE="${WORK_DIR}/phytium-d2000-nic-offline"
mkdir -p "${NIC_STAGE}/src" "${NIC_STAGE}/debs" "${NIC_STAGE}/prebuilt/${KVER}"
cp -a "${NIC_DIR}/src/." "${NIC_STAGE}/src/"
cp -f "${NIC_DIR}/README.md" "${NIC_STAGE}/README.md"
install -m 755 "${NIC_DIR}/installer/install.sh" "${NIC_STAGE}/install.sh"
install -m 755 "${NIC_DIR}/installer/uninstall.sh" "${NIC_STAGE}/uninstall.sh"
cp -f "${NIC_BUILD}/dwmac-phytium.ko.xz" "${NIC_STAGE}/prebuilt/${KVER}/"
cp -f "${DEBS_CACHE}"/*.deb "${NIC_STAGE}/debs/" 2>/dev/null || true
tar -czf "${DIST_DIR}/phytium-d2000-nic-offline-v${NIC_VER}-arm64.tar.gz" -C "${WORK_DIR}" "phytium-d2000-nic-offline"

echo "[INFO] 打包显卡离线套件..."
GPU_STAGE="${WORK_DIR}/phytium-d2000-gpu-offline"
mkdir -p "${GPU_STAGE}/src" "${GPU_STAGE}/debs" "${GPU_STAGE}/prebuilt/${KVER}"
cp -a "${GPU_DIR}/src/." "${GPU_STAGE}/src/"
cp -f "${GPU_DIR}/README.md" "${GPU_STAGE}/README.md"
install -m 755 "${GPU_DIR}/installer/install.sh" "${GPU_STAGE}/install.sh"
install -m 755 "${GPU_DIR}/installer/uninstall.sh" "${GPU_STAGE}/uninstall.sh"
cp -f "${GPU_BUILD}/mwv206linuxdev/mwv206.ko.xz" "${GPU_STAGE}/prebuilt/${KVER}/"
cp -f "${DEBS_CACHE}"/*.deb "${GPU_STAGE}/debs/" 2>/dev/null || true
tar -czf "${DIST_DIR}/phytium-d2000-gpu-offline-v${GPU_VER}-arm64.tar.gz" -C "${WORK_DIR}" "phytium-d2000-gpu-offline"

echo "=== 打包完成 ==="
ls -lh "${DIST_DIR}"/*.tar.gz
