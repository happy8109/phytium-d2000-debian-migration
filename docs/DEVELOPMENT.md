# 飞腾 D2000 板载网卡驱动开发文档（Debian 13 / Linux 6.12）

> 本文档记录基于 **黄河 K681 F223（飞腾 D2000/8）** 平台在 **Debian 13 (trixie)**、**Linux 6.12** 环境下为板载千兆网卡（`PHYT0004` / `FTGM0001`）开发原生驱动的分析、设计、调试与验证过程。

---

## 1. 目标主机环境调研

调研日期：2026-11-18  
目标主机：`192.168.9.226`（主机名 `xcfk`）

### 1.1 硬件与固件信息

| 项目 | 实测信息 |
| --- | --- |
| 整机厂商 / 型号 | Huanghe `K681 F223`（Version `V1.0`） |
| 主板型号 | `L21K-2041K` |
| 处理器 | Phytium `FTC663`（飞腾 D2000/8，8 核 `aarch64`） |
| 引导方式 | EFI v2.7 by Phytium D2000（UEFI + ACPI，无 `/proc/device-tree`） |
| 兼容网卡（当前在线） | `06:00.0` Realtek RTL8111/8168/8211/8411 `[10ec:8168]`，内核驱动 `r8169`，接口名 `enp6s0` |
| 板载待驱动网卡 | ACPI 设备 `PHYT0004:00`（路径 `\_SB_.ETH1`），`_HID=PHYT0004`，`_CID=FTGM0001`，`_UID=1`，`_STA=15` |
| 板载网卡 MMIO 资源 | `0x28210000 - 0x28211fff`（8 KiB） |

### 1.2 操作系统与内核状态

| 项目 | 实测信息 |
| --- | --- |
| 操作系统 | Debian GNU/Linux 13 (trixie) `13.7` |
| 内核版本 | `6.12.107+deb13-arm64 #1 SMP Debian 6.12.107-1 (2026-08-29) aarch64` |
| 根分区可用空间 | `/dev/nvme0n1p3` 共 226G，可用 210G（已用 3%） |
| 编译工具链 | `gcc`、`make`、`dpkg` 已安装 |
| 内核头文件 | `/lib/modules/6.12.107+deb13-arm64/build` 暂不存在；apt 源（清华源）提供 `linux-headers-6.12.107+deb13-arm64`（`6.12.107-1`） |
| ACPI 反编译工具 | `iasl` / `acpidump` 暂未安装；apt 源提供 `acpica-tools`（`20250404-1`） |

### 1.3 内核已有相关模块与配置

从 `/boot/config-6.12.107+deb13-arm64` 及 `/lib/modules/6.12.107+deb13-arm64/kernel/drivers/net/ethernet/stmicro/stmmac/` 确认：

- 核心模块均已编译为可加载模块（`m`）：
  - `CONFIG_STMMAC_ETH=m`（`stmmac.ko.xz`）
  - `CONFIG_STMMAC_PLATFORM=m`（`stmmac-platform.ko.xz`）
  - `CONFIG_DWMAC_GENERIC=m`（`dwmac-generic.ko.xz`）
- PHY 驱动已启用：
  - `CONFIG_MOTORCOMM_PHY=m`
  - `CONFIG_REALTEK_PHY=m`
- 未内置飞腾专用胶水驱动，且 `dwmac-generic` 未包含 `PHYT0004` / `FTGM0001` 的 ACPI 匹配表，因此内核启动后 `PHYT0004:00` 处于未绑定驱动状态（`/sys/bus/platform/devices/PHYT0004:00/waiting_for_supplier` 为 `0`）。

### 1.4 ACPI DSDT 初步特征

通过读取 `/sys/firmware/acpi/tables/DSDT` 可见 `\_SB_.ETH1`（`PHYT0004` / `FTGM0001`）包含 `_CRS`、`_CCA` 与 `_DSD`，其中 `_DSD` 暴露了以下属性关键字：

