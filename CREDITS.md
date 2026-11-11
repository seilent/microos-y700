# Credits

Projects MicroOS builds, with their authors and license.

## Kernel

Linux 7.2.12 from [kernel.org](https://www.kernel.org/), GPL-2.0-only WITH Linux-syscall-note. Patches and their
origins in `packages/kernel/PATCHES.md`.

| What | Origin | Author | License |
|---|---|---|---|
| TB321FU DTS and patch set | [enij90/armada-tb321fu](https://github.com/enij90/armada-tb321fu) `v20261024.0146e89`, per patch sources in its `PATCHES.md` | enij90, patch authors as listed there | BSD-3-Clause (DTS), GPL-2.0-only |
| Qualcomm HV haptics driver | [ROCKNIX](https://github.com/ROCKNIX/distribution) `47e077d0bb` (SM8750), Qualcomm downstream `qcom-hv-haptics` | The Linux Foundation, Qualcomm Innovation Center (Qualcomm downstream) | GPL-2.0-only |
| PM8150L LCDB regulator | ROCKNIX `063e530e58`, ported from Qualcomm downstream `qpnp-lcdb-regulator` | Philippe Simons, The Linux Foundation (Qualcomm downstream) | GPL-2.0-only |
| wcd938x headphone jack detection | [batocera.linux](https://github.com/batocera-linux/batocera.linux) `ea7bbd5c7f84` | Daniel Martin | GPL-2.0 |
| HDMI audio `hw_params` callback | lore `20250925040530.20731-1-liujianfeng1994@gmail.com` | Jianfeng Liu | MIT |
| sm8250 backend format kept for PCM | [ROCKNIX/distribution-old](https://github.com/ROCKNIX/distribution-old) `f7b53cc4b244` (idea), Linux `89be3c15a58b` (S16_LE force) | rmake, Alexey Klimov | GPL-2.0 |
| msm DP `audio_prepare` unplugged | lore `20260616151252.3599089-2-kumar.singh@oss.qualcomm.com` | Kumar Anurag | GPL-2.0-only |
| ufs-qcom lane clocks | `mkp/scsi.git` `f07317a8d57f` | Nitin Rawat | GPL-2.0-only |
| qcom-geni force suspend in system sleep | Linux `d0cd9c8d0fd5` | Praveen Talari | GPL-2.0 |
| qce runtime PM and interconnect scaling | Linux `6f5569203bb6` | Udit Tiwari | GPL-2.0-only |
| lpass rx and tx macro PM clocks for runtime PM, clk_set_rate() check, wsa macro MCLK output with devm | Linux `b9b23e72abef`, `b05482e7ce1b`, `b8ca90fafe6a`, `541735571578` | Ajay Kumar Nandam, Ravi Hothi | GPL-2.0-only |
| AR16 panel driver, base of the AR18 driver | ROCKNIX SM8550 `0064`, `aa418ad72e` | danyi | GPL-2.0-only |
| Sitronix ST7123 driver, base of the ST7123 driver | [raspberrypi/linux](https://github.com/raspberrypi/linux) `6d4adb6bfea6` | Waveshare, Sitronix | GPL-2.0 |
| Rumble report format in `hid-ayaneo` | stock Android 4.19.157 `hid-ayaneo` | AYANEO | GPL-2.0 |

## Base

| What | Origin | Author | License |
|---|---|---|---|
| Base image | [Fedora bootc](https://gitlab.com/fedora/bootc/base-images) `registry.fedoraproject.org/fedora-bootc:44` | Fedora Project | per package (Fedora 44) |
| bootc | [bootc-dev/bootc](https://github.com/bootc-dev/bootc), Fedora `bootc` | bootc contributors | Apache-2.0 OR MIT |
| AVB test key `usr/share/microos/avb/testkey_rsa4096.pem` | [AOSP external/avb](https://android.googlesource.com/platform/external/avb) `test/data/testkey_rsa4096.pem` | The Android Open Source Project | Apache-2.0 |
| OSTree | [ostreedev/ostree](https://github.com/ostreedev/ostree), Fedora `ostree` | OSTree contributors | LGPL-2.0-or-later |
| `mkbootimg`, `unpack_bootimg` | AOSP `platform/system/tools/mkbootimg`, Fedora `android-tools` | The Android Open Source Project | Apache-2.0 |
