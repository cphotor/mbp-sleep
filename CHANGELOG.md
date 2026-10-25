# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **A self-wake no longer leaves the machine awake with the lid shut.** The
  machine has a wake source that is not identified, and nothing re-suspended it:
  logind's lid handling is off here, and the daemon acts only on an
  open→closed edge. Measured 2026-10-23: a self-wake at 23:22 left it awake,
  lid shut, for **38 hours**. On resume the daemon now notices the S3 residence
  through `CLOCK_BOOTTIME` (which counts sleep; `CLOCK_MONOTONIC` does not) and,
  if the lid is still closed, suspends again after `resuspend_delay` seconds, at
  most `resuspend_max` times in a row. The wake itself is not suppressed — the
  source is still unknown, and the only sources that could be disabled are the
  keyboard and lid wake that must keep working.
- **Wake attribution.** `wake_log`: the `pre` hook saves
  `/sys/class/wakeup/*/event_count` and the ACPI GPE counters, the `post` hook
  logs what moved (`wake: counters moved: …`). `event_count`, not
  `wakeup_count`: the latter is only incremented on a retried suspend and stays
  `0` on a clean S3 cycle. A mover is a candidate, not a cause — the Apple EC
  block moves its counters on every cycle.

### Changed

- `mbp-sleep report` points at the new attribution log instead of telling the
  reader to take a snapshot by hand.
- `macbook.conf` grew sections 7 (self-wake) and 8 (the session freeze, was 7).

### Fixed

- **A share whose `umount` was killed at the timeout was never remounted.**
  `umount /mnt/tmcap2` was killed at its 15 s timeout *after* the kernel had
  dropped the mount — systemd logged `mnt-tmcap2.mount: Deactivated
  successfully` in the same millisecond the command started. The exit code was
  read as "still mounted", so the share never entered the record of what to put
  back; `post` then rebuilt that record from the live mount table, which no
  longer named it, and announced `cifs: all shares are back` 0.14 s later over
  the shares that were left. The record is now written **before** the first
  unmount, and a failed `umount` is checked against the mount table instead of
  believed. Observed four times (2026-10-23 05:56 and 19:45, 2026-10-25 14:04
  and 16:41); the 2026-10-23 case left `/mnt/tmcap2` down for 4 h 31 min.
- **The CIFS messages name the shares they checked.** `all shares are back`
  now lists them, `gave up` lists the ones still down, and a share that is
  still owed stays in the record for the next sleep instead of being forgotten
  by the next `pre`.
- **`cifs: … not remounted; it will come back on next access` no longer
  promises an automount.** Nothing touches a plain `.mount` share on its own;
  the sentence belongs to the `x-systemd.automount` case. Measured 2026-10-26
  00:05: the message appeared twice and the share came back because the retry
  loop tried again, not because anything accessed it. The line now says only
  `not remounted yet`, and `gave up` says the next sleep will try again instead
  of saying that something touching the share will.

## [0.1.1] - 2026-10-20

### Fixed

- **The post-resume helpers were killed with the sleep unit.** The CIFS
  reconnect ran as a plain detached child, still inside
  `systemd-suspend.service`; `KillMode=control-group` killed it when the hook
  returned, so a share stayed unmounted until something else touched it. The
  reconnect and the Wi-Fi check now run as their own transient units
  (`systemd-run --collect --no-block`). Verified on a real sleep: S3 573.422 s,
  the helper survived, retried while the network came back, and remounted the
  share.

### Added

- `VERSION` is the single source of the project version. `mbp-sleep --version`
  prints it, `install.sh` installs it, and a release is the tag
  `v$(cat VERSION)`.

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
