#!/usr/bin/env bash
set -euo pipefail

out=${1:?usage: pkg-kernel.sh <rpmdir>}
here=$(cd "$(dirname "$0")" && pwd)
rpm=$(find "$out" -name 'microos-kernel-[0-9]*.aarch64.rpm' | head -1)
[[ -n $rpm ]] || { echo "pkg-kernel: no microos-kernel rpm in $out" >&2; exit 1; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
rpm2cpio "$rpm" > "$root/kernel.cpio"
(cd "$root" && cpio -idm --quiet < kernel.cpio)
rm "$root/kernel.cpio"

mods=("$root"/usr/lib/modules/*)
[[ ${#mods[@]} -eq 1 && -d ${mods[0]} ]] || { echo "pkg-kernel: expected one modules dir" >&2; exit 1; }
kdir=${mods[0]}
[[ $(basename "$kdir") == *-microos ]] || { echo "pkg-kernel: modules dir $(basename "$kdir")" >&2; exit 1; }
[[ $(head -c 64 "$kdir/vmlinuz" | tail -c 8 | od -An -c | tr -d ' ') == ARMd* ]] || { echo "pkg-kernel: vmlinuz is not a raw arm64 Image" >&2; exit 1; }
dtbs=$(find "$kdir/dtb" -name '*.dtb' | sort)
want=$(printf '%s\n' "$kdir/dtb/qcom/sm8650-lenovo-tb321fu-abl.dtb" "$kdir/dtb/qcom/sm8650-lenovo-tb321fu-csot.dtb" "$kdir/dtb/qcom/sm8650-lenovo-tb321fu.dtb")
[[ $dtbs == "$want" ]] || { echo "pkg-kernel: unexpected dtb set: $dtbs" >&2; exit 1; }

builtin=(
  PINCTRL_SM8650 SM_GCC_8650 SM_TCSRCC_8650 SM_DISPCC_8550 INTERCONNECT_QCOM_SM8650 QCOM_LLCC
  DRM DRM_KMS_HELPER DRM_DISPLAY_HELPER DRM_SCHED DRM_GPUVM DRM_EXEC DRM_MIPI_DSI
  DRM_MSM DRM_MSM_MDSS DRM_MSM_DPU DRM_MSM_DSI DRM_MSM_DSI_7NM_PHY DRM_MSM_DP DRM_DISPLAY_DSC_HELPER
  DRM_PANEL_NOVATEK_NT36523 BACKLIGHT_CLASS_DEVICE BACKLIGHT_KTZ8866 FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER
  I2C_QCOM_GENI QCOM_GPI_DMA SCSI_UFS_QCOM PHY_QCOM_QMP_UFS QCOM_PMIC_GLINK UCSI_PMIC_GLINK TYPEC_MUX_PS5169
  PHY_QCOM_QMP_COMBO DRM_AUX_BRIDGE DRM_AUX_HPD_BRIDGE TYPEC TYPEC_TCPM
  FTRACE TRACING EVENT_TRACING TRACEPOINTS PM_DEBUG PM_SLEEP_DEBUG HIDRAW NTSYNC LRU_GEN_ENABLED
  SECURITY_YAMA HOTPLUG_PCI_PCIE UCLAMP_TASK UCLAMP_TASK_GROUP CGROUP_BPF BPF_SYSCALL
  ANDROID_BINDER_IPC ANDROID_BINDERFS NETFILTER_NETLINK IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES IPV6_MULTIPLE_TABLES FIB_RULES
  EFI EFI_STUB
)
for s in "${builtin[@]}"; do
  grep -qx "CONFIG_$s=y" "$kdir/config" || { echo "pkg-kernel: CONFIG_$s is not built in" >&2; exit 1; }
done

grep -qE '^CONFIG_LSM="([^"]*,)?yama(,[^"]*)?"$' "$kdir/config" || { echo "pkg-kernel: CONFIG_LSM lacks yama: $(grep '^CONFIG_LSM=' "$kdir/config")" >&2; exit 1; }
grep -qx 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"' "$kdir/config" || { echo "pkg-kernel: CONFIG_ANDROID_BINDER_DEVICES is not the Kconfig default: $(grep '^CONFIG_ANDROID_BINDER_DEVICES=' "$kdir/config")" >&2; exit 1; }

for m in snd-seq joydev hid-playstation hid-sony hid-nintendo xpad zram exfat ntfs3 nfnetlink_log; do
  find "$kdir" -name "$m.ko*" | grep -q . || { echo "pkg-kernel: module $m missing" >&2; exit 1; }
done

for d in $dtbs; do
  "$here/pkg-kernel/dts-drivers.sh" "$d" "$kdir/config"
done

abl=$kdir/dtb/qcom/sm8650-lenovo-tb321fu-abl.dtb
[[ $(fdtget -t x "$abl" / qcom,msm-id) == "241 20000" ]] || { echo "pkg-kernel: abl dtb msm-id" >&2; exit 1; }
[[ $(fdtget -t x "$abl" / qcom,board-id) == "0 0" ]] || { echo "pkg-kernel: abl dtb board-id" >&2; exit 1; }
[[ $(fdtget "$abl" / region_country) == PRC ]] || { echo "pkg-kernel: abl dtb region_country" >&2; exit 1; }
[[ $(fdtget -t x "$abl" /reserved-memory/splash_region reg) == "0 d5100000 0 2b00000" ]] || { echo "pkg-kernel: abl dtb splash_region" >&2; exit 1; }
[[ $(fdtget -p "$abl" /__symbols__ | wc -l) -ge 1634 ]] || { echo "pkg-kernel: abl dtb symbols" >&2; exit 1; }
mdss=$(fdtget -t x "$abl" /soc@0/display-subsystem@ae00000 phandle)
splash=$(fdtget -t x "$abl" /reserved-memory/splash_region phandle)
[[ $(fdtget -t x "$abl" /reserved-memory/splash_region iommu-addresses) == "$mdss 0 d5100000 0 2b00000" ]] || { echo "pkg-kernel: abl dtb splash iommu-addresses" >&2; exit 1; }
[[ $(fdtget -t x "$abl" /soc@0/display-subsystem@ae00000 memory-region) == "$splash" ]] || { echo "pkg-kernel: abl dtb mdss memory-region" >&2; exit 1; }

dtbo=$kdir/dtb/qcom/sm8650-lenovo-tb321fu-dtbo.img
[[ -f $dtbo ]] || { echo "pkg-kernel: dtbo image missing" >&2; exit 1; }
read -r magic _ hsize esize count eoff _ <<<"$(od -An -v -tx4 --endian=big -w28 -N28 "$dtbo")"
[[ "$magic $hsize $esize $count $eoff" == "d7b7ab1e 00000020 00000020 00000001 00000020" ]] || { echo "pkg-kernel: dtbo header" >&2; exit 1; }
read -r dsize doff <<<"$(od -An -v -tu4 --endian=big -j32 -N8 "$dtbo")"
work=$root/dtbo
mkdir "$work"
dd if="$dtbo" of="$work/o.dtb" bs=1 skip="$doff" count="$dsize" status=none
[[ $(fdtget -t x "$work/o.dtb" / qcom,msm-id) == "22d 20000 22d 10000 241 20000 241 10000" ]] || { echo "pkg-kernel: dtbo msm-id" >&2; exit 1; }
[[ $(fdtget -t x "$work/o.dtb" / qcom,board-id) == "3000b 0" ]] || { echo "pkg-kernel: dtbo board-id" >&2; exit 1; }
! fdtget "$work/o.dtb" / compatible >/dev/null 2>&1 || { echo "pkg-kernel: dtbo sets the root compatible" >&2; exit 1; }
! fdtget "$work/o.dtb" / model >/dev/null 2>&1 || { echo "pkg-kernel: dtbo sets the root model" >&2; exit 1; }
fdtoverlay -i "$abl" -o "$work/applied.dtb" "$work/o.dtb"
[[ $(fdtget "$work/applied.dtb" / compatible) == "lenovo,tb321fu qcom,sm8650" ]] || { echo "pkg-kernel: abl dtb compatible after the dtbo" >&2; exit 1; }
echo "pkg-kernel: $(basename "$rpm") ok"
