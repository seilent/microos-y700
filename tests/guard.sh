#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tree=${MICROOS_TREE:-$here/../system_files}
mod=$tree/usr/lib/dracut/modules.d/92microos-y700-guard
guard=$mod/microos-guard
initrdlog=$mod/microos-initrd-log
mtest=$tree/usr/libexec/microos/microos-test
mfail=$tree/usr/libexec/microos/microos-fail
efilog=$tree/usr/libexec/microos/microos-efi-log
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

export FAKE_STATE=$tmp/fake PATH=$here/guard/bin:$PATH MICROOS_SDAM_LIB=$tree/usr/libexec/microos/microos-sdam
id=0123456789ab
nv=$tmp/nvmem
efi=$tmp/efi

reset() {
  rm -rf "$nv" "$efi" "$FAKE_STATE" "$tmp/run"
  mkdir -p "$nv/spmi_sdam0" "$nv/spmi_sdam1" "$tmp/dt/pmic@0/nvram@7000" "$tmp/dt/pmic@0/nvram@7100" "$efi" "$FAKE_STATE"
  head -c 256 /dev/zero > "$nv/spmi_sdam0/nvmem"
  head -c 256 /dev/zero > "$nv/spmi_sdam1/nvmem"
  ln -s "$tmp/dt/pmic@0/nvram@7000" "$nv/spmi_sdam0/of_node"
  ln -s "$tmp/dt/pmic@0/nvram@7100" "$nv/spmi_sdam1/of_node"
}
cmdline() { echo "root=PARTLABEL=microos rootwait ro init=/init $* microos.id=$id" > "$tmp/cmdline"; }
noid() { echo "root=PARTLABEL=microos $*" > "$tmp/cmdline"; }
run_guard() {
  env MICROOS_CMDLINE="$tmp/cmdline" MICROOS_EFI_DIR="$efi" MICROOS_NVMEM_ROOT="$nv" MICROOS_INITRD_ID="$tmp/initrd-id" \
    sh "$guard" 2> "$tmp/guard.err"
}
preset_of() { od -An -tx1 -j72 -N1 "$nv/$1/nvmem" | tr -d ' \n'; }
nonzero() { tr -d '\0' < "$nv/$1/nvmem" | wc -c; }
attempts() { cat "$efi/microos/boot-attempts" 2> /dev/null || echo none; }
echo "7.2.12-microos 20261111T000000Z" > "$tmp/initrd-id"

for w in "" 1 noguard bootloader panic emergency wdhang gptdump; do
  name=${w:-production}
  reset
  cmdline ${w:+microos.test=$w}
  run_guard || fail "guard $name: exit $?: $(cat "$tmp/guard.err")"
  if [[ $w == 1 ]]; then
    [[ $(preset_of spmi_sdam1) == 04 && $(nonzero spmi_sdam1) == 1 ]] || fail "guard 1: preset byte $(preset_of spmi_sdam1)"
  else
    [[ $(nonzero spmi_sdam1) == 0 ]] || fail "guard $name wrote the preset"
  fi
  [[ $(nonzero spmi_sdam0) == 0 ]] || fail "guard $name wrote another SDAM"
  if [[ $w == noguard || $w == gptdump ]]; then
    [[ $(attempts) == none ]] || fail "guard $name counted: $(attempts)"
  else
    [[ $(attempts) == "$id 1" ]] || fail "guard $name count: $(attempts)"
  fi
  [[ $(tail -n 1 "$efi/logs/guard.txt") == "initrd=7.2.12-microos 20261111T000000Z id=$id test=${w:-none} count="* ]] \
    || fail "guard $name log: $(tail -n 1 "$efi/logs/guard.txt")"
done

