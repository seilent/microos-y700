#!/usr/bin/env bash
set -euo pipefail

fail() { echo "image: $*" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mods=(/usr/lib/modules/*)
[[ ${#mods[@]} -eq 1 && -d ${mods[0]} ]] || fail "expected one modules dir, found ${mods[*]}"
kver=${mods[0]##*/}
rpm -q microos-kernel >/dev/null || fail "microos-kernel not installed"
[[ -z $(rpm -qa 'kernel*') ]] || fail "Fedora kernel rpms left: $(rpm -qa 'kernel*' | tr '\n' ' ')"
[[ -z $(rpm -qa 'fedora-release*') ]] || fail "fedora-release rpms left"
rpm -q generic-release generic-logos >/dev/null || fail "generic-release or generic-logos missing"

for kv in ID=microos NAME=MicroOS ID_LIKE=fedora VERSION_ID=44 DEFAULT_HOSTNAME=microos \
  HOME_URL=https://github.com/seilent/microos-y700; do
  grep -qx "$kv" /usr/lib/os-release || fail "os-release lacks $kv"
done
grep -qx "$(cat /usr/lib/microos/version)" /usr/lib/os-release || fail "version file and os-release differ"
[[ $(readlink /etc/os-release) == ../usr/lib/os-release ]] || fail "/etc/os-release is not the relative symlink"

rpm -q android-tools btrfs-progs dosfstools jq util-linux rsync dnsmasq python3 >/dev/null || fail "base rpms missing"
for c in mkbootimg unpack_bootimg avbtool skopeo jq flock python3 btrfs mkfs.vfat rsync dnsmasq sshd NetworkManager sudo; do
  command -v "$c" >/dev/null || fail "$c missing"
done
grep -qx 'install_weak_deps=False' /etc/dnf/libdnf5.conf.d/10-microos.conf || fail "10-microos.conf does not turn off weak deps"
[[ -z $(rpm -qa '*-debuginfo' '*-debugsource') ]] || fail "debug rpms installed: $(rpm -qa '*-debuginfo' '*-debugsource' | tr '\n' ' ')"
own=$(rpm -qa --qf '%{NAME}\t%{VENDOR}\n' | awk -F'\t' '$2 == "MicroOS" && $1 != "microos-kernel" { print $1 }')
[[ -z $own ]] || fail "MicroOS rpms other than microos-kernel: $(tr '\n' ' ' <<< "$own")"
for p in qbootctl gamescope gamescope-session inputplumber steamos-manager microset mangohud lsfg-vk hexagonrpc microos-eq \
  libfreeaptx pipewire-codec-aptx sddm microos-android-guestos microos-steam-seed; do
  ! rpm -q "$p" >/dev/null 2>&1 || fail "$p is installed"
done

for u in bootloader-update.service systemd-repart.service systemd-backlight@.service systemd-hibernate.service systemd-hybrid-sleep.service \
  systemd-suspend-then-hibernate.service bootc-fetch-apply-updates.timer bootc-generic-growpart.service \
  microos-update-check.timer; do
  [[ $(readlink "/etc/systemd/system/$u") == /dev/null ]] || fail "$u is not masked"
done
[[ -z $(compgen -G '/usr/lib/repart.d/*') ]] || fail "repart.d holds definitions: $(ls /usr/lib/repart.d)"
[[ $(readlink /etc/systemd/user/mpris-proxy.service) == /dev/null ]] || fail "user mpris-proxy.service is not masked"

tests=(microos-test-bootloader.service microos-test-emergency.service microos-test-gptdump.service microos-test-panic.service
  microos-test-wdhang.service)
want=$(printf '%s\n' microos-boot-ok.service microos-provision.service microos-update-applied.service microos-update.service \
  microos-update-check.service microos-update-check.timer microos-boot-deadline.service microos-boot-deadline.timer \
  microos-bootlog-efi.path microos-bootlog-efi.service microos-grow-root.service microos-usb-console.service "${tests[@]}")
units=()
for u in /usr/lib/systemd/system/microos-*; do
  [[ -f $u ]] && units+=("$u")
done
got=$(printf '%s\n' "${units[@]##*/}" | LC_ALL=C sort)
[[ $got == "$(LC_ALL=C sort <<< "$want")" ]] || fail "MicroOS units: $(tr '\n' ' ' <<< "$got")"
for u in microos-boot-ok.service microos-provision.service microos-update-applied.service microos-boot-deadline.timer \
  microos-bootlog-efi.path microos-grow-root.service microos-usb-console.service "${tests[@]}"; do
  [[ $(systemctl is-enabled "$u") == enabled ]] || fail "$u is not enabled"
done
[[ -L /etc/systemd/system/multi-user.target.wants/microos-bootlog-efi.path ]] || fail "microos-bootlog-efi.path is not wanted by multi-user.target"
[[ $(systemctl is-enabled microos-bootlog-efi.service) == static ]] || fail "microos-bootlog-efi.service is not static"
for u in "${tests[@]}"; do
  w=${u#microos-test-}
  systemctl cat "$u" | grep -qx "ConditionKernelCommandLine=microos.test=${w%.service}" || fail "$u has no microos.test condition"
done
[[ $(systemctl is-enabled microos-update-check.timer) == masked ]] || fail "microos-update-check.timer is not masked"
[[ ! -e /usr/lib/systemd/user-preset/50-microos.preset && -z $(compgen -G '/usr/lib/systemd/user/microos-*') ]] \
  || fail "MicroOS user units in the image"
[[ $(< /usr/lib/systemd/system-preset/50-microos.preset) == 'enable microos-*' ]] || fail "50-microos.preset"

kept=(
  /etc/containers/policy.json
  /etc/containers/registries.d/ghcr-microos.yaml
  /etc/ssh/sshd_config.d/10-microos.conf
  /usr/bin/microos-update
  /usr/lib/NetworkManager/conf.d/10-microos.conf
  /usr/lib/NetworkManager/system-connections/microos-usb0.nmconnection
  /usr/lib/bootc/install/00-microos.toml
  /usr/lib/bootc/kargs.d/10-microos.toml
  /usr/lib/dracut/dracut.conf.d/90-microos.conf
  /usr/lib/dracut/modules.d/91microos-ostree-remap/module-setup.sh
  /usr/lib/dracut/modules.d/91microos-ostree-remap/prepare-root.conf
  /usr/lib/dracut/modules.d/92microos-y700-guard/cmdline.conf
  /usr/lib/dracut/modules.d/92microos-y700-guard/efi-device.conf
  /usr/lib/dracut/modules.d/92microos-y700-guard/emergency.conf
  /usr/lib/dracut/modules.d/92microos-y700-guard/microos-guard
  /usr/lib/dracut/modules.d/92microos-y700-guard/microos-guard.service
  /usr/lib/dracut/modules.d/92microos-y700-guard/microos-initrd-log
  /usr/lib/dracut/modules.d/92microos-y700-guard/module-setup.sh
  /usr/lib/dracut/modules.d/92microos-y700-guard/switch-root.conf
  /usr/lib/microos/boot-ok.conf
  /usr/lib/microos/bootimg.conf
  /usr/lib/microos/slot.conf
  /usr/lib/microos/stub.conf
  /usr/lib/microos/version
  /usr/lib/sysctl.d/60-microos-yama.conf
  /usr/lib/systemd/journald.conf.d/10-microos.conf
  /usr/lib/systemd/system-preset/50-microos.preset
  /usr/lib/systemd/system/emergency.service.d/10-microos.conf
  /usr/lib/systemd/system/microos-boot-deadline.service
  /usr/lib/systemd/system/microos-boot-deadline.timer
  /usr/lib/systemd/system/microos-boot-ok.service
  /usr/lib/systemd/system/microos-bootlog-efi.path
  /usr/lib/systemd/system/microos-bootlog-efi.service
  /usr/lib/systemd/system/microos-grow-root.service
  /usr/lib/systemd/system/microos-provision.service
  /usr/lib/systemd/system/microos-update-applied.service
  /usr/lib/systemd/system/microos-update-check.service
  /usr/lib/systemd/system/microos-update-check.timer
  /usr/lib/systemd/system/microos-test-bootloader.service
  /usr/lib/systemd/system/microos-test-emergency.service
  /usr/lib/systemd/system/microos-test-gptdump.service
  /usr/lib/systemd/system/microos-test-panic.service
  /usr/lib/systemd/system/microos-test-wdhang.service
  /usr/lib/systemd/system/microos-update.service
  /usr/lib/systemd/system/microos-usb-console.service
  /usr/lib/systemd/system/serial-getty@ttyGS0.service.d/10-microos.conf
  /usr/lib/systemd/system/sshd.service.d/10-microos.conf
  /usr/lib/sysusers.d/microos.conf
  /usr/lib/tmpfiles.d/microos.conf
  /usr/lib/udev/rules.d/90-microos-usb-console.rules
  /usr/libexec/microos/microos-boot-ok
  /usr/libexec/microos/microos-bootimg-build
  /usr/libexec/microos/microos-bootlog
  /usr/libexec/microos/microos-efi-log
  /usr/libexec/microos/microos-fail
  /usr/libexec/microos/microos-grow-root
  /usr/libexec/microos/microos-provision
  /usr/libexec/microos/microos-sdam
  /usr/libexec/microos/microos-slot
  /usr/libexec/microos/microos-test
  /usr/libexec/microos/microos-update-applied
  /usr/libexec/microos/microos-usb-console
  /usr/libexec/microos/prepare-root
  /usr/share/microos/avb/testkey_rsa4096.pem
  /usr/share/microos/keys/microos-backup.pub
  /usr/share/microos/keys/microos-next.pub
  /usr/share/microos/keys/microos.pub
)
for f in "${kept[@]}"; do
  [[ -f $f ]] || fail "$f missing"
done
ours=()
while IFS= read -r f; do
  rpm -qf "$f" >/dev/null 2>&1 || ours+=("$f")
done < <(find /usr /etc -xdev -path /usr/lib/modules -prune -o -path '*microos*' -type f -print \
  | grep -vxF /etc/dnf/libdnf5.conf.d/10-microos.conf | LC_ALL=C sort)
extra=$(LC_ALL=C comm -23 <(printf '%s\n' "${ours[@]}") <(printf '%s\n' "${kept[@]}" | LC_ALL=C sort))
[[ -z $extra ]] || fail "MicroOS files outside the M1 set: $(tr '\n' ' ' <<< "$extra")"
for f in /usr/bin/steam /usr/bin/steamvr /usr/bin/steamos-update /usr/bin/steamos-select-branch /usr/bin/steamos-session-select \
  /usr/bin/steamos-mandatory-update /usr/bin/steamos-polkit-helpers /usr/bin/jupiter-biosupdate \
  /usr/bin/jupiter-initial-firmware-update /usr/lib/hwsupport /usr/lib/android-sdk /usr/share/gamescope-session-plus \
  /etc/gamescope-session-plus /usr/share/inputplumber /usr/share/steamos-manager; do
  [[ ! -e $f ]] || fail "$f is in the image"
done
ucm=$(compgen -G '/usr/share/alsa/ucm2/*/sm8250/PocketMICRO2*' || true)
[[ -z $ucm ]] || fail "PM2 UCM files in the image: $ucm"
! grep -qs '^micro:' /etc/subuid /etc/subgid || fail "micro has subordinate ids"
words=$(grep -lIiE 'PocketMICRO2|sm8250|ayaneo|aya-keys|fastrpc-sdsp|mmcblk' "${ours[@]}" || true)
[[ -z $words ]] || fail "MicroOS files name PM2 hardware: $(tr '\n' ' ' <<< "$words")"

yama=/usr/lib/sysctl.d/60-microos-yama.conf
grep -qx 'kernel.yama.ptrace_scope = 1' "$yama" || fail "$yama does not set ptrace_scope 1"
last=$(/usr/lib/systemd/systemd-sysctl --cat-config | awk '/^# \/[^ ]*\.conf( -> |$)/ { f = $2 } /^-?kernel[.\/]yama[.\/]ptrace_scope[[:space:]]*=/ { l = f " " $0 } END { print l }')
[[ $last == "$yama kernel.yama.ptrace_scope = 1" ]] || fail "the last ptrace_scope setting is not $yama: $last"

[[ $(< /usr/lib/bootc/kargs.d/10-microos.toml) == 'match-architectures = ["aarch64"]
kargs = [
  "firmware_class.path=/var/lib/microos/fw",
  "loglevel=4",
  "regulator_ignore_unused",
  "clk_ignore_unused",
  "pd_ignore_unused",
  "reboot=cold",
  "cpuidle.off=1",
]' ]] || fail "10-microos.toml kargs"
[[ $(< /usr/lib/microos/slot.conf) == $'MICROOS_SLOT_WRITE=0\nMICROOS_BOOT_TRIES=3' ]] || fail "slot.conf does not keep slot writes off"
[[ $(sha256sum < /usr/share/microos/avb/testkey_rsa4096.pem) == "6a224754880a57ab9cbd308267cd157d94cf05a1c8cb851aec4090e045d24121  -" ]] \
  || fail "AVB test key sha256"
[[ $(< /usr/lib/systemd/journald.conf.d/10-microos.conf) == $'[Journal]\nStorage=persistent' ]] || fail "journald 10-microos.conf"
[[ $(< /usr/lib/bootc/install/00-microos.toml) == $'[install.filesystem.root]\ntype = "btrfs"' ]] || fail "00-microos.toml"
[[ $(< /usr/lib/NetworkManager/conf.d/10-microos.conf) == $'[keyfile]\npath=/var/lib/NetworkManager/system-connections\n\n[device-microos-usb0]\nmatch-device=interface-name:usb0\nmanaged=1' ]] \
  || fail "NetworkManager 10-microos.conf"
nm=/usr/lib/NetworkManager/system-connections/microos-usb0.nmconnection
[[ $(stat -c '%a %U' "$nm") == '600 root' ]] || fail "$nm mode"
grep -qx 'method=shared' "$nm" && grep -qx 'address1=10.42.0.1/24' "$nm" || fail "$nm is not shared on 10.42.0.1/24"
for f in microos-slot microos-usb-console; do
  [[ $(stat -c %a "/usr/libexec/microos/$f") == 755 ]] || fail "$f is not 755"
done
[[ $(< /usr/lib/udev/rules.d/90-microos-usb-console.rules) == \
  'SUBSYSTEM=="tty", KERNEL=="ttyGS0", ENV{SYSTEMD_WANTS}+="serial-getty@ttyGS0.service"' ]] || fail "90-microos-usb-console.rules"
[[ $(< /usr/lib/tmpfiles.d/microos.conf) == $'d /run/microos 0755 root root -\nd /var/home/micro 0700 micro micro -\nd /var/lib/microos 0755 root root -' ]] \
  || fail "tmpfiles microos.conf"
dtb=/usr/lib/modules/$kver/dtb/$(sed -n 's/^MICROOS_DTB=//p' /usr/lib/microos/bootimg.conf)
[[ $(od -An -tx1 -N4 "$dtb" | tr -d ' \n') == d00dfeed ]] || fail "MICROOS_DTB $dtb is not a DTB"

execs() {
  systemctl cat "$1" | awk -v k="$2=" 'index($0, k) == 1 { v = substr($0, length(k) + 1); if (v == "") n = 0; else l[++n] = v }
    END { for (i = 1; i <= n; i++) print l[i] }'
}
[[ $(execs ostree-finalize-staged.service ExecStop) == '/usr/bin/ostree admin finalize-staged' ]] \
  || fail "effective ostree-finalize-staged.service ExecStop: $(execs ostree-finalize-staged.service ExecStop)"
[[ -z $(execs ostree-finalize-staged.service ExecStartPre) ]] || fail "ostree-finalize-staged.service has an ExecStartPre"
[[ $(execs microos-boot-ok.service After) == 'multi-user.target ostree-finalize-staged.service' ]] \
  || fail "microos-boot-ok.service After: $(execs microos-boot-ok.service After)"
[[ $(execs emergency.service ExecStart) == '-/usr/libexec/microos/microos-fail emergency' ]] \
  || fail "effective emergency.service ExecStart: $(execs emergency.service ExecStart)"
systemctl cat microos-boot-deadline.timer | grep -qx 'OnBootSec=900' || fail "microos-boot-deadline.timer is not 900 s"
systemctl cat serial-getty@ttyGS0.service | grep -qx 'ConditionKernelCommandLine=microos.test' \
  || fail "serial-getty@ttyGS0.service has no microos.test condition"
[[ $(execs serial-getty@ttyGS0.service ExecStart) == '-/usr/sbin/agetty --autologin root '* ]] \
  || fail "serial-getty@ttyGS0.service ExecStart: $(execs serial-getty@ttyGS0.service ExecStart)"
systemctl cat sshd.service | grep -qx 'ConditionPathExists=/var/home/micro/.ssh/authorized_keys' \
  || fail "sshd.service has no ConditionPathExists on micro's authorized_keys"
while read -r u p; do
  [[ $p == -* || $p == /sys/* ]] && continue
  grep -qE "^d $p [0-7]+ " /usr/lib/tmpfiles.d/*.conf || fail "${u##*/} ReadWritePaths=$p has no tmpfiles line"
done < <(awk -F= '/^ReadWritePaths=/ { n = split($2, a, " "); for (i = 1; i <= n; i++) print FILENAME, a[i] }' \
  /usr/lib/systemd/system/microos-*)
SYSTEMD_LOG_LEVEL=warning systemd-analyze verify --man=no "${units[@]}" /usr/lib/systemd/system/sshd.service \
  /usr/lib/systemd/system/ostree-finalize-staged.service || fail "systemd-analyze verify"

pol=/etc/containers/policy.json
keys=(/usr/share/microos/keys/microos.pub /usr/share/microos/keys/microos-backup.pub /usr/share/microos/keys/microos-next.pub)
jq -e '.default == [{"type": "reject"}]' "$pol" >/dev/null || fail "policy default is not reject"
jq -e '.transports.docker["ghcr.io/seilent/microos-y700"] == [{"type": "sigstoreSigned", "keyPaths": $ARGS.positional,
  "signedIdentity": {"type": "matchRepository"}}]' --args "${keys[@]}" < "$pol" >/dev/null || fail "policy scope ghcr.io/seilent/microos-y700"
for k in "${keys[@]}"; do
  openssl pkey -pubin -noout -in "$k" 2>/dev/null || fail "$k is not a public key"
done
[[ $(< /etc/containers/registries.d/ghcr-microos.yaml) == $'docker:\n  ghcr.io/seilent/microos-y700:\n    use-sigstore-attachments: true' ]] \
  || fail "registries.d ghcr-microos.yaml"

mkdir -p "$tmp/etc/ssh"
ssh-keygen -A -f "$tmp" >/dev/null
hk=()
for k in "$tmp"/etc/ssh/ssh_host_*_key; do hk+=(-h "$k"); done
sshd -T "${hk[@]}" > "$tmp/sshd"
for kv in 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permitrootlogin no' 'allowusers micro' \
  'authenticationmethods publickey' 'x11forwarding no' 'gssapiauthentication no'; do
  grep -qx "$kv" "$tmp/sshd" || fail "sshd -T lacks '$kv'"
done

systemd-sysusers >/dev/null 2>&1
[[ $(id -u micro):$(id -g micro) == 1000:1000 ]] || fail "micro is not 1000:1000"
groups=$(id -nG micro)
for g in wheel systemd-journal; do
  [[ " $groups " == *" $g "* ]] || fail "micro is not in $g"
done
[[ $(getent passwd micro | cut -d: -f6,7) == /var/home/micro:/bin/bash ]] || fail "micro home or shell"
for u in microos-openh264 microset; do
  ! getent passwd "$u" >/dev/null || fail "user $u exists"
done
! getent group hexagonrpc >/dev/null || fail "group hexagonrpc exists"
rules=$(sudo -l -U micro)
grep -q '(ALL) ALL' <<< "$rules" || fail "micro has no wheel sudo rule"
! grep -q NOPASSWD <<< "$rules" || fail "micro has a NOPASSWD rule"
! grep -qE '/tee( |,|$)' <<< "$rules" || fail "micro has a sudo rule for tee"

img=/usr/lib/modules/$kver/initramfs.img
list=$(lsinitrd "$img")
for m in erofs overlay btrfs ufs-qcom; do
  grep -qE "/$m\.ko" <<< "$list" || grep -qE "/$m\.ko$" "/usr/lib/modules/$kver/modules.builtin" || fail "initramfs lacks $m"
done
dropin=usr/lib/systemd/system/ostree-prepare-root.service.d/10-microos-remap.conf
for f in usr/lib/ostree/ostree-prepare-root usr/libexec/microos/prepare-root usr/bin/sh usr/bin/realpath usr/bin/mkdir "$dropin"; do
  grep -qE " $f( |$)" <<< "$list" || fail "initramfs lacks $f"
done
! grep -qE "/kernel/drivers/gpu/" <<< "$list" || fail "initramfs has a GPU module"
(( $(stat -c %s "$img") <= 15728640 )) || fail "initramfs is $(stat -c %s "$img") bytes, over 15728640"
[[ $(lsinitrd -f "$dropin" "$img") == $'[Service]\nExecStart=\nExecStart=/usr/libexec/microos/prepare-root' ]] || fail "remap drop-in content"
for f in usr/libexec/microos/microos-guard usr/libexec/microos/microos-initrd-log usr/libexec/microos/microos-sdam \
  usr/lib/systemd/system/microos-guard.service etc/microos-initrd-id usr/lib/systemd/system/emergency.service.d/10-microos.conf \
  usr/lib/systemd/system/dracut-emergency.service.d/10-microos.conf; do
  grep -qE " $f( |$)" <<< "$list" || fail "initramfs lacks $f"
done
grep -qE "/initrd\.target\.wants/microos-guard\.service( |$)" <<< "$list" || fail "initramfs does not enable microos-guard.service"
unpack=$(mktemp -d)
(cd "$unpack" && lsinitrd --unpack "$img" usr/lib/systemd/system/emergency.service.d/10-microos.conf \
  usr/lib/systemd/system/dracut-emergency.service.d/10-microos.conf)
for u in emergency dracut-emergency; do
  [[ $(< "$unpack/usr/lib/systemd/system/$u.service.d/10-microos.conf") == \
    $'[Service]\nExecStartPre=-/usr/libexec/microos/microos-initrd-log' ]] || fail "initramfs $u drop-in content"
done
rm -rf "${unpack:?}"
grep -qE "/nvmem_qcom-spmi-sdam\.ko" <<< "$list" || fail "initramfs lacks nvmem_qcom-spmi-sdam"
[[ $(lsinitrd -f etc/cmdline.d/90-microos.conf "$img") == 'rd.shell=0 rd.emergency=reboot' ]] || fail "initramfs cmdline.d/90-microos.conf"
[[ $(lsinitrd -f usr/lib/systemd/system/initrd-switch-root.service.d/10-microos.conf "$img") == \
  $'[Service]\nExecStart=\nExecStart=systemctl --no-block switch-root /sysroot /usr/lib/systemd/systemd' ]] || fail "initramfs switch-root drop-in"
[[ $(lsinitrd -f 'usr/lib/systemd/system/dev-disk-by?x2dpartlabel-microos_efi.device.d/10-microos.conf' "$img") == \
  $'[Unit]\nJobRunningTimeoutSec=45' ]] || fail "initramfs microos_efi device timeout"
[[ $(lsinitrd -f etc/microos-initrd-id "$img") =~ ^$kver\ [0-9]{8}T[0-9]{6}Z$ ]] || fail "initramfs microos-initrd-id"
lsinitrd -f usr/lib/systemd/system/ostree-prepare-root.service "$img" | grep -qx 'ExecStart=/usr/lib/ostree/ostree-prepare-root /sysroot' \
  || fail "ostree-prepare-root.service ExecStart changed"

[[ -x /usr/bin/microos-update ]] || fail "/usr/bin/microos-update missing"
scripts=()
for f in /usr/libexec/microos/* /usr/lib/microos/* /usr/lib/dracut/modules.d/91microos-ostree-remap/* /usr/bin/microos-*; do
  [[ -f $f ]] && scripts+=("$f")
done
etc=$(grep -nE '(^|[^[:alnum:]_.}-])/etc/' "${scripts[@]}" \
  | grep -vxE '/usr/bin/microos-update:[0-9]+:[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/etc/containers/policy\.json' \
  | grep -vE '== /etc/\*' || true)
[[ -z $etc ]] || fail "MicroOS scripts reference /etc: $etc"

chmod 711 "$tmp"
esp=$tmp/esp
mkdir -p "$esp/microos"
printf '[connection]\nid=home\ntype=wifi\n' > "$esp/microos/home.nmconnection"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA test\n' > "$esp/microos/authorized_keys"
env MICROOS_ESP="$esp" MICROOS_RUNDIR="$tmp/run" MICROOS_NMDIR="$tmp/nm" MICROOS_HOME="$tmp/home" \
  /usr/libexec/microos/microos-provision >/dev/null || fail "provision failed"
[[ -z $(ls -A "$esp/microos") ]] || fail "provision left files on the ESP: $(ls -A "$esp/microos")"
[[ $(stat -c '%a %U' "$tmp/nm/home.nmconnection") == '600 root' ]] || fail "nmconnection mode"
[[ $(stat -c '%a %U' "$tmp/home/.ssh") == '700 micro' ]] || fail ".ssh mode"
[[ $(stat -c '%a %U' "$tmp/home/.ssh/authorized_keys") == '600 micro' ]] || fail "authorized_keys mode"
[[ -e $tmp/run/bootimg.lock ]] || fail "provision did not take the bootimg lock"

printf '[connection]\nid=kept\n' > "$esp/microos/kept.nmconnection"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB test\n' > "$esp/microos/authorized_keys"
touch "$tmp/nmfile"
if env MICROOS_ESP="$esp" MICROOS_RUNDIR="$tmp/run" MICROOS_NMDIR="$tmp/nmfile/sub" MICROOS_HOME="$tmp/home" \
  /usr/libexec/microos/microos-provision >/dev/null 2>&1; then
  fail "provision passed with an unwritable connection dir"
fi
[[ -f $esp/microos/kept.nmconnection ]] || fail "failed import removed the file"
[[ ! -e $esp/microos/authorized_keys ]] || fail "authorized_keys not imported next to a failed import"

install -d -m 0755 "$tmp/victim"
for kind in symlink file; do
  rm -rf "$tmp/home2"
  install -d -m 0700 -o micro -g micro "$tmp/home2"
  if [[ $kind == symlink ]]; then
    ln -s "$tmp/victim" "$tmp/home2/.ssh"
  else
    touch "$tmp/home2/.ssh"
  fi
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC test\n' > "$esp/microos/authorized_keys"
  if env MICROOS_ESP="$esp" MICROOS_RUNDIR="$tmp/run" MICROOS_NMDIR="$tmp/nm" MICROOS_HOME="$tmp/home2" \
    /usr/libexec/microos/microos-provision >/dev/null 2>&1; then
    fail "provision passed with a $kind .ssh"
  fi
  [[ -f $esp/microos/authorized_keys ]] || fail "$kind .ssh: authorized_keys removed from the ESP"
done
[[ $(stat -c '%a %U %G' "$tmp/victim") == '755 root root' ]] || fail "symlinked .ssh changed its target"
[[ ! -e $tmp/victim/authorized_keys ]] || fail "symlinked .ssh: key written into the target"
rm -f "$esp/microos/authorized_keys" "$esp/microos/kept.nmconnection"

root=$tmp/initrd
mkdir -p "$root"
(cd "$root" && lsinitrd --unpack "$img")
[[ -x $root/usr/libexec/microos/prepare-root && -x $root/usr/bin/sh ]] || fail "unpacked initramfs lacks the wrapper"

s=$tmp/sysroot
a=$(printf 'a%.0s' {1..64}).0
b=$(printf 'b%.0s' {1..64}).0
ca=$(printf 'c%.0s' {1..64})
cb=$(printf 'd%.0s' {1..64})
mkdir -p "$s/ostree/deploy/default/deploy/$a" "$s/ostree/deploy/default/deploy/$b" "$s/ostree/boot.1.1/default/$ca" \
  "$s/ostree/boot.1.1/default/$cb"
ln -s boot.1.1 "$s/ostree/boot.1"
ln -s "../../../deploy/default/deploy/$a" "$s/ostree/boot.1.1/default/$ca/0"
ln -s "../../../deploy/default/deploy/$b" "$s/ostree/boot.1.1/default/$cb/1"

cat > "$tmp/prep" <<'PREP'
#!/bin/sh
printf '%s\n' "$#" "$@" > "$PREP_OUT"
PREP
chmod 755 "$tmp/prep"

remap() {
  local path=$1 cmdline=$2
  printf '%s\n' "$cmdline" > "$tmp/cmdline"
  rm -rf "$tmp/rrun" "$tmp/out"
  env -i PATH="$path" PREP_OUT="$tmp/out" MICROOS_PREPARE_ROOT="$tmp/prep" MICROOS_SYSROOT="$s" \
    MICROOS_CMDLINE="$tmp/cmdline" MICROOS_RUNDIR="$tmp/rrun" MICROOS_KMSG="$tmp/kmsg" \
    "$root/usr/bin/sh" "$root/usr/libexec/microos/prepare-root"
}
ipath=$root/usr/bin:$root/usr/sbin
base="root=UUID=x rw rootflags=subvol=root,noatime,compress=zstd:1 console=tty0"
expect_unchanged() {
  [[ $(cat "$tmp/out") == "1"$'\n'"$s" ]] || fail "$1: expected unchanged, got $(tr '\n' ' ' < "$tmp/out")"
  [[ ! -e $tmp/rrun/remapped ]] || fail "$1: remapped written"
}
expect_remap() {
  [[ $(cat "$tmp/out") == "2"$'\n'"$s"$'\n'"$2" ]] || fail "$1: got $(tr '\n' ' ' < "$tmp/out")"
  [[ $(cat "$tmp/rrun/remapped") == "$3 $4" ]] || fail "$1: remapped is $(cat "$tmp/rrun/remapped")"
}

good=/ostree/boot.1/default/$ca/0
remap "$ipath" "ostree=$good $base microos.deploy=$a"
expect_unchanged match

remap "$ipath" "ostree=$good $base"
expect_unchanged "no microos.deploy"

stale=/ostree/boot.0/default/$ca/0
remap "$ipath" "ostree=$stale $base microos.deploy=$a"
expect_remap "stale, one match" "ostree=$good $base microos.deploy=$a" "$stale" "$good"

remap "$ipath" "ostree=/ostree/boot.1/default/$cb/1 $base microos.deploy=$a"
expect_remap "link names another deployment" "ostree=$good $base microos.deploy=$a" "/ostree/boot.1/default/$cb/1" "$good"

remap "$ipath" "ostree=$stale $base microos.deploy=$(printf 'e%.0s' {1..64}).0"
expect_unchanged "stale, no match"

mkdir -p "$s/ostree/boot.0.1/default/$ca"
ln -s boot.0.1 "$s/ostree/boot.0"
ln -s "../../../deploy/default/deploy/$a" "$s/ostree/boot.0.1/default/$ca/0"
remap "$ipath" "ostree=/ostree/boot.1/default/$cb/1 $base microos.deploy=$a"
[[ $(sed -n 1p "$tmp/out") == 2 ]] || fail "same dir via both boot.N: not remapped"
grep -qE "^ostree=/ostree/boot\.[01]/default/$ca/0 " <(sed -n 3p "$tmp/out") || fail "same dir via both boot.N: wrong link"

mkdir -p "$s/ostree/deploy/other/deploy/$a" "$s/ostree/boot.1.1/other/$ca"
ln -s "../../../deploy/other/deploy/$a" "$s/ostree/boot.1.1/other/$ca/0"
remap "$ipath" "ostree=/ostree/boot.1/default/$cb/1 $base microos.deploy=$a"
expect_unchanged "two different dirs"
rm -rf "$s/ostree/boot.1.1/other" "$s/ostree/deploy/other"

mkdir -p "$tmp/broken"
cp -a "$root/usr/bin/." "$tmp/broken/"
printf '#!/bin/sh\nexit 1\n' > "$tmp/broken/realpath"
chmod 755 "$tmp/broken/realpath"
remap "$tmp/broken:$root/usr/sbin" "ostree=$stale $base microos.deploy=$a"
expect_unchanged "broken realpath"
printf '#!/bin/sh\necho\n' > "$tmp/broken/realpath"
remap "$tmp/broken:$root/usr/sbin" "ostree=$stale $base microos.deploy=$a"
expect_unchanged "empty realpath"

echo "image: ok ($kver)"