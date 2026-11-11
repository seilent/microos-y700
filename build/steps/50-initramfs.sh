#!/usr/bin/env bash
set -euo pipefail

mods=(/usr/lib/modules/*)
[[ ${#mods[@]} -eq 1 ]] || { echo "50-initramfs: expected one modules dir" >&2; exit 1; }
kver=${mods[0]##*/}
img=/usr/lib/modules/$kver/initramfs.img

kdir=/usr/lib/modules/$kver/kernel/drivers
omit=$(find "$kdir/gpu" "$kdir/pwm" "$kdir/video/backlight" -name '*.ko*' -printf '%f\n' | sed 's/\.ko.*//' | sort -u | tr '\n' ' ')

mkdir -p /var/roothome
dracut --no-hostonly --reproducible --add "ostree microos-ostree-remap" --omit-drivers "$omit" --force "$img" "$kver"

list=$(lsinitrd "$img")
builtin=$(cat "/usr/lib/modules/$kver/modules.builtin")
for m in erofs overlay btrfs sdhci-msm ufs-qcom; do
  grep -qE "/$m\.ko" <<< "$list" || grep -qE "/$m\.ko$" <<< "$builtin" || { echo "50-initramfs: $m missing" >&2; exit 1; }
done
for f in usr/lib/ostree/ostree-prepare-root usr/libexec/microos/prepare-root usr/bin/sh usr/bin/realpath usr/bin/mkdir \
  usr/lib/systemd/system/ostree-prepare-root.service.d/10-microos-remap.conf; do
  grep -qE " $f( |$)" <<< "$list" || { echo "50-initramfs: $f missing" >&2; exit 1; }
done
lsinitrd -f usr/lib/systemd/system/ostree-prepare-root.service.d/10-microos-remap.conf "$img" | grep -qx 'ExecStart=' \
  || { echo "50-initramfs: drop-in has no ExecStart= reset" >&2; exit 1; }
if grep -qE "/kernel/drivers/(gpu|pwm|video/backlight)/.*\.ko" <<< "$list"; then
  echo "50-initramfs: GPU, PWM or backlight module in the initramfs" >&2
  exit 1
fi

base=49006320
size=$(stat -c %s "$img")
echo "50-initramfs: $img $size bytes, base $base"
(( size - base <= 4194304 )) || { echo "50-initramfs: initramfs grew $((size - base)) bytes over $base, limit 4194304" >&2; exit 1; }