reset
cmdline
run_guard
run_guard
[[ $(attempts) == "$id 2" ]] || fail "second boot count: $(attempts)"
cmdline microos.test=noguard
run_guard
[[ $(attempts) == "$id 2" ]] || fail "noguard changed the count: $(attempts)"
echo "aaaaaaaaaaaa 7" > "$efi/microos/boot-attempts"
cmdline
run_guard
[[ $(attempts) == "$id 1" ]] || fail "another id did not start at 0: $(attempts)"
echo "$id x" > "$efi/microos/boot-attempts"
run_guard
[[ $(attempts) == "$id 1" ]] || fail "a bad count did not start at 0: $(attempts)"
noid
run_guard || fail "guard without microos.id failed"
[[ $(attempts) == "$id 1" ]] || fail "boot without microos.id counted: $(attempts)"
for i in $(seq 1 210); do echo "line $i"; done > "$efi/logs/guard.txt"
cmdline
run_guard
(( $(wc -l < "$efi/logs/guard.txt") == 200 )) || fail "guard.txt not trimmed to 200 lines"

reset
printf '\001' | dd of="$nv/spmi_sdam1/nvmem" bs=1 seek=72 conv=notrunc status=none
cmdline microos.test=1
run_guard || fail "guard 1 with bit 0 set: $(cat "$tmp/guard.err")"
[[ $(preset_of spmi_sdam1) == 05 && $(nonzero spmi_sdam1) == 1 ]] || fail "guard 1 with bit 0 set: preset byte $(preset_of spmi_sdam1)"

reset
rm "$nv/spmi_sdam1/of_node"
cmdline microos.test=1
run_guard || fail "guard 1 without the SDAM failed"
[[ $(cat "$tmp/guard.err") == *"no fastboot preset"* ]] || fail "missing SDAM not reported: $(cat "$tmp/guard.err")"
[[ $(nonzero spmi_sdam0) == 0 && $(nonzero spmi_sdam1) == 0 ]] || fail "guard 1 wrote an SDAM with no nvram@7100 node"
[[ $(attempts) == "$id 1" ]] || fail "guard 1 without the SDAM did not count"

reset
cmdline
if env MICROOS_CMDLINE="$tmp/cmdline" MICROOS_EFI_DEV="$tmp/missing" MICROOS_NVMEM_ROOT="$nv" sh "$guard" 2> /dev/null; then
  fail "guard passed without microos_efi"
fi

mkdir -p "$efi/logs"
for i in 1 2 3 4 5 6 7 8; do : > "$efi/logs/initrd-$i.txt"; done
MICROOS_EFI_DIR=$efi sh "$initrdlog" || fail "initrd log failed"
[[ -s $efi/logs/initrd-9.txt && ! -e $efi/logs/initrd-1.txt && -e $efi/logs/initrd-2.txt ]] \
  || fail "initrd log rotation: $(ls "$efi/logs" | tr '\n' ' ')"

