# Kernel patches

Base: mainline `v7.4-rc2` (`7475ea8b5861`), set in `SOURCE.env`. `build.sh` fetches the tag from kernel.org git and
exports it with `git archive`; a stable base is the kernel.org tarball with its sha256. No patches on top. The DTS
files in `dts/` are copied into `arch/arm64/boot/dts/qcom/` by `build.sh`.

Config: `tb321fu.config` holds the board lines, `microos.config` the image level lines.
