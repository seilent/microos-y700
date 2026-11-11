# MicroOS for the Legion Y700

A bootc image for the Lenovo Legion Y700 (2025, TB321FU), built on Fedora (`registry.fedoraproject.org/fedora-bootc:44`).

It boots from slot b, next to the stock Android on slot a. Session: Steam game mode.

CI builds the `testing` channel, `ghcr.io/seilent/microos-y700:testing`, from `main`, and
`ghcr.io/seilent/microos-y700:dev-<sha>` from other branches.

## License

GPL-2.0-or-later, see [LICENSE](LICENSE). Components taken from other projects keep their own license and are listed
in [CREDITS.md](CREDITS.md).

MicroOS is not provided or supported by the Fedora Project. Official Fedora is available at
[fedoraproject.org](https://fedoraproject.org/). Steam is a trademark of Valve. MicroOS is not affiliated
with Valve or Lenovo.
