# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-20

First release.

### Added

- **One program, one configuration file, one installer.** `mbp-sleep` is a
  daemon plus a systemd sleep hook; it replaces a set of separately written
  hooks and units that had drifted apart.

  | file | role |
  |---|---|
  | `mbp-sleep` | daemon (wake sources, lid, backup deferral) plus the `pre`/`post` sleep hook |
  | `macbook.conf` | every behaviour as a switch, all of them `on` by default |
  | `install.sh` | installs the program, unit, hook and two drop-ins; removes what it replaces |
  | `uninstall.sh` | the inverse, restoring what the installer moved aside |

- **Network filesystems are taken down before sleep and brought back after.**
  A dirty page on a share whose link is gone blocks `sync_filesystem()` for the
  length of the CIFS reconnect deadline; with the mounts removed first the stall
  measured **0.019 s** instead of 194.6 s and 95.6 s. The target list is
  discovered from `/proc/mounts` by filesystem type, so no share names are
  configured.

- **Wi-Fi is detached before sleep and reloaded after resume.** A loaded
  `brcmfmac` could refuse to be suspended, and one refusing device aborts the
  whole transaction; a module that is not loaded cannot refuse.

- **The Thunderbolt Ethernet adapter's endpoint is de-authorised across sleep.**
  With the adapter attached across sleep, resumes did not complete on this
  machine; with it off the bus first, they do. The host controller is never
  touched, so the adapter stays usable.

- **A sleep requested during a backup waits for it** instead of killing it. The
  daemon holds a logind `block` lock on `sleep` while a configured backup
  process is running, remembers the request, and re-issues it when the backup
  ends.

- **Wake sources are re-armed at start**, because `/proc/acpi/wakeup` is rebuilt
  at every boot and comes back with `SPIT` disabled.

- Commands: `mbp-sleep status`, `dry-run`, `report --boot N`, and the `pre` /
  `post` entry points the sleep hook calls.

- `docs/background.md` — the machine, the three measured faults, and what is not
  worth re-testing.
- `docs/config-changes.md` — every change made to the machine, each with an undo.
- `scripts/diagnose.sh`, `scripts/test-suspend.sh`, `scripts/run-report.sh`,
  `scripts/set-wake.sh`.

### Known limitations

- **Hibernation is not supported.** Nothing here runs for `hibernate.target`,
  and hibernation does not work on this hardware as configured.
- **Physical wake from the lid is unverified.** `/proc/acpi/wakeup` lists `LID0`
  as S4-only.
- **`gnome-shell.service` can end up `inactive` with a live process after an S3
  resume**; the screen lights but no password prompt appears.
- This is one machine's configuration. The defaults assume the same hardware:
  `wlan0`, `brcmfmac`, and a Thunderbolt-to-Ethernet adapter.
