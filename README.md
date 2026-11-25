# 飞腾 D2000 平台 Debian 13 (trixie) 迁移与驱动适配

本项目针对 **飞腾腾锐 D2000/8（Phytium FTC663）** 平台（实测机型：**黄河 K681 F223 / 主板 L21K-2041K**，UEFI + ACPI 模式）迁移至 **Debian 13 (trixie, Linux 6.12 arm64)** 过程中的硬件驱动适配与离线部署。

## 硬件适配进度

| 子系统 | 硬件 / 标识 | Debian 13 状态 | 模块目录 |
| :--- | :--- | :--- | :--- |
| **板载千兆网卡** | 飞腾 GMAC (`PHYT0004` / `FTGM0001` + `YT8521`) | ✅ 已完成 (`v1.0.1` DKMS + 离线包) | [nic-dwmac-phytium](file:///e:/phytium-d2000-debian-migration/drivers/nic-dwmac-phytium/README.md) |
| **独立显卡** | 景嘉微 JM7200 (`0731:7200`) | ✅ 已完成 (`mwv206` 6.12 适配 + DKMS + Xfce 实测) | [gpu-jm7200](file:///e:/phytium-d2000-debian-migration/drivers/gpu-jm7200/README.md) |
| **板载声卡** | 飞腾 HDA 控制器 (`PHYT0006` / `FTHD0001`) | ⏳ 待适配（外接 USB 声卡 `31b2:0011` 免驱可用） | — |

## 仓库目录结构

```text
phytium-d2000-debian-migration/
├── README.md                  # 平台迁移总览
├── dist/                      # 离线分发包（不入 Git，通过 GitHub Releases 分发）
│   ├── phytium-d2000-nic-offline-v1.0.1-arm64.tar.gz      # 网卡离线套件 (dwmac-phytium)
│   └── phytium-d2000-gpu-offline-v1.0.0-arm64.tar.gz      # 显卡离线套件 (mwv206)
├── scripts/
│   └── build-dist.sh          # 在 Debian 13 arm64 主机上复现生成离线包
└── drivers/                   # 按硬件子系统隔离的驱动模块
    ├── nic-dwmac-phytium/     # 板载网卡驱动 (dwmac-phytium)
    └── gpu-jm7200/            # 景嘉微 JM7200 显卡驱动 (mwv206)
```

## 离线包构建与发布

仓库仅跟踪源码与脚本，`dist/*.tar.gz` 已通过 `.gitignore` 忽略。如需在 Debian 13 arm64 主机上重新生成离线包并上传至 GitHub Releases：

```bash
chmod +x scripts/build-dist.sh
./scripts/build-dist.sh
```
