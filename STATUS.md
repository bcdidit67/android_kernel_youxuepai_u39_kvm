# 状态报告（2026-10-19）

优学派 U39（MT8788 / 平台 `mt6771` / 内核 4.4.146）→ 编译带 KVM 的内核，用于 EL2 / KVM 可行性验证。

## 一、已确认的硬事实（设备实测）

| 项 | 实测值 | 结论 |
|---|---|---|
| 内核版本 | `Linux version 4.4.146 (release@yxp) clang 6.0.2 #170 SMP PREEMPT 2023-03-01` | vermagic = `4.4.146 SMP preempt`，无 LOCALVERSION |
| `CONFIG_ARCH_MTK_PROJECT` | `"yxp_738_pad"` | 厂商项目代号 |
| `/proc/device-tree/compatible` | `mediatek,mt6771` | MT8788 = MT6771 平台平板 SKU |
| `gz1` / `gz2` | 各 16 MB，**非零字节数 0** | **无 GenieZone hypervisor** |
| `CONFIG_MTK_ENABLE_GENIEZONE` | `is not set` | 同上 |
| `lk` 镜像 | 无 geniezone / hypervisor / kvm 字符串 | 同上 |
| boot 分区 | 33,554,432 B（32 MiB），header v1，page 2048 | 新内核占用 ~11.5 MB，余量充足 |
| 原厂 boot.img | kernel = `Image.gz`(9,566,522) + 尾附 DTB(110,572)，ramdisk 427,560 | DTB: model=mt6771，含 `arm,psci-1.0`、`arm,gic-v3` |
| 厂商预编译模块 | `wlan_drv_gen3, wmt_drv, gps_drv, bt_drv, fmradio_drv, fpsgo` | 换核后能否加载取决于 vermagic/CRC |

**26 个分区已完整备份**（619 MB，sha256 全部校验通过）：`boot dtbo boot_para recovery lk lk2 tee1 tee2 seccfg noah spmfw scp1 scp2 sspm_1 sspm_2 gz1 gz2 md1img proinfo otp expdb nvram nvdata protect1 protect2 metadata`。`preloader` 全程不触碰。

## 二、donor 内核树的选择过程

| 树 | 结果 |
|---|---|
| `Hadenix/android_kernel_alps-4.4@4.4.146` | ❌ **不可用**：缺 `helio-dvfsrc.h` / `autok.h` 等，连它自己的 `k71v1` 配置都编不过（裁剪镜像） |
| `CyberJalagam/kernel_oppo_mt6771@Alien-Xtreme-master`（4.4.206） | ✅ **可用**：完整 ALPS，带 `virt/kvm/arm/vgic-v3.c`（KVM vGICv3 支持），MT6771 平台齐全 |

**vermagic 对齐**：把该树 `Makefile` 的 `SUBLEVEL` 改为 `146`，使版本串与厂商内核一致（源码本体仍是 4.4.206）。

## 三、编译环境与已解决问题的完整清单

编译机：Fedora 44 / aarch64 / 8 核（绑 2–7 核，`-j6`）/ GCC 16.2.1 / 原生编译。

| 问题 | 解法 |
|---|---|
| `CONFIG_KVM` 有 `depends on (!HARDEN_BRANCH_PREDICTOR \|\| BROKEN)` | 关掉 `HARDEN_BRANCH_PREDICTOR` |
| `scripts/extract-cert` 依赖 `openssl/engine.h`（OpenSSL3 已移除） | 摘掉该 hostprog + certs 规则解耦 |
| MTK 满地的 `subdir-ccflags-y += -Werror`（GCC16 变硬错误） | 精确删除 `-Werror` token（**不能整行删**，会破坏续行） |
| `scripts/Makefile.kasan` 被批量 sed 破坏 | 最小化重写（本构建不用 KASAN） |
| MTK 私用头文件用 `<>` 包含、依赖 Android.mk 注入 `-I` | 建立 **2046 个唯一名头文件 include farm** + 27 个“同目录自引用”目录 + 各子系统显式 `-I` |
| `mtk_dcm.h` 缺 MT6771 分支 | 打补丁指向 `dcm_v1/mtk_dcm.h` |
| `ppm_ipi_init` 未定义 | `PPM_SSPM_SUPPORT` 未定义时不调用 |
| `ld.bfd: read-only segment has dynamic relocations` | `LD="ld.bfd -z notext"` |
| 重打包用了 zlib 而非 gzip | `gzip.compress(img, 9, mtime=0)`（LK 只认 `1f8b`） |

## 四、产物（本次 Release）

| 文件 | 说明 |
|---|---|
| `Image_kvm_oppo` | 29,624,936 B。`Linux version 4.4.146 ... #2 SMP PREEMPT`，含 `kvm: enabling virtualization on CPU%d`、`kvm_vgic_map_phys_irq`。**OPPO 手机配置**，仅用于 EL2/KVM 判定 |
| `boot_kvm_oppo.img` | 32 MB，已重打包：DTB 与原厂**逐字节一致**、ramdisk 一致、header 除 `kernel_size` 全一致 |