sysblock=$tmp/sys/block
devdir=$tmp/dev
platform=$tmp/platform
mkdir -p "$sysblock/sda/queue" "$sysblock/sdb/queue" "$devdir" "$platform/soc@0/1d84000.ufshc/attributes"
echo 4096 > "$sysblock/sda/queue/logical_block_size"
echo 160 > "$sysblock/sda/size"
echo 512 > "$sysblock/sdb/queue/logical_block_size"
echo 40 > "$sysblock/sdb/size"
for i in $(seq 0 19); do printf "%-4096s" "sda$i"; done > "$devdir/sda"
for i in $(seq 0 39); do printf "%-512s" "sdb$i"; done > "$devdir/sdb"
echo 2 > "$platform/soc@0/1d84000.ufshc/attributes/boot_lun_enabled"
run_test() {
  env MICROOS_EFI="$efi" MICROOS_SYSBLOCK="$sysblock" MICROOS_DEVDIR="$devdir" MICROOS_PLATFORM="$platform" \
    MICROOS_SYSRQ="$tmp/sysrq" MICROOS_WATCHDOG="$tmp/watchdog" "$mtest" "$1" > /dev/null 2>&1
}
for w in bootloader panic emergency wdhang gptdump; do
  reset
  rm -f "$tmp/sysrq" "$tmp/watchdog"
  r=0
  run_test "$w" || r=$?
  [[ $(nonzero spmi_sdam0) == 0 && $(nonzero spmi_sdam1) == 0 ]] || fail "case $w wrote the preset"
  log=$(cat "$FAKE_STATE/systemctl.log" 2> /dev/null || true)
  case $w in
    bootloader) [[ $log == "systemctl reboot --reboot-argument=bootloader" ]] || fail "case bootloader: $log" ;;
    panic) [[ $(cat "$tmp/sysrq") == c && $r != 0 ]] || fail "case panic: sysrq $(cat "$tmp/sysrq" 2> /dev/null), exit $r" ;;
    emergency) [[ $log == "systemctl --no-block start emergency.target" ]] || fail "case emergency: $log" ;;
    wdhang)
      [[ $(cat "$FAKE_STATE/sleep.log") == "sleep infinity fd3=$tmp/watchdog" ]] || fail "case wdhang: $(cat "$FAKE_STATE/sleep.log")"
      [[ ! -s $tmp/watchdog ]] || fail "case wdhang wrote to the watchdog"
      ;;
    gptdump)
      d=$efi/logs/gpt-1
      [[ $log == "systemctl reboot" ]] || fail "case gptdump: $log"
      [[ $(sha256sum < "$d/sda-primary.bin") == $(head -c $((6 * 4096)) "$devdir/sda" | sha256sum) ]] || fail "sda primary"
      [[ $(sha256sum < "$d/sda-backup.bin") == $(tail -c $((5 * 4096)) "$devdir/sda" | sha256sum) ]] || fail "sda backup"
      [[ $(sha256sum < "$d/sdb-primary.bin") == $(head -c $((6 * 512)) "$devdir/sdb" | sha256sum) ]] || fail "sdb primary"
      [[ $(sha256sum < "$d/sdb-backup.bin") == $(tail -c $((5 * 512)) "$devdir/sdb" | sha256sum) ]] || fail "sdb backup"
      [[ $(cat "$d/boot_lun_enabled.txt") == "soc@0/1d84000.ufshc/attributes/boot_lun_enabled 2" ]] || fail "boot_lun_enabled: $(cat "$d/boot_lun_enabled.txt")"
      [[ $(cat "$d/disks.txt") == $'sda logical_block_size=4096 blocks=20\nsdb logical_block_size=512 blocks=40' ]] || fail "disks.txt: $(cat "$d/disks.txt")"
      (cd "$d" && sha256sum -c --quiet SHA256SUMS) || fail "gpt SHA256SUMS"
      run_test gptdump
      [[ -d $efi/logs/gpt-2 ]] || fail "second gptdump did not use gpt-2"
      ;;
  esac
done

