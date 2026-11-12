# Kernel patches

Base: mainline `v7.4-rc2` (`7475ea8b5861`), set in `SOURCE.env`. `build.sh` fetches the tag from kernel.org git and
exports it with `git archive`; a stable base is the kernel.org tarball with its sha256. `patches/series` applies in
order with `patch -p1 -F0`. The patches are made with `git format-patch` from a kernel tree on the base tag. The DTS
files in `dts/` are copied into `arch/arm64/boot/dts/qcom/` by `build.sh`.

Config: `tb321fu.config` holds the board lines, `microos.config` the image level lines.

## Patches

| Patch | Origin | Check |
|---|---|---|
| `0001-dt-bindings-arm-qcom-Add-Lenovo-Legion-Y700-2025.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0002-dt-bindings-display-panel-novatek-nt36523-Add-Lenovo.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0003-drm-panel-novatek-nt36523-Remove-the-panel-when-prob.patch` | mine | panel probes after a deferred DSI attach, no list corruption in dmesg |
| `0004-drm-panel-novatek-nt36523-Add-Lenovo-Legion-Y700-202.patch` | mine | `card1-DSI-1` connected, 1600x2560 at 120 Hz, picture without DSC or underrun errors, panel back after 10 DPMS cycles |
| `0005-dt-bindings-backlight-kinetic-ktz8866-Add-boost-and-.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0006-backlight-ktz8866-Set-boost-OVP-inductor-and-LED-cur.patch` | mine | KTZ8866 regs 0x02 0xda, 0x11 0x37, 0x15 0x68; brightness steps even |
| `0013-iommu-arm-smmu-qcom-Add-SM8650-MDSS-compatible-to-cl.patch` | mine | no `Unhandled context fault` on SID 0x1c00 at the splash addresses during boot; MDSS group default domain identity |
| `0007-dt-bindings-input-touchscreen-Add-Novatek-NT36523-SP.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0008-Input-add-Novatek-NT36523-SPI-touchscreen-driver.patch` | mine | probe log with the firmware version; 10 fingers matching the landscape panel; the pen input device and its absinfo; firmware reload after a DPMS cycle; reloads stop after five watchdog resets in a row |
| `0009-dt-bindings-input-awinic-aw86927-Add-AW86937.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0010-Input-aw86927-add-support-for-AW86937.patch` | mine | both motors probe with chip ID 0x9370; `fftest` rumble and stop on both, felt |
| `0011-dt-bindings-usb-Add-Parade-PS5169-USB-C-redriver.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0012-usb-typec-mux-Add-Parade-PS5169-redriver-driver.patch` | mine | typec switch and retimer registered; DP alt mode picture on a monitor; SuperSpeed link on the USB-C port |
| `0020-ASoC-dt-bindings-awinic-aw88395-Add-AW88461.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0021-ASoC-codecs-aw88261-Enable-I2S-TX-in-I2SCTRL3.patch` | mine | AW88261 boards: TX feedback on I2SCTRL3 bit 6 during a stream; the register comes from the vendor PID 0x2113 table, no datasheet (unverified) |
| `0022-ASoC-codecs-aw88261-Keep-the-volume-across-profile-c.patch` | mine | `Profile Set` to Receiver and back keeps `PCM Playback Volume` |
| `0023-ASoC-codecs-aw88261-Add-AW88461-support.patch` | mine | chip ID 0x2308 in the probe log of both PAs, ACF loaded with its Music and Receiver profiles, `SpkrLeft` and `SpkrRight` controls, `PCM Playback Volume` 360 leaves SYSCTRL2 at the ACF level 0x19; both PAs heard |
| `0024-ASoC-codecs-aw88261-Enable-TX-feedback-only-with-a-T.patch` | mine | SYSCTRL bit 13 clear on both PAs while the speaker stream runs (no TX slot in the DT) |
| `0025-ASoC-qcom-q6prm-Add-TDM-bit-clocks.patch` | mine | SEC TDM bit clock on at 12.288 MHz while the speaker stream runs, no PRM error |
| `0026-ASoC-qcom-audioreach-Add-legacy-TDM-sink-and-source.patch` | mine | topology loads with the legacy TDM sink, the Secondary TDM0 graph opens and starts with no APM error; both PAs play |
| `0027-ASoC-dt-bindings-qcom-sm8250-Add-Lenovo-Legion-Y700-.patch` | mine | `dt-validate` on the TB321FU DTBs |
| `0028-ASoC-qcom-sc8280xp-Add-Lenovo-Legion-Y700-2025-sound.patch` | mine | card `Lenovo-Y700-TB321FU` registers, `/proc/asound/pcm` lists the MultiMedia PCMs, UCM HiFi Speaker plays on `hw:0,1` |
| `0029-ASoC-soc-core-reset-rtd-num_components-after-allocat.patch` | upstream, broonie/sound.git for-next `d00ba321499c` (Emanuele Ghidoli), https://patch.msgid.link/20261109102536.357134-1-ghidoliemanuele@gmail.com | the card probes its components: component directories under the card in `/sys/kernel/debug/asoc`, the AW88261 and topology controls, `MultiMedia` PCMs in `/proc/asound/pcm` |
| `0030-ASoC-codecs-aw88261-Start-the-amplifier-from-a-work.patch` | mine | no `start failure` on either PA when the speaker stream starts; both PAs heard |
| `0040-ASoC-qcom-sc8280xp-Set-up-the-Lenovo-Legion-Y700-202.patch` | mine | `Headphone Jack` and `Mic Jack` controls on the card; a headset in the USB-C port sets both, its removal clears them; a failed jack setup leaves the card up with one warning |
