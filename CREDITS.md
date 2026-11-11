# Credits

Projects MicroOS builds, with their authors and license.

## Kernel

Linux 7.4-rc2 from [kernel.org](https://www.kernel.org/), GPL-2.0-only WITH Linux-syscall-note. Patches and their
origins in `packages/kernel/PATCHES.md`.

## Session

| What | Origin | Author | License |
|---|---|---|---|
| `gamescope-session` | [OpenGamingCollective/gamescope-session](https://github.com/OpenGamingCollective/gamescope-session) `08e65a62ed` | Joaquín Ignacio Aramendía, ChimeraOS and Open Gaming Collective contributors | MIT |
| `gamescope-session-steam` | [OpenGamingCollective/gamescope-session-steam](https://github.com/OpenGamingCollective/gamescope-session-steam) `82c45fc112` | ChimeraOS and Open Gaming Collective contributors | MIT |
| `gamescope` | [OpenGamingCollective/gamescope](https://github.com/OpenGamingCollective/gamescope) `3.16.31-ogc2` `76a1563a83` | Valve (Joshua Ashton and gamescope contributors), Open Gaming Collective contributors | BSD-2-Clause, BSD-3-Clause |
| `gamescope` RPM spec and packaging patches | Fedora [rpms/gamescope](https://src.fedoraproject.org/rpms/gamescope) `a846be4c` | František Zatloukal, Neal Gompa and Fedora packagers | MIT |
| `gamescope` one step vblank catch up | OGC `72ad630c018e`, first in `3b3cced787e3` | Matthew Schwartz | BSD-2-Clause |
| Steam client and Steam Runtime (steamrt3c arm64) | Valve `steam_client_steamdeck_stable_linuxarm64` `1788652215`, `steam-runtime-steamrt-arm64` `3c.0.20260729.253765` | Valve Corporation | Steam Subscriber Agreement |

`gamescope-session` carries my Y700 `device-quirks` entry and my startup timeout patch, `gamescope` carries Fedora's
packaging patches, six of mine and an OGC patch backported by me (`0003` to `0009`, `0006` from OGC) (`PATCHES.md`
in each package); `gamescope-session-steam` is built as is. License texts in `packages/gamescope/` and
`packages/gamescope-session/`.

## Audio

| What | Origin | Author | License |
|---|---|---|---|
| `audioreach-topology` m4 macros | [Linaro audioreach-topology](https://git.codelinaro.org/linaro/qcomlt/audioreach-topology) `1d4c4e337d` | Linaro Ltd | BSD-3-Clause |

`audioreach-topology` carries my legacy TDM module and subgraph and my Y700 topology (`PATCHES.md` in the package).
License text in `packages/audioreach-topology/`.

## Base

| What | Origin | Author | License |
|---|---|---|---|
| Base image | [Fedora bootc](https://gitlab.com/fedora/bootc/base-images) `registry.fedoraproject.org/fedora-bootc:44` | Fedora Project | per package (Fedora 44) |
| bootc | [bootc-dev/bootc](https://github.com/bootc-dev/bootc), Fedora `bootc` | bootc contributors | Apache-2.0 OR MIT |
| AVB test key `usr/share/microos/avb/testkey_rsa4096.pem` | [AOSP external/avb](https://android.googlesource.com/platform/external/avb) `test/data/testkey_rsa4096.pem` | The Android Open Source Project | Apache-2.0 |
| OSTree | [ostreedev/ostree](https://github.com/ostreedev/ostree), Fedora `ostree` | OSTree contributors | LGPL-2.0-or-later |
| `mkbootimg`, `unpack_bootimg` | AOSP `platform/system/tools/mkbootimg`, Fedora `android-tools` | The Android Open Source Project | Apache-2.0 |
