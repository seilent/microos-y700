# MicroOS for the Legion Y700

A bootc image for the Lenovo Legion Y700 (2025, TB321FU), built on Fedora (`registry.fedoraproject.org/fedora-bootc:44`).

It boots from slot b, next to the stock Android on slot a. Session: Steam game mode.

CI builds the `testing` channel, `ghcr.io/seilent/microos-y700:testing`, from `main`,
`ghcr.io/seilent/microos-y700:dev-<sha>` from other branches, and moves `branch-<name>` to each green branch head.

## Updates

The device checks its channel daily and after each boot, pulls the update and writes it to `boot_b`. The next reboot
applies it. Updates that change the kernel, the initramfs or the boot image wait for `sudo microos-update`.

The channel is `/var/lib/microos/update-channel`: `testing` (the default), `stable` or `branch-<name>`.

## License

GPL-2.0-or-later, see [LICENSE](LICENSE). Components taken from other projects keep their own license and are listed
in [CREDITS.md](CREDITS.md).

MicroOS is not provided or supported by the Fedora Project. Official Fedora is available at
[fedoraproject.org](https://fedoraproject.org/). Steam is a trademark of Valve. MicroOS is not affiliated
with Valve or Lenovo.
