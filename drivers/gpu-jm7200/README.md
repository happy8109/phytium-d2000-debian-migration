# 景嘉微 JM7200 显卡驱动（Debian 13 / Linux 6.12）

本目录提供 **景嘉微 JM7200（PCI ID `0731:7200` / Subsystem `0731:7201`）** 显卡在 **飞腾 D2000 / Debian 13 (trixie, Linux 6.12 arm64)** 下的 `mwv206` 内核驱动（Linux 6.12 适配版）、DKMS 配置及 LightDM/Xorg 桌面引导配置。

## 目录结构

```text
gpu-jm7200/
├── README.md
├── docs/
├── installer/
│   ├── install.sh       # DKMS 编译安装 + LightDM/Xorg fbdev 配置
│   └── uninstall.sh     # 卸载脚本
└── src/                 # 已适配 Linux 6.12 / GCC 14 的 mwv206 源码与 dkms.conf
```

## 快速安装

```bash
cd drivers/gpu-jm7200/installer
sudo ./install.sh
```

## Linux 6.12 适配说明

1. **内核 API 适配**：
   - `mwv206_proc.c`：`PDE_DATA` → `pde_data`，`file_operations` → `proc_ops`
   - `mwv206_fb.c`：`strlcpy` → `strscpy`，`remove_conflicting_framebuffers` → `aperture_remove_conflicting_pci_devices`，`mwv206fb_ops` 补齐 `__FB_DEFAULT_IOMEM_OPS_RDWR` 与 `__FB_DEFAULT_IOMEM_OPS_MMAP`（解决 `Xorg fbdev` 报错 `mmap fbmem: No such device`）
   - `mwv206_hdmiaudio.c`：`snd_dma_continuous_data(GFP_KERNEL)` → `NULL`，`snd_pcm_ops.copy_user` → `copy`（`iov_iter` + `copy_from_iter`）
   - `mwv206_edid.c`：`drm_edid_block_valid` → `drm_edid_is_valid`
   - `mwv206_pci.c` / `mwv206ioctl_config.c`：`access_ok` 去除旧版首参，`class_create` 去除 `THIS_MODULE`，`kallsyms_lookup_name` 按内核版本条件屏蔽
   - `mwv206hal/`：`mwv206dec.h` 避免与 `printk` 宏冲突，`mwv206dec_aarch64.S` 调用 `_printk`，`mwv206memmgr.c` 适配两参数 `__vmalloc`，`mwv206dev.c` 屏蔽已移除的 `linux/input-polldev.h`
2. **桌面环境（LightDM + Xorg）配置**：
   - `mwv206` 提供 `/dev/fb0`（`0 MWV206`）而不提供 `/dev/dri`；通过 `/etc/lightdm/lightdm.conf.d/10-mwv206.conf` 设置 `logind-check-graphical=false` 并通过 `/etc/X11/xorg.conf.d/20-mwv206-fbdev.conf` 指定 `fbdev` 绑定 `/dev/fb0`，即可正常拉起 LightDM 与 Xfce 桌面。
