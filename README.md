# 飞腾 D2000 板载千兆网卡驱动（Debian 13 / Linux 6.12 离线安装套件）

![Phytium D2000](https://img.shields.io/badge/CPU-Phytium%20D2000%2F8-blue.svg)
![Kernel](https://img.shields.io/badge/Kernel-Linux%206.12%20(Debian%2013)-brightgreen.svg)
![Driver](https://img.shields.io/badge/Driver-dwmac--phytium-orange.svg)
![Mode](https://img.shields.io/badge/Install-Offline%20%2B%20DKMS-success.svg)

本项目为 **飞腾腾锐 D2000/8（Phytium FTC663）** 平台（已于 **黄河 K681 F223 / 主板 L21K-2041K** 实测）在 **Debian 13 (trixie)**、UEFI + ACPI 模式下提供板载千兆网卡（ACPI `_HID=PHYT0004` / `_CID=FTGM0001`、Synopsys `DWMAC1000` + Motorcomm `YT8521` PHY）的**原生驱动与无网离线一键安装套件**。

---

## 一、交付物目录结构

```text
phytium-d2000-nic-offline/
├── README.md                          # 使用说明
├── install.sh                         # 一键离线安装脚本（支持 DKMS + 自动 DHCP）
├── uninstall.sh                       # 一键卸载脚本
├── src/                               # 驱动源码与 DKMS 配置
│   ├── dwmac-phytium.c
│   ├── Makefile
│   └── dkms.conf
├── prebuilt/
│   └── 6.12.107+deb13-arm64/
│       └── dwmac-phytium.ko.xz        # 6.12.107+deb13-arm64 预编译模块（无编译环境时回退使用）
└── debs/                              # 离线依赖包（dkms、linux-headers-6.12.107+deb13-arm64 等）
```

仓库内对应文件：
- 离线分发压缩包：[phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz](file:///e:/phytium-d2000-debian-migration/dist/phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz)
- 驱动源码：[dwmac-phytium.c](file:///e:/phytium-d2000-debian-migration/src/dwmac-phytium.c)、[Makefile](file:///e:/phytium-d2000-debian-migration/src/Makefile)、[dkms.conf](file:///e:/phytium-d2000-debian-migration/src/dkms.conf)
- 安装脚本：[install.sh](file:///e:/phytium-d2000-debian-migration/installer/install.sh)、[uninstall.sh](file:///e:/phytium-d2000-debian-migration/installer/uninstall.sh)
- 开发与调试文档：[DEVELOPMENT.md](file:///e:/phytium-d2000-debian-migration/docs/DEVELOPMENT.md)

---

## 二、快速使用（无网环境多机部署）

1. 将 `phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz` 拷贝到目标飞腾 D2000 Debian 13 主机。
2. 解压并执行安装脚本：

```bash
tar -xzf phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz
cd phytium-d2000-nic-offline
sudo ./install.sh
```

### 可选参数

- **仅安装驱动，暂不自动配置 DHCP**：
  ```bash
  sudo ./install.sh --no-dhcp
  ```
- **完整卸载驱动、DKMS 注册与网口 DHCP 配置**：
  ```bash
  sudo ./uninstall.sh
  ```

---

## 三、安装脚本工作流程

1. **离线依赖检查与补齐**：检测 `dkms`、`gcc`、`make` 及 `/lib/modules/$(uname -r)/build` 是否存在，缺失时自动从 `debs/` 目录离线安装匹配当前内核版本的 `.deb` 依赖包。
2. **驱动编译与安装（混合策略）**：
   - **优先 DKMS**：当 `dkms`、编译工具与当前内核头文件就绪时，注册并编译安装 `dwmac-phytium/1.0.0` 到 DKMS；
   - **次选本地直编**：若无 `dkms` 但具备内核头文件与编译工具，则原地 `make` 编译安装；
   - **兜底预编译回退**：若无编译环境但当前内核为 `6.12.107+deb13-arm64`，直接安装 `prebuilt/` 下对应版本的 `.ko.xz`。
3. **持久化与加载**：执行 `depmod -a`，写入 `/etc/modules-load.d/dwmac-phytium.conf` 实现开机自动加载，并立即 `modprobe dwmac-phytium`。
4. **自动配置 DHCP**：自动识别 `PHYT0004:00` 对应的网口名（如 `enaphyt4i0`），写入 `/etc/network/interfaces.d/<网口名>`（`allow-hotplug` + `dhcp`，不覆盖已有配置）并立即拉起获取 IP。

---

## 四、安装后验证

```bash
# 查看网口状态与 IP
ip -br addr

# 查看 DKMS 状态
sudo dkms status

# 查看内核驱动日志
sudo dmesg | grep -iE "phytium-dwmac|YT8521|enaphyt"
```

---

## 五、常见问题（FAQ）

1. **后续在线 `apt upgrade` 升级了内核，驱动会失效吗？**  
   只要已通过 DKMS 安装且系统装有 `linux-headers-arm64`，升级新内核时 DKMS 会自动为新内核重编 `dwmac-phytium.ko.xz`，重启后依然可用。
2. **其他主机内核版本与 `6.12.107+deb13-arm64` 有小差异时能否安装？**  
   预编译 `.ko.xz` 仅适用于完全一致的 `uname -r`（`6.12.107+deb13-arm64`）。若其他主机为不同的 `6.12.x` 小版本，只需确保该主机已安装对应版本的 `linux-headers-<uname -r>`，运行 `sudo ./install.sh` 即可自动完成编译安装。
