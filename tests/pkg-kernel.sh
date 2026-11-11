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
  PINCTRL_SM8650 SM_GCC_8650 SM_TCSRCC_8650 SM_DISPCC_8550 SM_GPUCC_8650 INTERCONNECT_QCOM_SM8650 QCOM_LLCC
  DRM DRM_KMS_HELPER DRM_DISPLAY_HELPER DRM_SCHED DRM_GPUVM DRM_EXEC DRM_MIPI_DSI
  DRM_MSM DRM_MSM_MDSS DRM_MSM_DPU DRM_MSM_DSI DRM_MSM_DSI_7NM_PHY DRM_MSM_DP DRM_DISPLAY_DSC_HELPER
  DRM_PANEL_NOVATEK_NT36523 BACKLIGHT_CLASS_DEVICE BACKLIGHT_KTZ8866 REGULATOR_AW37503 FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER
  I2C_QCOM_GENI QCOM_GPI_DMA SCSI_UFS_QCOM PHY_QCOM_QMP_UFS QCOM_PMIC_GLINK UCSI_PMIC_GLINK
  PHY_QCOM_QMP_COMBO DRM_AUX_BRIDGE DRM_AUX_HPD_BRIDGE TYPEC
  FTRACE TRACING EVENT_TRACING TRACEPOINTS PM_DEBUG PM_SLEEP_DEBUG HIDRAW NTSYNC LRU_GEN_ENABLED
  SECURITY_YAMA HOTPLUG_PCI_PCIE UCLAMP_TASK UCLAMP_TASK_GROUP CGROUP_BPF BPF_SYSCALL
  NETFILTER_NETLINK IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES IPV6_MULTIPLE_TABLES FIB_RULES
  EFI EFI_STUB PANIC_ON_OOPS DEVMEM NVMEM_SYSFS
  USB_CONFIGFS USB_LIBCOMPOSITE USB_F_ACM USB_F_NCM USB_CONFIGFS_ACM PHY_SNPS_EUSB2 PHY_NXP_PTN3222
)
for s in "${builtin[@]}"; do
  grep -qx "CONFIG_$s=y" "$kdir/config" || { echo "pkg-kernel: CONFIG_$s is not built in" >&2; exit 1; }
done

grep -qE '^CONFIG_LSM="([^"]*,)?yama(,[^"]*)?"$' "$kdir/config" || { echo "pkg-kernel: CONFIG_LSM lacks yama: $(grep '^CONFIG_LSM=' "$kdir/config")" >&2; exit 1; }
grep -qx 'CONFIG_PANIC_TIMEOUT=10' "$kdir/config" || { echo "pkg-kernel: CONFIG_PANIC_TIMEOUT is not 10: $(grep '^CONFIG_PANIC_TIMEOUT=' "$kdir/config")" >&2; exit 1; }

for m in snd-seq joydev hid-playstation hid-sony hid-nintendo xpad zram exfat ntfs3 nfnetlink_log btrfs nvmem_qcom-spmi-sdam \
  snd-soc-wcd939x novatek-nt36523; do
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
[[ $(fdtget "$abl" /chosen/framebuffer@d5100000 status) == okay ]] || { echo "pkg-kernel: abl dtb framebuffer" >&2; exit 1; }
[[ $(fdtget "$abl" /soc@0/spmi@c400000/pmic@0/nvram@7100 compatible) == qcom,spmi-sdam ]] || { echo "pkg-kernel: abl dtb sdam nvram@7100" >&2; exit 1; }
[[ $(fdtget "$abl" /aliases serial1) == /soc@0/geniqup@8c0000/serial@898000 ]] || { echo "pkg-kernel: abl dtb serial1 alias" >&2; exit 1; }
[[ $(fdtget -p "$abl" /__symbols__ | wc -l) -ge 1634 ]] || { echo "pkg-kernel: abl dtb symbols" >&2; exit 1; }
mdss=$(fdtget -t x "$abl" /soc@0/display-subsystem@ae00000 phandle)
splash=$(fdtget -t x "$abl" /reserved-memory/splash_region phandle)
[[ $(fdtget -t x "$abl" /reserved-memory/splash_region iommu-addresses) == "$mdss 0 d5100000 0 2b00000" ]] || { echo "pkg-kernel: abl dtb splash iommu-addresses" >&2; exit 1; }
[[ $(fdtget -t x "$abl" /soc@0/display-subsystem@ae00000 memory-region) == "$splash" ]] || { echo "pkg-kernel: abl dtb mdss memory-region" >&2; exit 1; }

for s in lenovo,tb321fu-boe-nt36523 lenovo,tb321fu-csot-nt36523 kinetic,ovp-microvolt kinetic,inductor-nanohenry; do
  grep -qaF "$s" "$kdir/vmlinuz" || { echo "pkg-kernel: vmlinuz lacks $s" >&2; exit 1; }
done