- 中断与时钟：`interrupt-names`（`macirq`）、`clocks`、`clock-names`（`stmmaceth`）、`clock-frequency`
- MAC / DMA 参数：`snps,pbl`、`snps,abl`、`snps,burst_len`、`snps,multicast-filter-bins`、`snps,perfect-filter-entries`、`max-frame-size`
- PHY / 接口参数：`phy-mode`（`rgmii-rxid`）、`bus_id`、`txc-skew-ps`
- 同表中还存在时钟 ACPI 设备 `PHYT8001`（`\_SB_.CLK1`）和 `PHYT8002`（`\_SB_.CLK2`）。

---

## 2. 可行性评估

### 2.1 结论

**完全可行，且工程复杂度可控、风险低。**

### 2.2 依据

1. **核心驱动栈无需重写**：Debian 13 6.12 内核已将 `stmmac` 与 `stmmac-platform` 编译为模块并导出平台驱动接口，仅需编写 Out-of-Tree 平台胶水模块（如 `dwmac-phytium.ko`），通过 `acpi_match_table` 匹配 `PHYT0004` / `FTGM0001`。
2. **固件信息完整**：ACPI DSDT 已提供 MMIO 地址、中断和 `_DSD` 参数，安装 `acpica-tools` 后即可完整反编译确认所有硬件参数。
3. **原生直编条件充分**：目标机 `aarch64` 环境与软件源均完整，安装 `linux-headers-6.12.107+deb13-arm64` 后即可原地编译加载 `.ko`，不影响现有 `enp6s0`（`r8169`）SSH 网络。

### 2.3 关键技术风险与待确认项

