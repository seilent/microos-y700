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
