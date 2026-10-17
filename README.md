# android_kernel_youxuepai_u39_kvm

优学派 U39（MediaTek **MT8788**，平台代码 `mt6771`，内核 **Linux 4.4.146**）→ 编译带 **KVM** 的内核。

本仓库**不存内核源码**（源码 200 MB+，且国内直连 GitHub 不稳）。仓库只放：

| 路径 | 作用 |
|---|---|
| `configs/yxp_u39_vendor_defconfig` | 原厂 `/proc/config.gz` 原样导出（**基线**，用于验证 donor 树能否编译） |
| `configs/yxp_u39_kvm_defconfig` | 基线 + 3 处改动，开启 KVM |
| `.github/workflows/build-kernel.yml` | CI：clone 上游 MTK ALPS 4.4.146 → 应用 defconfig → 编译 `Image` → 上传 artifact |

## 上游 donor 树

`Hadenix/android_kernel_alps-4.4` @ `4.4.146`（完整 MTK ALPS 树，版本号与本机内核**完全一致**；
含 `arch/arm64/configs/evb6771_64_emmc_defconfig`、`k71v1_64_bsp_defconfig`；
`virt/kvm/arm/` 带 **vgic-v3** 支持 —— 本机是 GICv3-only，这一点是 KVM 可行的前提）。

## defconfig 的 3 处改动（其余 4664 行逐行原样）

```
# CONFIG_VIRTUALIZATION is not set   ->  CONFIG_VIRTUALIZATION=y
(不存在)                            ->  CONFIG_KVM=y  +  CONFIG_KVM_ARM_MAX_VCPUS=8
CONFIG_HARDEN_BRANCH_PREDICTOR=y     ->  # ... is not set
```

> 第 3 项是硬依赖：`arch/arm64/kvm/Kconfig` 里 `CONFIG_KVM` 有
> `depends on (!HARDEN_BRANCH_PREDICTOR || BROKEN)`，不关掉它 KVM 根本选不中。

`CONFIG_LOCALVERSION=""`、`CONFIG_MODVERSIONS=y`、`SMP`、`PREEMPT` 必须保持原样，
否则厂商预编译模块（`wlan_drv_gen3` / `wmt_drv` / `gps_drv` / `bt_drv` / `fmradio_drv` / `fpsgo`）加载不了。

## 怎么跑

1. Actions → `build-kernel` → Run workflow
2. `config` 选 `yxp_u39_vendor_defconfig`（先跑基线，确认 donor 树本身能编译）
3. 基线通过后，再选 `yxp_u39_kvm_defconfig` 出 KVM 内核
4. 下载 artifact `Image-*`（内含 `Image` + `.config`）

## 拿到 Image 之后（设备端）

```bash
# 原厂 ramdisk + 原厂 DTB 不动，只换 Image
python3 tools/repack_boot.py --image Image --out out/boot_kvm.img --check
# 只刷 boot，不碰 dtbo / lk / preloader
```

工作目录：`/storage/emulated/0/AI/kvm_work/`（含 28 个分区备份、boot.img 解析、重打包脚本）。

## 已知事实（实测）

- `gz1`/`gz2` 各 16 MB **全零** → 本机没有 GenieZone hypervisor，EL2 未被 MTK 占用
- `CONFIG_ARCH_MTK_PROJECT="yxp_738_pad"`（厂商项目代号）
- boot.img：header v1 / page 2048 / kernel = `Image.gz` + 尾部内嵌 DTB(110,572 B)
- `/proc/cmdline` 的 `bootopt=64S3,32N2,64N2` 与 `buildvariant=userdebug` 必须原样保留
