# mbp-sleep

**Sleep and wake handling for a MacBook Pro (Retina, 13-inch, Early 2015 —
`MacBookPro12,1`) on Linux.** It makes the machine sleep when asked, wake when
asked, and keep its network afterwards.

It is one small daemon plus one systemd sleep hook and one configuration file.
No kernel module, no patched kernel.

## The problems it solves

Most of these share one pattern: **something was still attached when the machine
went to sleep.** Taking it off before sleep — and putting it back afterwards — is
what the program does, and it is what makes the cycles complete. The wake-source
row is the exception: there, the firmware itself leaves a source disabled.

| symptom | what is happening | what this program does |
|---|---|---|
| **It never finishes going to sleep.** The screen goes black and the machine sits there. | A network share with unwritten data whose server is gone blocks `sync_filesystem()`. Measured in this machine's journal: **194.646 s** and **95.554 s** in `Filesystems sync`, against **0.014–0.031 s** once the share was unmounted first. | Unmounts network filesystems before sleep and remounts them after. |
| **Suspend is aborted and the machine stays awake.** The journal says `PM: suspend entry`, then `-EIO`. | The Wi-Fi driver was not in a state where it could be suspended; the failure of one device aborts the whole transaction. | Disconnects Wi-Fi and unloads the driver before sleep, reloads it after resume. A driver that is not loaded cannot refuse. |
| **It sleeps but never comes back.** It is powered, but the screen stays dark and no key does anything. | On this machine the device that made the difference was the **Thunderbolt Ethernet adapter**: with it attached across sleep, resumes did not complete; taken off the bus before sleep, they do. The detailed resume-path explanation this project used to give is **not re-verifiable from the journals it still has** — treat it as a hypothesis, not a finding. | De-authorises the adapter's own Thunderbolt endpoint before sleep and re-authorises it on resume. The Thunderbolt host controller is never touched, so the adapter keeps working. |
| **It wakes, but Wi-Fi or network shares are gone.** | The driver came back without a usable radio, or the shares were unmounted on the way in and nothing put them back. | Reloads the Wi-Fi driver, waits for the interface, and re-mounts the shares with retries until the network is up. |
| **A backup is killed by a sleep**, or a sleep requested during a backup is lost. | The desktop suspends in the middle of the job. | Holds a logind block lock while a backup runs, remembers the suspend request, and issues it again when the backup ends. |
| **Keyboard and lid cannot wake the machine.** | `/proc/acpi/wakeup` is rebuilt at every boot, and this firmware declares the internal keyboard/touchpad source (`SPIT`) disabled. | Re-arms the configured wake sources at daemon start. It never disables one. |

**If the machine wakes by itself a few seconds after sleeping**, this program
does not suppress that. It tells you whether the cycle was a wake and where it
stopped, and you can attribute the wake by taking a snapshot of
`/sys/class/wakeup/*/event_count` immediately before and after a run — the kernel
does not record the wake source in the journal. One candidate for this model —
the EC's GPE `0x4E` — was investigated and **never confirmed**; see
`docs/background.md`.

## Which machines

Written and tested on a **MacBookPro12,1** (13-inch Early 2015). The Wi-Fi,
Thunderbolt and wake-source parts are Apple-specific:

| part | applies to |
|---|---|
| `brcmfmac` suspend refusal, Wi-Fi reload | Apple laptops with a Broadcom Wi-Fi card |
| Thunderbolt Ethernet endpoint | the Apple Thunderbolt→Gigabit Ethernet adapter; the mechanism is the same for other Thunderbolt NICs |
| `SPIT` wake source | Macs whose firmware declares the internal keyboard source disabled |
| network filesystems, backup deferral, report, lid handling | **any laptop** running systemd — these parts are not Apple-specific |

Every behaviour is a switch in one configuration file, so the parts that do not
apply to your machine can be turned off.

## Requirements

- Linux with systemd (tested with systemd 262) and Python 3.10 or newer.
- NetworkManager — only for the Wi-Fi detach (`nmcli`).
- `dbus-monitor` — only for noticing a suspend request made during a backup.
- polkit — only for the optional "do not offer to force a suspend past the lock"
  rule.
- util-linux, kmod, systemd: `mount`, `umount`, `modprobe`, `systemctl`,
  `journalctl`.

Nothing is needed from the desktop environment.

## Install

Needs root; the script re-executes itself through `pkexec` if you are not root.

```sh
git clone git@github.com:cphotor/mbp-sleep.git
cd mbp-sleep
sudo ./install.sh          # or: pkexec ./install.sh
```