main=$kdir/dtb/qcom/sm8650-lenovo-tb321fu.dtb
csot=$kdir/dtb/qcom/sm8650-lenovo-tb321fu-csot.dtb
bl=/soc@0/geniqup@8c0000/i2c@888000/backlight@11
disp=/soc@0/display-subsystem@ae00000
panel=$disp/dsi@ae94000/panel@0
for d in "$main" "$csot" "$abl"; do
  n=$(basename "$d")
  for dsi in dsi@ae94000 dsi@ae96000; do
    fdtget "$d" "$disp/$dsi" qcom,dual-dsi-mode > /dev/null && fdtget "$d" "$disp/$dsi" qcom,sync-dual-dsi > /dev/null ||
      { echo "pkg-kernel: $n $dsi is not dual sync DSI" >&2; exit 1; }
    [[ $(fdtget "$d" "$disp/$dsi/ports/port@1/endpoint" data-lanes) == "0 1 2" ]] || { echo "pkg-kernel: $n $dsi data-lanes" >&2; exit 1; }
  done
  fdtget "$d" "$disp/dsi@ae94000" qcom,master-dsi > /dev/null || { echo "pkg-kernel: $n dsi0 is not the master" >&2; exit 1; }
  ! fdtget "$d" "$disp/dsi@ae96000" qcom,master-dsi > /dev/null 2>&1 || { echo "pkg-kernel: $n dsi1 is a master" >&2; exit 1; }
  for phy in phy@ae95000 phy@ae97000; do
    [[ $(fdtget "$d" "$disp/$phy" phy-type) == 11 ]] || { echo "pkg-kernel: $n $phy is not C-PHY" >&2; exit 1; }
  done
  for sup in vddio-supply vci-supply vdd-supply; do
    fdtget "$d" "$panel" "$sup" > /dev/null || { echo "pkg-kernel: $n panel has no $sup" >&2; exit 1; }
  done
  [[ $(fdtget -t x "$d" "$panel" vddio-supply) == "$(fdtget -t x "$d" /regulator-panel-iovdd phandle)" ]] ||
    { echo "pkg-kernel: $n panel vddio is not the IOVDD switch" >&2; exit 1; }
  for node in /soc@0/clock-controller@af00000 /soc@0/display-subsystem@ae00000 "$bl" /soc@0/geniqup@8c0000/i2c@888000/regulator@3e; do
    [[ $(fdtget -d okay "$d" "$node" status) == okay ]] || { echo "pkg-kernel: $n $node is off" >&2; exit 1; }
  done
  v="$(fdtget "$d" "$bl" kinetic,ovp-microvolt) $(fdtget "$d" "$bl" kinetic,inductor-nanohenry)"
  v+=" $(fdtget "$d" "$bl" led-max-microamp) $(fdtget "$d" "$bl" current-num-sinks)"
  [[ $v == "34000000 4700 15600 4" ]] || { echo "pkg-kernel: $n ktz8866 settings $v" >&2; exit 1; }
done
[[ $(fdtget "$main" "$panel" compatible) == "lenovo,tb321fu-boe-nt36523 novatek,nt36523" ]] || { echo "pkg-kernel: main dtb panel" >&2; exit 1; }
[[ $(fdtget "$abl" "$panel" compatible) == "lenovo,tb321fu-boe-nt36523 novatek,nt36523" ]] || { echo "pkg-kernel: abl dtb panel" >&2; exit 1; }
[[ $(fdtget "$csot" "$panel" compatible) == "lenovo,tb321fu-csot-nt36523 novatek,nt36523" ]] || { echo "pkg-kernel: csot dtb panel" >&2; exit 1; }

spi=/soc@0/geniqup@ac0000/spi@a90000
ts=$spi/touchscreen@0
for d in "$main" "$csot" "$abl"; do
  n=$(basename "$d")
  [[ $(fdtget -d okay "$d" "$spi" status) == okay ]] || { echo "pkg-kernel: $n spi4 is off" >&2; exit 1; }
  [[ $(fdtget "$d" "$ts" compatible) == novatek,nt36523-ts ]] || { echo "pkg-kernel: $n touchscreen compatible" >&2; exit 1; }
  [[ $(fdtget -t x "$d" "$ts" panel) == "$(fdtget -t x "$d" "$panel" phandle)" ]] || { echo "pkg-kernel: $n touchscreen panel" >&2; exit 1; }
  v="$(fdtget "$d" "$ts" touchscreen-size-x) $(fdtget "$d" "$ts" touchscreen-size-y) $(fdtget "$d" "$ts" touchscreen-x-mm)"
  v+=" $(fdtget "$d" "$ts" touchscreen-y-mm) $(fdtget "$d" "$ts" spi-max-frequency)"
  [[ $v == "16000 25600 118 190 9600000" ]] || { echo "pkg-kernel: $n touchscreen settings $v" >&2; exit 1; }
  fdtget "$d" "$ts" touchscreen-inverted-x > /dev/null && fdtget "$d" "$ts" touchscreen-swapped-x-y > /dev/null ||
    { echo "pkg-kernel: $n touchscreen orientation" >&2; exit 1; }
  ! fdtget "$d" "$ts" touchscreen-inverted-y > /dev/null 2>&1 || { echo "pkg-kernel: $n touchscreen inverts y" >&2; exit 1; }
done
fw=qcom/sm8650/lenovo/tb321fu/novatek_ts
[[ $(fdtget "$main" "$ts" firmware-name) == "${fw}_boe_fw.bin" ]] || { echo "pkg-kernel: main dtb touch firmware" >&2; exit 1; }
[[ $(fdtget "$abl" "$ts" firmware-name) == "${fw}_boe_fw.bin" ]] || { echo "pkg-kernel: abl dtb touch firmware" >&2; exit 1; }
[[ $(fdtget "$csot" "$ts" firmware-name) == "${fw}_csot_fw.bin" ]] || { echo "pkg-kernel: csot dtb touch firmware" >&2; exit 1; }

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