校验结论（`tools/verify_boot.py`）：`magic / page_size / kernel_addr / ramdisk_addr / tags_addr / cmdline / header / gz magic / Image sha256 / DTB 一致 / ramdisk 一致` 全部 PASS。

## 五、当前阻塞点

优学派自有配置（`yxp_u39_kvm_defconfig`）编译失败，根因是 **donor 树缺少本机专有驱动源码**：

1. `mt65xx_lcm_list.c` 编译期断言失败 → 原厂屏 `dg10132004_40c_wuxga_dsi_vdo` / `lq079l1sx01_qxga_dsi` 在本树无驱动，`lcm_driver_list` 为空数组
2. `oppo_charger.h` → `linux/qpnp/qpnp-adc.h` 不存在（OPPO 给高通平台写的充电 IC 头）
3. `ufs-mtk-platform.h` → `ufs.h` 缺包含路径（可修）

**这意味着：任何从公开 donor 树编出的内核都不会点亮本机屏幕。** 想要屏幕/触控/充电/WiFi 全部正常，唯一途径是向厂商索取 GPL 源码（`4.4.146` / `yxp_738_pad`）。

## 六、下一步

1. 刷入 `boot_kvm_oppo.img`（只写 `boot`，BROM 兜底），开机后 `adb shell dmesg | grep "started at EL"` → 判定 EL1/EL2
2. 若 EL2：`adb shell ls -l /dev/kvm`，再跑最小 guest
3. 若 EL1：KVM 路线终止，转 TCG
4. 并行：向优学派索取 GPL 源码

## 七、复现方式

```
workspace: /storage/emulated/0/AI/kvm_work/
  backup/    26 个分区镜像 + SHA256SUMS.txt
  parsed/    boot.img 解包（Image.bin / ramdisk.bin / dtb_boot.bin）
  tools/     bootparse.py dtb.py repack_boot.py verify_boot.py gh_ci.py gh_push.py
  out/       Image_kvm / boot_kvm.img / repack.log
  configs/   yxp_u39_kvm_defconfig / yxp_u39_vendor_defconfig
```

编译机：`/root/build_gcc.sh`（OPPO 配置）、`/root/build_yxp.sh`（本机配置）、`/root/k`（内核树，补丁已固化）、`/root/k_mtkinc`（头文件 farm）。

## 八、EL2 / KVM 实测结论（2026-10-20，已确认）

刷入 `boot_kvm_oppo.img` 后：首屏花屏（屏驱动不匹配）→ 黑屏 → 自动重启。刷回原厂 boot 后，从 **`expdb` 分区**里完整取回了探针内核的启动日志（`logs/probe1_kernel_log.txt`）。

**关键证据（同一段连续日志内）：**

```
CPU features: detected feature: GIC system register CPU interface
CPU: All CPU(s) started at EL2
...
kvm [1]: GICv3: no GICV resource entry
kvm [1]: disabling GICv2 emulation
kvm [1]: interrupt-controller@ffffff8008d9eec0 IRQ15
kvm [1]: timer IRQ3
kvm [1]: Hyp mode initialized successfully
```

结论：

1. **本机内核运行在 EL2**，`HCR_EL2` 可用 → KVM 的硬件前提成立
2. **KVM Hyp stub 初始化成功**，vGICv3（GIC system register CPU interface）已接上，GICv2 模拟被正确关闭
3. 不是崩溃内核：日志一路推进到 `init`、`logd`、**`surfaceflinger` 与 `bootanim` 通信**，即 Android 框架已近乎启动，之后才重启
4. `ramoops: attached 0xe0000@0x54410000` —— pstore 也已就绪

**尚未验证**：`/dev/kvm` 节点与真正跑起 guest（因为系统在到达 adb 前就重启了）。

### 剩余缺口（要变成"能日常用的 KVM 平板"）

| 缺口 | 原因 | 出路 |
|---|---|---|
| 屏幕 / 触控 | donor 树里没有 `dg10132004_40c_wuxga_dsi_vdo` / `lq079l1sx01_qxga_dsi` 两个屏的驱动源码 | 只能靠厂商 GPL 源码 |
| 充电 / 电量计 | OPPO 充电框架引用高通 `qpnp-adc.h`，MTK 路径不同 | 同上 |
| Wi-Fi / BT / GPS | 厂商预编译 `.ko`（`wlan_drv_gen3` 等）的 MODVERSIONS CRC 可能与新内核不匹配 | 若拿到源码可整编；否则可尝试关 `MODVERSIONS` |

**唯一能拿到 100% 匹配源码的正规途径：向优学派（yxp）索取 GPL 源码包**，关键字：机型 U39 / `CONFIG_ARCH_MTK_PROJECT="yxp_738_pad"` / `Linux 4.4.146`（构建时间 2023-03-01，`release@yxp`）。