1. **ACPI 时钟适配**：DSDT 中可能引用 `\_SB.CLK1`（`PHYT8001`），Linux 主线 ACPI 下通常无对应 CCF 时钟驱动；胶水驱动需读取 `_DSD` 中的 `clock-frequency` 并注册固定频率时钟（如 `clk_register_fixed_rate`）供给 `stmmaceth`。
2. **DMA 与缓存一致性**：需确认 DSDT 中 `_CCA` 值，并在 `probe` 中正确配置 `dma_set_mask_and_coherent`。
3. **PHY 识别与 RGMII 时延**：需反编译 DSDT 确认 `phy-mode`（`rgmii-rxid`）、`txc-skew-ps`、MDIO 扫描以及板上实际 PHY 芯片型号，避免出现识别不到 PHY 或千兆链路丢包问题。
4. **Linux 6.12 API 适配**：[README.md](file:///e:/phytium-d2000-debian-migration/README.md) 原先面向 Linux 6.6 LTS，而目标机运行 **6.12.107** 内核，需严格依据 `linux-headers-6.12.107+deb13-arm64` 头文件适配 `plat_stmmacenet_data` 等结构体与符号。

---

## 3. 计划与开发里程碑

- [x] **阶段 0：主机环境调研与可行性评估**（已完成，见第 1、2 节）
- [x] **阶段 1：安装头文件与反编译 ACPI DSDT**
  - 已安装 `linux-headers-6.12.107+deb13-arm64`（`6.12.107-1`）与 `acpica-tools`（`20250404-1`）
  - 已反编译 `DSDT` / `SSDT`，获取 `\_SB_.ETH1` 完整 ASL 定义及 `Module.symvers` / BTF 符号布局
- [x] **阶段 2：驱动设计、编码与编译**
  - 已编写适配 Linux 6.12 的 [dwmac-phytium.c](file:///e:/phytium-d2000-debian-migration/src/dwmac-phytium.c) 与 [Makefile](file:///e:/phytium-d2000-debian-migration/src/Makefile)
  - 已在目标机原生编译生成 `dwmac-phytium.ko`（零警告）
- [x] **阶段 3：加载调试与连通性验证**（已完成）
  - [x] 加载 `dwmac-phytium.ko`，注册网卡 `enaphyt4i0`（MAC `98:0e:24:51:28:6d`，GICv3 IRQ `82`），识别 PHY `YT8521 Gigabit Ethernet`
  - [x] 修复首次加载时的 `clk_prepare_enable` / `pm_runtime_suspend` 时钟告警
  - [x] 接入网线实测千兆链路协商（`1000Mb/s Full`，`carrier=1`）及二/三层收发包（`ping -6 -n -c 3 -I enaphyt4i0 ff02::1` 0% 丢包，局域网多主机正常应答，RX/TX 零错误）
- [x] **阶段 4：持久化与交付**（已完成）
  - [x] 通过 `modules_install` 安装至 `/lib/modules/6.12.107+deb13-arm64/updates/dwmac-phytium.ko.xz`，执行 `depmod -a` 并配置 `/etc/modules-load.d/dwmac-phytium.conf` 实现开机自动加载
  - [x] 验证 `rmmod dwmac_phytium && modprobe dwmac-phytium` 正常拉起 `enaphyt4i0`
  - [x] 同步更新仓库源码与开发文档
- [x] **阶段 5：离线安装套件（方案 C + DKMS + 自动 DHCP）**（已完成）
  - [x] 新增 [dkms.conf](file:///e:/phytium-d2000-debian-migration/src/dkms.conf)、[install.sh](file:///e:/phytium-d2000-debian-migration/installer/install.sh) 与 [uninstall.sh](file:///e:/phytium-d2000-debian-migration/installer/uninstall.sh)
  - [x] 打包离线 `.deb` 依赖（`dkms`、`linux-headers-6.12.107+deb13-arm64` 及关联依赖、`dpkg-dev`、`patch`、`make`、`gcc`）与 `prebuilt/6.12.107+deb13-arm64/dwmac-phytium.ko.xz`
  - [x] 在目标机端到端实测 `install.sh`：DKMS 注册安装（`dwmac-phytium/1.0.0, 6.12.107+deb13-arm64, aarch64: installed`），自动写入 `/etc/network/interfaces.d/enaphyt4i0` 并成功通过 DHCP 获取 `192.168.9.138/24`，`ping -I enaphyt4i0 -n -c 4 192.168.9.1` 4/4 成功（0% 丢包，平均 0.404 ms）
  - [x] 生成离线分发包 [phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz](file:///e:/phytium-d2000-debian-migration/dist/phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz)（约 18 MiB）

---

## 4. DSDT 解析与驱动设计细节（阶段 1-2 记录）

### 4.1 `\_SB_.ETH1` ASL 关键参数（来自 `DSDT.dsl`）

| 属性 / 资源 | 实测值 | 说明 |
| --- | --- | --- |
| `_HID` / `_CID` | `PHYT0004` / `FTGM0001` | ACPI 匹配 ID |
| `_UID` / `_CCA` | `1` / `1` | 缓存一致 DMA |
| `_CRS` 内存 | `0x28210000`（长度 `0x2000`） | GMAC 寄存器基址 |
| `_CRS` 中断 | `0x52`（十进制 `82`，Level ActiveHigh） | `interrupt-names = "macirq"` |
| `clock-frequency` | `0x0EE6B280`（`250000000` Hz） | 250 MHz 参考时钟 |
| `phy-mode` | `"rgmii-rxid"` | RGMII RX 内部延时 |
| `mdc_clock_selection` | `0x05` | `STMMAC_CSR_250_300M` |
| `bus_id` | `1` | MDIO 总线号 `stmmac-1` |
| `snps,pbl` / `snps,abl` | `0x10` (16) / `0x20` (32) | DMA PBL |
| `snps,burst_len` | `0x0E` | AXI burst 4/8/16 |
| `snps,multicast-filter-bins` | `0x40` (64) | 多播过滤桶数 |
| `snps,perfect-filter-entries` | `0x41` (65) | 单播完美过滤表项数 |
| `max-frame-size` | `0x2328` (9000) | 最大帧长 |
| `txc-skew-ps` / `rxc-skew-ps` | `0x03E8` (1000) | 板级 RGMII 时延提示 |

### 4.2 BTF 与内核 6.12 适配要点

- 通过内核 BTF（`pahole -F btf --btf_base /sys/kernel/btf/vmlinux -C stmmac_resources /sys/kernel/btf/stmmac`）核对 `struct stmmac_resources` 二进制布局（104 字节），避免 Out-of-Tree 模块缺少内部头文件导致的 ABI 偏差。
- `stmmac_pltfr_remove` 在 Linux 6.12 中返回 `void`，直接绑定到 `platform_driver.remove`。
- **时钟使能坑点（已修复）**：`stmmac_pltfr_probe()` 假定 `plat->stmmac_clk` 已处于 `clk_prepare_enable()` 状态；仅调用 `clk_register_fixed_rate()` 会在 `pm_runtime_suspend` 触发 `stmmac_bus_clks_config(priv, false)` 时引发 `stmmaceth already disabled / unprepared` 内核 `WARNING`。在 `probe` 中补充 `clk_prepare_enable()` 并在 `devm` 释放回调中先 `clk_disable_unprepare()` 再 `clk_unregister_fixed_rate()` 后，卸载与运行时挂起均无任何告警。

---

## 5. 开发日志

### 2026-11-18
- 完成 `192.168.9.226`（`happy8109`）远程环境调研，确认平台为黄河 K681 F223（飞腾 D2000/8），系统 Debian 13.7，内核 `6.12.107+deb13-arm64`，板载网卡 ACPI 设备为 `PHYT0004:00`（`\_SB_.ETH1`，`_CID=FTGM0001`）。
- 确认可行性并建立本开发文档 [DEVELOPMENT.md](file:///e:/phytium-d2000-debian-migration/docs/DEVELOPMENT.md)。
- **阶段 1**：在主机安装 `linux-headers-6.12.107+deb13-arm64` 与 `acpica-tools`，反编译 `DSDT`/`SSDT` 获取 `ETH1` 完整参数，并通过 BTF 核验 `stmmac_resources` 布局。
- **阶段 2**：编写 [dwmac-phytium.c](file:///e:/phytium-d2000-debian-migration/src/dwmac-phytium.c) 与 [Makefile](file:///e:/phytium-d2000-debian-migration/src/Makefile)，在目标机编译通过。
- **阶段 3**：加载后成功识别 `DWMAC1000`（`Synopsys ID: 0x36`）、MAC `98:0e:24:51:28:6d` 与 `YT8521 Gigabit Ethernet` PHY（`0x0000011a`），注册网口 `enaphyt4i0` 与 GICv3 中断 `82`；修复 `stmmaceth` 时钟未使能导致的 `pm_runtime_suspend` 告警后，接入网线实测 `Link is Up - 1Gbps/Full`，`ping -6 -n -c 3 -I enaphyt4i0 ff02::1` 收到局域网多节点应答（0% 丢包，RX/TX 零错误）。
- **阶段 4**：执行 `modules_install` 将模块安装至 `/lib/modules/6.12.107+deb13-arm64/updates/dwmac-phytium.ko.xz`，运行 `depmod -a` 并写入 `/etc/modules-load.d/dwmac-phytium.conf`，验证 `modprobe dwmac-phytium` 可正常加载并拉起 `enaphyt4i0`。
- **阶段 5**：构建并实测方案 C 离线安装套件（DKMS + 离线 `.deb` 依赖 + `prebuilt` 回退 + 自动 DHCP）。`install.sh` 实测通过 DKMS 编译安装至 `/lib/modules/6.12.107+deb13-arm64/updates/dkms/dwmac-phytium.ko.xz`，自动写入 `/etc/network/interfaces.d/enaphyt4i0` 并通过 `dhcpcd` 获取 `192.168.9.138/24`，`ping -I enaphyt4i0 -n -c 4 192.168.9.1` 0% 丢包（平均 RTT 0.404 ms）。

### 多机离线部署方式
将 `dist/phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz` 拷贝到目标飞腾 D2000 Debian 13 主机后执行：
```bash
tar -xzf phytium-d2000-nic-offline-v1.0.0-arm64.tar.gz
cd phytium-d2000-nic-offline
sudo ./install.sh
```
- 如需仅安装驱动、暂不配置 DHCP，可执行 `sudo ./install.sh --no-dhcp`。
- 如需卸载驱动与配置，可执行 `sudo ./uninstall.sh`。
- 若未来在线 `apt upgrade` 升级内核，DKMS 会自动为新内核重编 `dwmac-phytium`（需保持安装了 `linux-headers-arm64`）。