slotconf=$tmp/slot.conf
run_fail() {
  env MICROOS_EFI="$efi" MICROOS_RUNDIR="$tmp/run" MICROOS_CMDLINE="$tmp/cmdline" MICROOS_SLOT_CONF="$slotconf" \
    MICROOS_EFI_LOG="$efilog" MICROOS_NVMEM_ROOT="$nv" "$mfail" "$@" > /dev/null 2> "$tmp/fail.err"
}
reboots() { cat "$FAKE_STATE/systemctl.log" 2> /dev/null | grep -c '^systemctl reboot$' || true; }
bootloader_reboots() { cat "$FAKE_STATE/systemctl.log" 2> /dev/null | grep -c '^systemctl reboot --reboot-argument=bootloader$' || true; }
reset
cmdline
mkdir -p "$efi/microos"
printf 'MICROOS_SLOT_WRITE=1\nMICROOS_BOOT_TRIES=3\n' > "$slotconf"
echo "$id 3" > "$efi/microos/boot-attempts"
mkdir -p "$tmp/run"
echo "$id" > "$tmp/run/boot-confirmed"
run_fail deadline || fail "deadline after boot ok failed"
[[ $(reboots) == 0 ]] || fail "deadline acted on a confirmed boot"
rm "$tmp/run/boot-confirmed"
run_fail deadline
[[ $(cat "$tmp/fail.err") == *"no $tmp/run/boot-confirmed"* ]] || fail "deadline reason: $(cat "$tmp/fail.err")"
[[ $(reboots) == 1 && $(attempts) == "$id 3" ]] || fail "deadline at 3 tries: reboots $(reboots), $(attempts)"
[[ $(cat "$tmp/fail.err") == *"plain reboot, the ABL retry budget decides"* ]] || fail "deadline at 3 tries: $(cat "$tmp/fail.err")"
[[ $(cat "$efi/logs/deadline-1.txt") == "journal of this boot" ]] || fail "deadline log"
reset
cmdline
mkdir -p "$efi/microos"
echo "$id 2" > "$efi/microos/boot-attempts"
run_fail deadline
[[ $(reboots) == 1 && $(attempts) == "$id 2" ]] || fail "deadline at 2 tries"
echo "$id 3" > "$efi/microos/boot-attempts"
printf 'MICROOS_SLOT_WRITE=0\nMICROOS_BOOT_TRIES=3\n' > "$slotconf"
run_fail emergency
[[ $(reboots) == 2 && $(bootloader_reboots) == 0 && $(attempts) == "$id 3" && $(nonzero spmi_sdam1) == 0 ]] \
  || fail "production image at 3 tries: reboots $(reboots), bootloader $(bootloader_reboots), preset $(preset_of spmi_sdam1)"
[[ -s $efi/logs/emergency-1.txt ]] || fail "emergency log"
rm -f "$FAKE_STATE/systemctl.log"
cmdline microos.test=1
run_fail emergency
[[ $(reboots) == 0 && $(bootloader_reboots) == 1 && $(attempts) == "$id 3" && $(preset_of spmi_sdam1) == 04 ]] \
  || fail "test image at 3 tries: reboots $(reboots), bootloader $(bootloader_reboots), preset $(preset_of spmi_sdam1)"
rm "$nv/spmi_sdam1/of_node"
printf '\000' | dd of="$nv/spmi_sdam1/nvmem" bs=1 seek=72 conv=notrunc status=none
run_fail emergency
[[ $(bootloader_reboots) == 1 && $(reboots) == 1 && $(cat "$tmp/fail.err") == *"no fastboot preset"* ]] || fail "no SDAM: bootloader $(bootloader_reboots), plain $(reboots): $(cat "$tmp/fail.err")"
ln -s "$tmp/dt/pmic@0/nvram@7100" "$nv/spmi_sdam1/of_node"
echo "bbbbbbbbbbbb 5" > "$efi/microos/boot-attempts"
run_fail emergency
[[ $(bootloader_reboots) == 1 && $(reboots) == 2 ]] || fail "another id's count acted: bootloader $(bootloader_reboots)"

reset
mkdir -p "$efi/logs"
for i in $(seq 1 9); do : > "$efi/logs/boot-$i.txt"; done
log() { env MICROOS_EFI="$efi" MICROOS_RUNDIR="$tmp/run" "$efilog" boot; }
[[ $(log) == "$efi/logs/boot-10.txt" ]] || fail "boot log number"
[[ $(log) == "$efi/logs/boot-10.txt" ]] || fail "boot log of the same boot moved"
[[ $(ls "$efi/logs" | sort -V | tr '\n' ' ') == "boot-3.txt boot-4.txt boot-5.txt boot-6.txt boot-7.txt boot-8.txt boot-9.txt boot-10.txt " ]] \
  || fail "boot logs kept: $(ls "$efi/logs" | tr '\n' ' ')"

if (( rc == 0 )); then
  echo "guard: ok"
fi
exit "$rc"