It installs:

| path | what |
|---|---|
| `/usr/local/sbin/mbp-sleep` | the program |
| `/etc/systemd/system/mbp-sleep.service` | the daemon (wake sources, lid, backup lock) |
| `/usr/lib/systemd/system-sleep/50-mbp-sleep` | the sleep hook (this systemd reads only `/usr/lib/...`) |
| `/etc/systemd/logind.conf.d/50-mbp-sleep.conf` | logind ignores the lid, so this program handles it |
| `/etc/systemd/system/systemd-suspend.service.d/10-no-freeze.conf` | user sessions are not frozen before sleep (`freeze_sessions`) |
| `/etc/mbp-sleep.conf` | the configuration, **only if it does not exist yet** |
| `/etc/polkit-1/rules.d/49-mbp-sleep-no-force-suspend.rules` | generated when `silence_force_prompt = on` |

Anything it replaces is copied to `/var/backups/mbp-sleep/<timestamp>/` with a
`manifest.tsv`, so `uninstall.sh` can put it back. An existing
`/etc/mbp-sleep.conf` is **never overwritten**; if the shipped defaults have
gained a switch, the installer prints which ones are missing.

## Check that it works

```sh
mbp-sleep status       # switches in effect, wake sources, Wi-Fi, adapter, mounts
mbp-sleep dry-run      # what the next suspend would do, without doing it
```

Then suspend — from the menu, the lid, or the key — and wake it again, and ask:

```sh
mbp-sleep report --boot 0        # --boot -1 for the previous boot
```

It answers, for every cycle in that boot: **did it sleep, where did it stop if
not, and was it a wake.** The wake source itself is not in the journal — take a
`/sys/class/wakeup/*/event_count` snapshot around a run for that. If a cycle goes
wrong, that output is the thing to attach to a report.

## Configuration

The live file is `/etc/mbp-sleep.conf`. `macbook.conf` in this repository is the
same file with every option commented — it is the reference for the defaults,
and any key you delete falls back to the default compiled into the program, so a
partial file is not a broken file.

Format: `key = value`. `#` starts a comment. Blank lines are ignored.

### When an edit takes effect

| keys | read by | to apply an edit |
|---|---|---|
| `wake_sources`, `wake_devices`, `defer_on_backup`, `backup_names`, `defer_max_wait`, `silence_force_prompt`, `lid_watch`, `lid_state` | the daemon, once at start | `sudo systemctl restart mbp-sleep` |
| `wifi_*`, `thunderbolt_*`, `cifs_*`, `network_fstypes` | the sleep hook, on every sleep | nothing — the next suspend uses it |
| `freeze_sessions` | `install.sh` | re-run `sudo ./install.sh` |

Editing `macbook.conf` in the repository changes nothing on the machine; it is a
template for the first install.

### Wake sources

| key | default | meaning |
|---|---|---|
| `wake_sources` | `on` | re-apply the wake-source state at every daemon start |
| `wake_devices` | `SPIT XHC1 LID0` | the ACPI devices to keep **enabled**: internal keyboard/EC, USB, lid |

### Wi-Fi

| key | default | meaning |
|---|---|---|
| `wifi_detach` | `on` | disconnect and unload the driver before sleeping |
| `wifi_interface` | `wlan0` | interface to disconnect |
| `wifi_modules` | `brcmfmac_wcc brcmfmac` | modules to unload, **in this order** (reversed, `brcmfmac` reports "in use") |
| `wifi_restore_wait` | `20` | seconds to wait for the interface to reconnect after the driver is loaded |

### Thunderbolt Ethernet

| key | default | meaning |
|---|---|---|
| `thunderbolt_eject` | `on` | de-authorise the adapter's endpoint before sleep, re-authorise on resume. The host controller `0-0` is skipped by name — de-authorising it removes the whole Thunderbolt router |
| `thunderbolt_name` | `Thunderbolt to Gigabit Ethernet Adapter` | product string used to find the endpoint |
| `thunderbolt_settle` | `2` | seconds to wait before re-authorising |

### Network filesystems

| key | default | meaning |
|---|---|---|
| `cifs_unmount` | `on` | unmount network filesystems before sleep, remount after |
| `cifs_auto` | `on` | discover mounts from `/proc/mounts` by type — no share names needed anywhere |
| `network_fstypes` | `cifs smb3 nfs nfs4 fuse.sshfs` | which filesystem types count as "network" |
| `cifs_shares` | *(empty)* | only read when `cifs_auto = off`: share names under `cifs_root` |
| `cifs_root` | `/mnt` | prefix for `cifs_shares` |
| `cifs_umount_wait` | `15` | seconds per mount before giving up; a lazy unmount is never used |
| `cifs_reconnect_wait` | `120` | seconds to keep retrying after resume — the network is not up when the hook runs |

An idle `x-systemd.automount` share is invisible to this: its mount point
carries `autofs`, not `cifs`, so it is left alone and comes back the next time
something touches it.

### Backups

| key | default | meaning |
|---|---|---|
| `defer_on_backup` | `on` | hold a logind block lock while a backup runs |
| `backup_names` | `borg` | program names that count as a backup, matched against `argv` |
| `defer_max_wait` | `3600` | safety valve: a backup older than this is treated as hung, the lock is released and the machine may sleep |
| `silence_force_prompt` | `on` | write the polkit rule that denies `org.freedesktop.login1.suspend-ignore-inhibit`, so the desktop does not offer a password to force a suspend past the lock |

A suspend requested while the lock is held is **held, not lost**: it is
remembered and re-issued when the backup ends, so the machine suspends by
itself. To suspend immediately, stop the lock: `sudo systemctl stop mbp-sleep`.

### Lid and session freeze

| key | default | meaning |
|---|---|---|
| `lid_watch` | `on` | handle the lid here, because logind is told to ignore it |
| `lid_state` | `/proc/acpi/button/lid/LID0/state` | where the lid state is read |
| `freeze_sessions` | `off` | `off` installs the drop-in that sets `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` |

## Commands

| command | what it does |
|---|---|
| `mbp-sleep status` | switches in effect, wake sources, Wi-Fi, adapter, mounts, whether a backup is running and whether a suspend is being deferred |
| `mbp-sleep dry-run` | print every pre-suspend and post-resume step without performing it |
| `mbp-sleep report --boot N` | the four questions, for every cycle in boot `N` (`-1` = previous boot) |
| `mbp-sleep cifs-reconnect` | wait for the network and remount the shares taken down before sleep |
| `mbp-sleep wake` | re-apply the wake sources |
| `mbp-sleep pre` / `post` | what the sleep hook calls; not for interactive use |

Run them with `sudo` when they need `/sys`, `/proc/acpi/wakeup` or the mount
table.

## Uninstall

```sh
sudo ./uninstall.sh
```

Stops and disables the service, removes the unit, the hook, the program, the two
drop-ins, the configuration and the generated polkit rule, reloads logind so the
lid works normally again, and restores what `install.sh` moved aside. To restore
a specific backup:

```sh
sudo ./uninstall.sh --restore /var/backups/mbp-sleep/20261020-180946
```

The polkit rule is removed only if it carries the `generated by mbp-sleep`
marker, so a rule written by hand is never touched.

## If it still fails

1. `mbp-sleep status` — is the daemon running, are the switches what you expect,
   is the adapter/interface/mount the one you think?
2. `mbp-sleep dry-run` — does the plan match what you expect?
3. `mbp-sleep report --boot 0` — did the machine actually sleep, and if not,
   which step was last?
4. Turn off what does not apply: `wifi_detach`, `thunderbolt_eject`,
   `cifs_unmount` are independent switches. A machine without a Thunderbolt
   adapter should keep `thunderbolt_eject = off`.
5. The journal is the source of truth: `journalctl -b -o short-monotonic |
   grep -i -E 'PM: suspend|Restarting tasks|Filesystems sync'`.

**Hibernation is not supported.** Nothing here runs for `hibernate.target`, and
hibernation does not work on this hardware as configured.

## How it works

- The **sleep hook** (`/usr/lib/systemd/system-sleep/50-mbp-sleep`) runs
  `mbp-sleep pre` before `suspend(2)` and `mbp-sleep post` after resume. It never
  fails the sleep: a sleep that could not be prepared is still better than a
  machine that refuses to sleep.
- The **daemon** owns the long-lived state: wake sources, the lid, and the logind
  block lock that defers sleep during a backup.
- It writes nothing outside `/run/mbp-sleep/`, `/var/backups/mbp-sleep/` and the
  generated polkit rule.

## More

- `docs/background.md` — why these failures happen, what was measured, and what
  is not worth re-testing on this hardware.
- `docs/config-changes.md` — every change this project made to the machine it
  was developed on, with an undo.
- `AGENTS.md` — the rules used when working on this repository.

## License

MIT — see `LICENSE`. Copyright (c) 2026 cphotor.
