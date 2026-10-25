# docs/config-changes.md — every change made to this machine

> **This file is the authoritative, append-only record of configuration changes
> made to the machine by this project or on the operator's instruction.**
>
> Required by AGENTS.md rule 4.3 and §4.3a. If a change is made and it is not in
> this file, it did not get recorded properly.
>
> Scope: **one entry per configuration change, and nothing else.** This file is
> a log of what was changed, not a snapshot of the machine. It deliberately
> carries no "current state" table: state goes stale the moment something
> changes elsewhere, and a stale table is worse than no table. For what the
> machine looks like *now*, read the live machine (`/proc/acpi/wakeup`,
> `/sys/power/`, `systemctl`) and `README.md`.
>
> Every entry carries the four things rule 4.3 demands: **what** (exactly enough
> to undo it), **where** it lives, **why**, and **whether it worked**.

> **Note, 2026-10-20.** The investigation documents (`docs/progress.md`,
> `docs/diagnosis.md`, `docs/root-cause-plan.md`, `docs/investigation-state.md`,
> `docs/systemd-freeze-dropin.md`) were pruned from the tree. Entries below still
> cite them, because they were written when those files existed and this file is
> append-only. Each is readable from the local `local-history` branch, e.g.
> `git show local-history:docs/progress.md`. The summary of what the investigation
> established is `docs/background.md`.
>
> Two further 2026-10-20 changes are visible in the entries below: `AGENTS.md`
> was condensed, so its section numbers quoted here do not match the current
> file, and share names, the access point, the LAN address and the hostname were
> replaced with placeholders (`shareA`-`shareD`, `192.0.2.102`, `host`) before
> publication. Behaviour, ordering and timestamps are unchanged.

---

## How to read this

| column | meaning |
|---|---|
| When | the time the change was written to the machine (file mtime where applicable), not when it was decided |
| Undo | the exact command that puts the machine back the way it was |
| Worked | **leave it empty until it has been observed.** A change that has not been exercised is `not yet tested`, not `yes` |

A change that was reverted still gets an entry, marked `reverted`. "It is gone
now" is not discoverable by a reader six hours later, and "did anyone try this?"
has no other source.

Entries are **never edited to look better**. A change that turned out to be
wrong gets a retraction underneath it, not a rewrite.

---

## C1 — systemd suspend freeze drop-in

| | |
|---|---|
| **When** | 2026-10-19 00:30:05 |
| **What** | new file, 330 bytes, mode 0644, with 3 comment lines and then:<br>`[Service]`<br>`Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` |
| **Where** | `/etc/systemd/system/systemd-suspend.service.d/10-no-freeze.conf` |
| **Why** | the operator's long-term setting, recorded in their notes vault under `~/sync/notes/` (the file titled "MacBook Pro 2015 — installing Linux, suspend and wake" in the hardware folder; its filename is in Chinese and is deliberately not quoted here, per AGENTS.md rule 0) §4.1 and §10, and in AGENTS.md §5.1. The reinstall of 2026-10-18 deleted it. Tells systemd **not** to freeze user sessions before the sleep target |
| **Applied by** | `pkexec sh -c ...` — one graphical authorisation. `systemctl daemon-reload` in the same transaction |
| **Backed up** | nothing to back up, the file did not exist. The installer copies any existing file to `<name>.bak.YYYYMMDD-HHMMSS` before replacing it, so re-running it is safe |
| **Verified** | `systemctl show systemd-suspend.service -p Environment` → `Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` |
| **Worked** | **not yet tested.** No measurement of what it does on this install. What it is claimed to do (raise suspend success rate) was measured on the *previous* install with the Thunderbolt Ethernet adapter plugged in, which was the dominant fault at the time — see AGENTS.md §0c.0, so that figure is not established |
| **Undo** | `rm /etc/systemd/system/systemd-suspend.service.d/10-no-freeze.conf && systemctl daemon-reload` |

Not related to hibernation. `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS` affects
`systemd-suspend.service` only.

---

## C2 — internal keyboard and trackpad wake enabled, and made persistent

Two writes, one requirement. Without the second, the first is undone by the next
reboot.

### C2a — runtime arming

| | |
|---|---|
| **When** | 2026-10-19 ~00:36 |
| **What** | `SPIT` toggled from `*disabled` to `*enabled` in the ACPI wake list. `XHC1` and `LID0` were named on the same command and both reported `already enabled` — nothing was written for them |
| **Where** | `/proc/acpi/wakeup`, via `scripts/set-wake.sh on SPIT XHC1 LID0` (the script re-execs itself through `pkexec`) |
| **Why** | AGENTS.md rule 3: never reduce this machine to power-button-only wake. `SPIT` is the firmware-declared wake source for the internal keyboard/touchpad and it comes back `*disabled` on every boot |
| **Verified** | read back `SPIT S3 *enabled` |
| **Worked** | **not yet tested.** "Enabled" is a configuration fact, not a wake. No physical keypress wake has been observed on this install |
| **Undo** | `./scripts/set-wake.sh off SPIT` |

Note: writing a device name to `/proc/acpi/wakeup` **toggles** it, it does not
set it. That is why the script reads first and writes only on a real change.
Anyone running the internet's `echo XHC1 > /proc/acpi/wakeup` twice inverts it.

### C2b — persistence across reboots

| | |
|---|---|
| **When** | 2026-10-19 00:36:44 |
| **What** | unit installed 0644 and `enable`d (symlink into `/etc/systemd/system/multi-user.target.wants/`) |
| **Where** | `/etc/systemd/system/mbp-wakeup.service`, copied verbatim from `files/mbp-wakeup.service` in this repository |
| **Why** | `/proc/acpi/wakeup` is rebuilt from the firmware's `_PRW`/`_STA` at every boot, so C2a does not survive a reboot. The unit is `After=sysinit.target`, `Before=sleep.target`, so the sources are armed before any sleep operation |
| **What it runs** | `ExecStart=<repository>/scripts/set-wake.sh on SPIT XHC1 LID0` |
| **Verified** | `systemctl is-enabled` → `enabled`; ran once on enable, `status=0/SUCCESS`, output `SPIT S3 *enabled` / `XHC1 S3 *enabled` / `LID0 S4 *enabled` |
| **Worked** | **not yet tested across a reboot.** The enable-time run is not evidence that it survives; only a reboot is |
| **Undo** | `systemctl disable --now mbp-wakeup.service && rm /etc/systemd/system/mbp-wakeup.service` |

**Known dependency, stated because it will fail silently.** `ExecStart=` and
`Documentation=` are absolute paths into the repository tree. If that tree is
moved or deleted, the unit fails at every boot and the wake sources revert
silently to the firmware default. `set-wake.sh` is self-contained — its only use of its own
location is re-`exec`ing itself as root — so copying it to `/usr/local/sbin/`
and pointing the unit there would remove the dependency. Not done; not asked for.

---

---

## C3 — automatic brcmfmac recovery after a resume

| | |
|---|---|
| **When** | 2026-10-19 01:05 |
| **What** | two new files: a recovery script (0755) and a oneshot unit (0644), and the unit `enable`d (four symlinks: `suspend.target.wants`, `hibernate.target.wants`, `hybrid-sleep.target.wants`, `suspend-then-hibernate.target.wants`) |
| **Where** | `/usr/local/bin/brcmfmac-resume-recover` (copy of `files/brcmfmac-resume-recover` in this repository) and `/etc/systemd/system/brcmfmac-resume-recover.service` |
| **Why** | after a resume the BCM43602 firmware sometimes stops answering the host and `brcmfmac` is functionally dead — 43 `Timeout on response for query command` in one cycle, Wi-Fi unusable until the module is reloaded. Upstream kernel bug 196019 (dup 178601), open since 2017, no upstream fix. Reloading the module recovers it every time, verified once on this machine |
| **Backed up** | nothing to back up, neither file existed |
| **Verified** | `systemctl is-enabled` → `enabled`; the unit's `ConditionPathExists` is satisfied on this machine; the script was run once by hand and exited 0 on its first guard (`wifi radio is off, leaving it alone`) |
| **Worked** | **yes — verified unattended on 2026-10-19 01:12.** A suspend cycle wedged the card; the script detected the firmware timeouts, reloaded the module, restored the radio and reconnected to the access point **5 s after the reload**, with nobody intervening. `/var/log/brcmfmac-resume-recover.log` and `docs/progress.md` §150 have the timeline. The module reload itself had already been verified by hand at 01:00:29 (§147.4) |
| **Undo** | `systemctl disable --now brcmfmac-resume-recover.service && rm /etc/systemd/system/brcmfmac-resume-recover.service /usr/local/bin/brcmfmac-resume-recover` |

**How it decides.** It waits 15 s for NetworkManager to reconnect on its own. If
it has not, it looks for the **wedge signature** — `brcmf_msgbuf_query_dcmd:
Timeout on response` in the last 5 minutes of kernel log — and reloads only if
that is there. A reload drops the association and makes NetworkManager re-scan,
so doing it on every resume forever is a tax for a bug that may be fixed upstream.

**Changed 2026-10-19 01:20, after the operator corrected §147.4.** The first
version exited immediately whenever `nmcli radio wifi` read `disabled`. On this
machine the radio goes off *as a consequence* of the wedge, so that guard would
have fired on every occurrence and the script would never have reloaded anything
— it would have been dead code on the exact failure it was installed for, and its
log line would have said so in a way that looks like correct behaviour. The
discriminator is now the firmware not answering, which is what actually
distinguishes a broken card from a card that is merely not connected. Reloading
the module does not switch the radio on, so a genuinely switched-off card is
reloaded for nothing and no setting is changed.

**It restores the radio to its pre-suspend state, changed 2026-10-19 01:35.**
Operator: *"switch it on automatically — however it was before sleeping is how it
must be after waking."* After a reload the script therefore reads the radio's
pre-suspend state back out of the journal — did NetworkManager have `wlan0`
`activated` before the last `PM: suspend exit` — and issues `nmcli radio wifi on`
only if it did. It does **not** switch the radio on unconditionally: Wi-Fi that
was deliberately off before the suspend (Ethernet session, saving power) stays
off. The current radio state is deliberately not used as the answer, because on
this machine the wedge is what switches it off, so it is precisely the thing that
cannot be trusted.

`was_wifi_in_use()` was unit-tested against this boot: it finds
`device (wlan0): state change: secondaries -> activated` at 21:50:06, before the
00:46:29 resume, and returns true. The rest of the branch needs a real wedged
resume to exercise.

**A service, not a `system-sleep` hook.** Sleep hooks run synchronously inside
the sleep transaction, so waiting in one delays the resume of every user on the
machine. This unit is `After=suspend.target` and never `Before=`, so it is only
reached once the machine is already back and nothing waits for it.

**It does not unload the module before suspend.** AGENTS.md §5.2 records that
doing so made the resume path hang — though §0c.0 notes that experiment ran with
the Ethernet adapter plugged in, so it is not trustworthy. §147.5 lists the
alternatives that were rejected and why.

**Log:** `/var/log/brcmfmac-resume-recover.log` — one line per run, stating
whether a reload happened and, if so, whether Wi-Fi came back.

## C4 — kernel log level raised to 7 (runtime, not persistent)

**What.** `/proc/sys/kernel/printk` set from `3 4 1 4` to `7 4 1 7`.
`console_loglevel 3 -> 7`, `default_message_loglevel 1 -> 7`.

**Where.** `/proc/sys/kernel/printk`. Runtime only — **nothing on disk was
touched**, and this does not survive a reboot. There is no `printk.*` sysctl drop-in
in `/etc/sysctl.d/`, and none was added; the value after the next reboot is again
whatever the kernel and `systemd` set.

**Why.** Level 3 prints `KERN_ERR` and above only. Every kernel line that
answers AGENTS.md §0a.7's questions 1 and 2 — `Filesystems sync`,
`Preparing to enter system sleep state S3`, `Freezing user space processes` — is
`KERN_INFO`. `scripts/run-report.sh` counts exactly those lines, so at level 3 it
cannot answer Q1 or Q2 at all. This is the same defect recorded in
`docs/investigation-state.md` §2.4: it cost the project a day before, and the
2026-10-18 reinstall silently restored the default.

**Cost.** Verbose kernel logging only. No functional effect on suspend, and
nothing reads the log between runs.

**Verified.** Read back immediately: `cat /proc/sys/kernel/printk` prints
`7	4	1	7`.

**Worked.** Not yet tested — the change was made immediately before the
operator's own suspend test of 2026-10-19, whose result is not in yet.

**Undo.** `pkexec sh -c 'echo "3 4 1 4" > /proc/sys/kernel/printk'` (or `sudo`
with a valid ticket). To make it permanent instead, a
`/etc/sysctl.d/60-printk.conf` containing `kernel.printk = 7 4 1 7` — **not
done, deliberately**: a persistent change needs its own decision and its own
entry.

## C5 — Thunderbolt Ethernet endpoint deauthorized around sleep (TRIAL, reversible)

**What.** One new file,
`/usr/lib/systemd/system-sleep/50-thunderbolt-ethernet-deauth` (mode 0755,
root:root, 2149 bytes). Installed 2026-10-19 12:02. Source kept in the
repository at `files/system-sleep/50-thunderbolt-ethernet-deauth`.

The hook walks `/sys/bus/thunderbolt/devices/*/`, keeps only entries whose
`device_name` contains `Thunderbolt to Gigabit Ethernet Adapter` (on this machine
that is `0-1`), **skips `0-0`** (the host controller), and writes `0` to that
endpoint's `authorized` in the `pre` phase and `1` in the `post` phase (after a
2-second settle). It always exits 0 and ignores write failures, so it can never
fail the sleep transaction.

**Where.** `/usr/lib/systemd/system-sleep/` — the only directory this systemd
reads (AGENTS.md §5.4). It was **empty** before this: the `10-brcfmac-hibernate`
hook did not survive the 2026-10-18 reinstall (§142).

**Why.** Eight sleep cycles this session, seven clean and one wedge, and the
Thunderbolt Ethernet adapter is the only tracked variable that separates them,
with the CIFS mount held constant across both sides
(`docs/progress.md` §158.1). The hook removes that variable before the machine
sleeps, to find out whether the wedge survives its absence. Planned as
`docs/root-cause-plan.md` **Step 11**, at the operator's request.

**This is a trial and is expected to be reverted.** The operator's instruction
was to record it here first and decide keep-or-remove **after** testing. It is
not a fix, and nothing in it explains the fault.

**Two corrections to the published script it is based on**
(<https://zzamboni.org/post/fixing-wake-from-sleep-in-linux-on-a-mac-when-using-ethernet/>):

1. That script selects devices by `[ -w .../authorized ]`, which as root is also
   true for `0-0`. Writing `0` to `0-0/authorized` deauthorizes the entire
   Thunderbolt host router. This one matches on `device_name` and skips `0-0`.
2. It uses `/lib/systemd/system-sleep/`, which on this system is a symlink to
   the same place; the real path is recorded above so the undo is unambiguous.

**Verified at install time, before any sleep:**

| step | observed |
|---|---|
| before | `ens9` UP `192.0.2.102/24`; `lspci` shows `0a:00.0` NetXtreme BCM57762; TB devices `0-0 0-1 domain0` |
| `echo 0 > 0-1/authorized` | `ens9` **does not exist**; `lspci` netxtreme count **0**; `0-1` still present in sysfs, deauthorized |
| `echo 1 > 0-1/authorized` | `ens9` **UP `192.0.2.102/24` again**, `carrier=1`, `0a:00.0` back in `lspci`, `0-1/authorized=1`, `nmcli`: `ens9:connected` |

**Worked.** `not yet tested` — no sleep has been attempted with the hook in
place. The round trip above proves only that the endpoint can be removed and
restored; it says nothing about the hang.

**Cost.** Every suspend now removes and restores the Ethernet adapter. If the
`post` phase ever fails, `ens9` stays gone until the adapter is unplugged and
replugged by hand. `systemd-cat -t tb-ethernet-deauth` logs every action.

**Rule 3.** Not breached. The `thunderbolt` module stays loaded and enabled, the
adapter is enumerated across every normal boot, and nothing is removed from the
machine. This is not the "blacklist thunderbolt" recipe that MacBook write-ups
recommend and that rule 3 forbids.

**Undo.**

```sh
pkexec rm /usr/lib/systemd/system-sleep/50-thunderbolt-ethernet-deauth
```

Immediate, no reboot. The hook has no other trace on the machine.

**Known dependency.** If the adapter is absent, or if some other component
re-authorizes Thunderbolt endpoints, the `post` phase may find nothing to
restore. The exit-0-and-ignore behaviour means this fails silently toward
"ethernet absent", not toward "sleep broken" — check
`journalctl -t tb-ethernet-deauth` if `ens9` does not come back.

### C5 update 1 — `Worked`, filled in

The `**Worked.**` line above says `not yet tested`, which was true when written
and is superseded by what follows. The hook was tested on 2026-10-19 (§159):

**Worked: partially, and not as intended.** The hook ran correctly every time
(3 `pre-suspend`, 3 `post-resume`, `0-0` never touched), the round trip worked,
and **2 clean sleeps with no wedge**. The base rate is 1 wedge in 5 attached
cycles, so that is **not** a demonstrated fix and was never recorded as one.

It also coincided with a symptom that had **not occurred once since the
2026-10-18 reinstall**: an **instant wake**, S3 residence 0.173 ms (§160). One
occurrence, n=1, not attributable to a specific device — the EC/LID0/ADP1 group
moved, but the operator's hands were on the machine. **Causality is not
established.**

### C5 update 2 — REVERTED, at the operator's instruction, 2026-10-19 13:06

```sh
pkexec rm /usr/lib/systemd/system-sleep/50-thunderbolt-ethernet-deauth
```

Verified: `/usr/lib/systemd/system-sleep/` is **empty** again; `ens9` is UP on
`192.0.2.102/24` with `carrier=1`; `0-1/authorized=1`; `0a:00.0` present in
`lspci`. No reboot was needed and none was done. The undo was exactly as written
in the entry above.

**Why.** The operator's reason: the machine now wakes instantly, and that did
not happen between the 2026-10-18 reinstall and 13:02 today. The association in
time is strong — the hook went in at 12:02, the instant wake happened at 13:02,
nothing else was changed — and **the cost of keeping it is unacceptable**, even
though the instant wake is n=1 and the wedge rate is only 1-in-5.

**What this does and does not mean.** The instant wake was **not attributed**
(§160.1: n=1, and that counter group cannot identify a single device). So **this
is not a demonstration that the hook caused the instant wake.** It is a
demonstration that the operator will not leave it installed while it is
unexplained. The wedge question returns to exactly where §158 left it:
unresolved, and with no instrumentation in place to catch it.

The hook did **not** cause the brcmfmac refusal (§159.4: the Wi-Fi was already
timing out 7 s before the deauthorize).

**The repository copy `files/system-sleep/50-thunderbolt-ethernet-deauth` is
kept**, deliberately: it is the only version of this that has run on hardware,
it documents the `0-0` hazard, and it is not installed. It is not on the machine
and nothing loads it.

## C6 — appindicator extension: `GLib.log_structured` replaced with `console.warn`

**What.** One line changed in one file:
`~/.local/share/gnome-shell/extensions/appindicatorsupport@rgcjonas.gmail.com/logger.js`,
line 59, inside `Logger._logStructured()`:

```js
-        GLib.log_structured(Logger._domain, logLevel, Object.assign(fields, extraFields));
+        console.warn(`${Logger._domain}: ${message}`);
```

A comment was added immediately above it explaining why. Nothing else in the
file changed.

**Backup.** `logger.js.bak-20261019-135000`, same directory. Verified with
`diff`: the only difference between it and the live file is the one line plus the
comment.

**Where.** The user's own home directory. **No root, no system file, no package
is involved.** The GNOME package `gnome-shell-extension-appindicator` is **not**
installed on this machine and was **not** installed by this change.

**Why.** `g_log_structured()`'s third parameter is `const gchar **fields` — a
NULL-terminated array of alternating key/value strings. The extension passed a
**plain JS object**. That is a GObject-introspection marshalling mismatch, and
it is reached on **every** `Util.Logger.*` call: 19 call sites in
`appIndicator.js`, all funnelling through this one function. On the boot where
gnome-shell crashed (2026-10-19 13:10:12, SIGSEGV in `g_object_unref`) the
journal holds **540** log lines from this extension and **870**
`g_object_unref: assertion 'G_IS_OBJECT (object)' failed`. Upstream issue
<https://github.com/ubuntu/gnome-shell-extension-appindicator/issues/540> is
open, describes the same crash, and has no fix.

**Why this file.** Logging is the only thing this module does. No tray-icon
code, signal wiring or icon lifecycle is touched, so the extension keeps
working and the operator keeps the notification-area icons they need for fcitx5
and Clash Verge. §11.3(a) patched a single call in `appIndicator.js` in
October; that patch was lost in the 2026-10-18 reinstall, and there are 19 such
calls — this is the same idea applied at the single choke point.

**Verified.** The change is syntactically valid JavaScript; `GLib` is still
referenced 12 times elsewhere in the file so the import stays used; `logLevel`
is still used by the guard clauses above. **No syntax checker was available on
the machine** (`node` is not installed); GJS parses the file at the next login,
and that parse is itself the first verification.

**Cost.** Extension log messages appear in the journal as plain
`AppIndicator-and-KStatusNotifierItem-Support: <message>` lines instead of
structured ones, and `G_MESSAGES_DEBUG` no longer changes their verbosity. No
functional change to any icon.

**Worked.** `not yet tested` — **a logout/login is required before it takes
effect**, because gnome-shell has already loaded the extension. The criterion is
free: after the next login, `journalctl -b | grep -c appIndicator.js` and
`journalctl -b | grep -c G_IS_OBJECT` should both be **0**, against 540 and 870
in the crashing boot. **If they are not zero this hypothesis is wrong**, and the
next candidate is the `indicatorStatusIcon.js` use-after-dispose path from issue
540.

**Undo.**

```sh
D=~/.local/share/gnome-shell/extensions/appindicatorsupport@rgcjonas.gmail.com
cp "$D/logger.js.bak-20261019-135000" "$D/logger.js"
```

Then log out and back in. Reinstalling the extension from the Extension Manager
overwrites the file entirely and removes both the patch and the backup.

**Known dependency.** A future update of the extension through the Extension
Manager **will overwrite this file and silently undo the patch**. No package is
involved, so nothing warns about it. If the crash returns, check this first.

**Relationship to the sleep work: none.** This is the §161 gnome-shell crash.
It is not the wedge (§157.2), not the brcmfmac D3 refusal (§159.2), and not the
instant wake (§160).

## C7 — `fcitx5-gtk` installed (fcitx5 GTK3/GTK4 IM module)

**When.** 2026-10-19, after 14:40. Installed by the operator, at the agent's
recommendation, as part of an input-method investigation that is **unrelated to
the sleep work**.

**What.** Package `fcitx5-gtk` 5.1.7-1 (Arch `extra`), which ships
`/usr/lib/gtk-3.0/3.0.0/immodules/im-fcitx5.so`,
`/usr/lib/gtk-4.0/4.0.0/immodules/libim-fcitx5.so`,
`/usr/lib/libFcitx5GClient.so`, and the two `fcitx5-gtk{3,4}-immodule-probing`
helpers. Verified with `pacman -Q fcitx5-gtk` and `pacman -Ql fcitx5-gtk`.

**Where.** The package files above, and — this is the part that makes the change
take effect — the session environment variable **`GTK_IM_MODULE=fcitx` in
`/etc/environment`**, which §11.3(b) added on 2026-10-15 and which has been in
effect ever since. **The variable was already there and is not part of this
change**; before this package existed, GTK silently ignored it because the IM
module was missing.

**Why.** With `GTK_IM_MODULE=fcitx` set but no module installed, GTK3/GTK4 apps
fell back to the native `zwp_text_input_v3` path, i.e.
`app → mutter → gnome-shell's JS ibus client → fcitx5 ibusfrontend`. fcitx5
itself documents that this path cannot position its own panel correctly
(`src/ui/classic/classicui.cpp:438-443`: *"If display is wayland, but frontend
is not, then we can only do X11 for now, though position is wrong ... The
position will be wrong anyway."*). The module moves the panel into the client
process, where GTK can position it against the parent surface.

**Worked.** **Partially, and it regressed something.** The candidate window is
now drawn by the client (`GtkPopover` under GTK4, `GtkWindow` type POPUP under
GTK3) instead of by fcitx5's own X11 window. The operator reports that **the
input-method theme stopped applying immediately** (the operator's words). Position
correctness was **not yet confirmed** by the operator. Neither the old nor the
new appearance has been characterised in `docs/progress.md` yet.

**Undo.**

```sh
pkexec pacman -R fcitx5-gtk
```

No logout is needed. `/etc/environment` needs no change: `GTK_IM_MODULE=fcitx`
is inert again once the module is gone. Already-running GTK apps must be
restarted in either direction.

**Known dependency.** The pacman database on this machine was **not synchronised**
before this install (§C-entry note: `database file for 'extra' does not exist`),
so the install was preceded by a sync and may have carried a wider system
upgrade with it; what else moved is **not recorded here** and would need
`pacman -Q` diffing against a dated snapshot to establish.

**Relationship to the sleep work: none.** No kernel module, no systemd unit, no
`/proc` or `/sys` write, no sleep-path configuration.

## C8 — GNOME accent colour baked into a custom fcitx5 theme

**When.** 2026-10-19, 16:00-16:01.

**What.** Two new files in `$HOME`, plus nothing else:

1. `~/.local/share/fcitx5/themes/gnome-accent/` — a copy of the system theme
   `/usr/share/fcitx5/themes/default/` (`theme.conf` plus `arrow.svg`,
   `next.svg`, `prev.svg`, `radio.svg`) with **exactly six colour values**
   changed, all from `#808080`/`#c0c0c0`/unset to `#9141acff`:
   `[InputPanel] HighlightBackgroundColor` (was unset, so the built-in default
   `#a5a5a5ff` applied), `[InputPanel/Highlight] Color`,
   `[InputPanel/Background] BorderColor`, `[Menu/Highlight] Color`,
   `[Menu/Background] BorderColor`, `[Menu/Separator] Color`.
2. `~/.config/fcitx5/conf/classicui.conf` — **this file did not exist before.**
   It contains `Theme=gnome-accent` and `UseAccentColor=False`, both at the
   top level with no INI section.

**Where.** `$HOME` only. No root, no `/etc`, no systemd, no `/sys`, no `/proc`.

**Why.** C7 (`fcitx5-gtk`) moved the candidate window into the client process,
and that regression was traced to a specific capability the GTK IM module does
not have: fcitx5's server-side renderer reads the desktop accent colour from the
XDG desktop portal (`org.freedesktop.appearance`/`accent-color`,
`src/ui/classic/classicui.cpp:237-243`) and substitutes it for every field named
in the theme's `[AccentColorField]` list (`Theme::populateColor`,
`src/ui/classic/theme.cpp:1184`). The installed `default/theme.conf` lists
`Input Panel Highlight Candidate Background` and `Input Panel Highlight` — the
candidate highlight background. `fcitx5-gtk` contains **no accent-colour code at
all** (zero matches for "accent" across the whole repository), so the
client-side renderer falls back to the theme's static value, which for
`HighlightBackgroundColor` is the built-in `#a5a5a5ff` grey. Baked into a
theme, the same colour is produced by both renderers.

**The accent colour is `#9141acff`**, read from this machine, not assumed:

```
$ gsettings get org.gnome.desktop.interface accent-color
'purple'
$ gdbus call --session --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.Settings.ReadOne \
    org.freedesktop.appearance accent-color
(<(0.56862747669219971, 0.25490197539329529, 0.67450982332229614)>,)
```

which is RGB(145, 65, 172). The matching text colour is white: fcitx5's
`accentForeground()` (`src/ui/classic/colorhelper.cpp:28`) returns white for any
accent with luma <= 0.5, and the theme's `HighlightColor`/`HighlightCandidateColor`
are already `#ffffff`, so no text colour needed changing.

**A custom theme name is required, not a user override of `default`.**
`Theme::load()` only reads a user-directory `theme.conf` when the theme is not
a system theme (`src/ui/classic/theme.cpp:1055`, `if (!isSystemTheme_)`), so
`~/.local/share/fcitx5/themes/default/theme.conf` would be ignored.

**Verified.** File contents read back and diffed against the system theme —
**exactly the six intended changes, no others** (see the change above). Both the
server and the client read `conf/classicui.conf` with top-level keys, so the
format is confirmed correct for both from the source: `ClassicUI::reloadConfig`
uses `readAsIni(config_, "conf/classicui.conf")` against a `Configuration` whose
options sit at the root, and the GTK client parses the same file with GKeyFile
after prepending a `[Group]` header. **Not yet verified visually** — whether the
candidate highlight renders purple is for the operator to confirm.

**Takes effect without a restart.** The GTK client monitors both
`conf/classicui.conf` and the loaded `theme.conf` and reloads on change
(`ClassicUIConfig::configChangedCallback`), so running applications pick this up
on their own.

**Worked.** `not yet tested` — pending the operator's visual check.

**Undo.** Delete both, no other file is touched:

```sh
rm -f ~/.config/fcitx5/conf/classicui.conf
rm -rf ~/.local/share/fcitx5/themes/gnome-accent
```

**Known dependency.** The accent colour is now a **hard-coded literal**. If the
GNOME accent colour is changed in Settings, GTK applications will keep the old
purple while any application still using fcitx5's server-side renderer with
`UseAccentColor=True` would have followed the change. With
`UseAccentColor=False` both sides now track the file, so neither follows the
system automatically. The fix after an accent change is to edit the six values
in `theme.conf`.

**Relationship to the sleep work: none.**

## C9 — `QT_IM_MODULES` set in `/etc/environment` so Qt apps stop going through mutter

**When.** 2026-10-19 16:19:22, edited by the operator.

**What.** One line added and one line commented out in `/etc/environment`:

```
 XMODIFIERS=@im=fcitx
 GTK_IM_MODULE=fcitx
+QT_IM_MODULES=fcitx;wayland;ibus
- QT_IM_MODULE=fcitx
+# QT_IM_MODULE=fcitx
```

The file is `root:root 0644`. **No backup file was made** — the previous content
was identical to the current one except for the two lines above, and is
reproduced verbatim above, so it can be restored by hand.

**Where.** `/etc/environment`, parsed by PAM's `pam_env`. Note that
`/usr/lib/environment.d/99-environment.conf` is a **symlink to this file**
(owned by the systemd package), so the systemd user manager picks the value up
through `systemd-environment-d-generator` as well; no second file needs editing.

**Why.** Qt 6.7 introduced `QT_IM_MODULES`, and Qt gives it absolute precedence
over `QT_IM_MODULE` (`src/gui/kernel/qplatforminputcontextfactory.cpp:33-46`,
qtbase dev): if `QT_IM_MODULES` is non-empty the function returns it immediately
and never reads the singular variable. The session's `QT_IM_MODULES` came from
`gnome-session` 51.0, `gnome-session/leader-main.c:161-170`:

```c
ibus_path = g_find_program_in_path ("ibus-daemon");
if (ibus_path) {
        /* For Qt 6.8 and newer */
        if (IS_STRING_EMPTY (g_getenv ("QT_IM_MODULES")))
                g_setenv ("QT_IM_MODULES", "wayland;ibus", TRUE);
```

so the value existed only because **nothing had ever set it** — the `ibus`
package merely needs to be installed for `g_find_program_in_path` to succeed.
Because the assignment is guarded by `IS_STRING_EMPTY`, setting it ourselves
permanently wins; `QT_IM_MODULE=fcitx` and `XMODIFIERS=@im=fcitx` were already
set and were not touched by gnome-session for the same reason.

Order is `fcitx` first, **not** the `wayland;fcitx;ibus` that the fcitx wiki
suggests generically: Qt takes the first plugin that loads
(`create(keys)`, same file), and `wayland` first would keep Qt apps on
`QtWaylandClient::QWaylandInputContext`, i.e. the mutter path whose popup
positioning C7/C8 exist to work around.

**Verified** by running fcitx5's own probe with the new value, no logout needed:

```
$ QT_IM_MODULES="fcitx;wayland;ibus" fcitx5-qt6-immodule-probing
QT_QPA_PLATFORM=wayland
QT_IM_MODULES="fcitx;wayland;ibus"
IM_MODULE_CLASSNAME=fcitx::QFcitxPlatformInputContext
```

against the current session's value, which yields
`IM_MODULE_CLASSNAME=QtWaylandClient::QWaylandInputContext`.

**Worked.** `not yet tested` — the operator has **not logged out**, so no running
process has the new environment. Criterion after the next login:
`fcitx5-diagnose`, section `qt6`, must report
`IM_MODULE_CLASSNAME=fcitx::QFcitxPlatformInputContext`, and the candidate window
in a Qt application must sit at the caret.

**Undo.**

```sh
# restore the previous behaviour
pkexec sed -i -e '/^# QT_IM_MODULE=fcitx$/d' -e '/^QT_IM_MODULES=/d' \
        -e '$a QT_IM_MODULE=fcitx' /etc/environment
```

**Known dependency.** Commenting out `QT_IM_MODULE` is **not required and is
slightly harmful**: Qt 6 ignores it anyway, but Qt 5 and Qt 4 — which do not read
`QT_IM_MODULES` at all, and which some proprietary applications bundle — lose
their only input-method hint. No `qt5-*` package is installed, so nothing on
this machine is affected today; the line should still be uncommented. This has
**not** been changed: the file is the operator's.

**Relationship to the sleep work: none.**

## C10 — Obsidian forced onto XWayland via `user-flags.conf`

**When.** 2026-10-19 16:35, on the operator's instruction.

**What.** New file `~/.config/obsidian/user-flags.conf`, containing one line:

```
--ozone-platform=x11
```

(plus comment lines describing why; the launcher strips lines starting with `#`).
**This file did not exist before.**

**Where.** `$HOME` only. The Obsidian launcher `/usr/bin/obsidian` — shipped by
the `obsidian` package and owned by it — reads exactly this path:

```bash
OBSIDIAN_USER_FLAGS_FILE="${XDG_CONFIG_HOME:-$HOME}/config/obsidian/user-flags.conf"
...
exec electron43 /usr/lib/obsidian/app.asar $OBSIDIAN_USER_FLAGS "$@"
```

so this was chosen over a `.desktop` override: it is the package's own supported
mechanism, survives package upgrades, and applies whether Obsidian is started
from the menu or from a terminal. A `.desktop` override would have had to be a
**copy** in `~/.local/share/applications/` and would only affect menu launches.

**Why.** `fcitx5-diagnose` reports Obsidian as `program:obsidian.desktop
frontend:ibus cap:12` — the input context arrives via mutter, i.e. the
Chromium native `text-input-v3` path, and mutter has no `zwp_input_panel_v1`,
so fcitx5 places its own X11 window using window-relative coordinates and the
panel lands up and to the left. GTK and Qt applications stopped hitting this in
C7/C9 because they now use fcitx's own GTK/Qt IM modules, which draw the panel
client-side; Chromium does not use the GTK IM module under Wayland. The same
`.desktop`-flag mechanism the operator used before (recorded in the personal
notes, "keys are dropped when typing fast in Chrome and Chromium applications") applies, with the flag
reversed: that note forces `--ozone-platform=wayland` because KWin supports the
native Wayland input-method protocol; on GNOME it must be `x11`.

**Worked.** `yes`, on the input-context evidence, pending the operator's visual
confirmation of the position.

Obsidian was fully restarted (new main process, started 16:37:24). The flag
reached Electron — both the main and the GPU child process show
`--ozone-platform=x11` in their command line:

```
$ tr '\0' ' ' < /proc/$(pgrep -f "obsidian/app.asar" | head -1)/cmdline
/usr/lib/electron43/electron --ozone-platform=x11 /usr/lib/obsidian/app.asar
```

**CORRECTION to the criterion first written here.** It predicted that
`fcitx5-diagnose` would "stop showing a `frontend:ibus` input context". **That was
wrong**, and grepping for `obsidian` after the restart still prints a
`frontend:ibus` line — but that line is a **stale leftover** from the previous
process, not the current one. The live input context is under a different program
name and a different group:

```
Group [wayland:] has 17 InputContext(s)
  IC [082749b9...] program:obsidian.desktop frontend:ibus   cap:52      focus:0   <- stale, old process
Group [x11::0] has 1 InputContext(s)
  IC [95cd8c19...] program:electron       frontend:dbus    cap:6000000032 focus:0 <- live
```

The live one is on `x11::0`, and its capability bitmap `0x6000000032` has bit 39
set — `CapabilityFlag::ClientSideInputPanel` (`src/lib/fcitx-utils/capabilityflags.h:70`)
— which is the flag that makes fcitx5 let the client draw its own panel. So under
XWayland, Chromium picks up the **GTK3 IM module** (present since C7), and the
panel is drawn client-side: correct position and the C8 theme, same as every other
GTK application.

**Do not judge this change by counting input contexts.** The `wayland:` group had
17 contexts while only a handful of applications were running; fcitx5 keeps an IC
until the client disconnects cleanly and Electron does not always do so. Fourteen
of them are `program:ptyxis` from earlier restarts of the terminal.

**Undo.**

```sh
rm ~/.config/obsidian/user-flags.conf
```

**Known dependency.** Requires a **complete** restart of Obsidian, including the
tray process, or the old process keeps the old ozone platform. If a future
Obsidian package drops the `user-flags.conf` mechanism this silently stops
working; the flag would then have to move into a `.desktop` override.

**Relationship to the sleep work: none.**

---

## C11 — EC read instrument and a sleep hook, for Step 12

Two changes, because each has its own undo. Written **before** either was made,
per AGENTS.md §4.3b. Step 12 in `docs/root-cause-plan.md`; rationale in
`docs/progress.md` F42 and F48.

### C11a — `mbp_ec_read` kernel module loaded at runtime

**What.** `modprobe mbp_ec_read`, built from `scripts/mbp-ec-read.c` in this
repository. It exposes `/proc/mbp_ec`, which `scripts/ec-snap.sh` reads. The
module adds **no** behaviour of its own: it calls the kernel's own `ec_read()`,
so the EC lock is respected and there is no port tearing. Step 0b, **PASS**
(`docs/progress.md` §22).

**The .ko had to be rebuilt.** The one in `scripts/` was built 2026-10-16
against `7.2.9-arch1-1`; the running kernel is `7.2.11-arch1-1` after the
2026-10-18 reinstall. **The stale module would not have loaded.** Rebuilt with
the repository's own `scripts/Makefile` against
`/lib/modules/$(uname -r)/build`, using the installed `linux-headers
7.2.11.arch1-1`. `modinfo -F vermagic` now reads `7.2.11-arch1-1`, matching
`uname -r`. Rebuilding is a user-space operation; no machine change.

**Where.** Loaded at runtime only. **Nothing was installed to
`/lib/modules/`**, no entry was added to `modules-load.d`, and no DKMS was set
up. The module is therefore **gone after every reboot** unless it is reloaded by
hand.

**Why.** Step 12 needs to read the EC across a sleep transition, and every
unprivileged route was ruled out first: `/sys/kernel/debug/ec/ec0/io` exists but
is root-only, and `/dev/port` cannot be used because `CONFIG_ACPI_EC=y` already
owns ports 0x62/0x66 and reads would tear.

**Worked.** `not yet tested` — written before the load.

**Undo.** The module does not persist, so after a reboot there is nothing to
undo. To drop it now:

```sh
sudo modprobe -r mbp_ec_read
```

**Known dependency.** Depends on the running kernel version matching the
`.ko`'s `vermagic`. **After any kernel upgrade this module will silently stop
loading** and `ec-snap.sh` will exit 1 with "`/proc/mbp_ec` not present". The
rebuild is one command and is recorded in `scripts/Makefile`.

**Relationship to the sleep work:** this is the instrument for Step 12. It
changes no power-management behaviour.

**RETRACTION (2026-10-19 20:13).** **Reverted.** The module was unloaded:

```sh
sudo rmmod mbp_ec_read
```

Verified: `lsmod | grep mbp_ec` prints nothing; `/proc/mbp_ec` is gone. The
machine behaves as if C11a never happened. **Worked: yes.**

The hook instrument proved unable to answer Step 12's question (the EC is
re-initialised during resume, before the `post` hook runs), so there is no
reason to keep it loaded.

### C11b — `/usr/lib/systemd/system-sleep/30-ec-snap.sh` installed

**What.** One executable hook that snapshots the EC at two points around a sleep
operation: `pre` writes `pre`, `post` writes `post`, each to
`/var/log/mbp-wedge/ec-<tag>.txt`, each announced through `systemd-cat -t mbp-ec`.

**Where.** `/usr/lib/systemd/system-sleep/30-ec-snap.sh`, mode 0755, owner
root. **This is the only directory this systemd reads** (AGENTS.md §5.4,
verified with `strings`); `/etc/systemd/system-sleep/` does not exist and is not
consulted.

**Why.** Step 12 asks whether `_WAK` runs during an idle-suspend cycle, and the
ECSS bit that answers it (`EC 0x10`) is only observable **inside** the sleep
transaction. A user-space daemon polling `/proc/mbp_ec` cannot see it, because
userspace is frozen.

**Worked.** `not yet tested` — written before the install.

**Undo.**

```sh
sudo rm /usr/lib/systemd/system-sleep/30-ec-snap.sh
```

Nothing else refers to it; there is no systemd unit to disable and no enablement
to reverse. After removal the machine behaves exactly as it does now.

**Known dependency.**

1. Depends on C11a. If `mbp_ec_read` is not loaded, the hook fails.
2. **The hook must never be able to fail the sleep transaction.** Every write is
   `|| true` and the script ends with `exit 0`. If that is ever not true, a
   failing sleep hook **aborts the suspend** — and a failure here would look
   exactly like the symptom under investigation. That is why the criterion is
   checked first by running the two commands by hand.
3. Writing to `/var/log/mbp-wedge/` needs the directory to exist and be writable
   by root; `ec-snap.sh` creates it.

**Rule 3.** Not breached. Nothing is disabled, unmasked or removed: `LID0` stays
`*enabled`, keyboard and mouse wake are untouched, `thunderbolt` stays loaded,
and no wake source is restricted. The hook only **reads**.

**Relationship to the sleep work:** this is the measurement point for Step 12. It
is expected to be removed once Step 12 has produced its result, whatever that
result turns out to be.

**RETRACTION (2026-10-19 20:13).** **Reverted.** The hook was removed:

```sh
sudo rm -f /usr/lib/systemd/system-sleep/30-ec-snap.sh
```

Verified: `/usr/lib/systemd/system-sleep/` is empty; `systemd-sleep` will execute
nothing extra on the next suspend. The machine behaves as if C11b never
happened. **Worked: yes.**

Step 12 is void (`docs/root-cause-plan.md`, Step 12 `Result`), so this hook has
no further purpose and is removed per AGENTS.md §0b.3 — it adds nothing.

---

## C12 — install `acpica` for Step 13 (DSDT disassembly)

**What.** Install package `acpica` (20251212-1) from the Arch repositories,
providing `iasl` and `acpidump`. These are the mature tools for disassembling
ACPI tables, confirmed absent from this machine (§0b.1 search: `which iasl`
and `which acpidump` both fail). Needed for Step 13 in
`docs/root-cause-plan.md`, which reads this machine's own DSDT/SSDT AML to find
what GPE 0x4E (`\_SB_.PCI0.LPCB.EC__`, the Apple EC) actually does.

**Where.** Package installed to `/usr/bin/iasl`, `/usr/bin/acpidump` etc. by
pacman. Installed files live under `/usr/`, managed by pacman's database.

**Why.** GPE 0x4E is the EC's event GPE (confirmed from boot log, F42), and the
wake source that fires every idle-suspend cycle (F22–F23). `strings` on the raw
DSDT shows EC query methods `_Q10`, `_Q20`, `_Q40`, `_QCE`, `_QCF`, `_QD0` and
a `_GPE` device, but `strings` cannot show control flow. `iasl -d` produces
readable AML (`.dsl`) to inspect the `_GPE._L4E`/`_E4E` handler and EC `_Qxx`
method bodies — the missing link between "GPE 0x4E fires" and "why the machine
doesn't stay asleep."

**Worked.** `not yet tested` — written before the install.

**Undo.**

```sh
sudo pacman -R acpica
```

Records installed by pacman are removed; nothing else depends on this package.

**Known dependency.** None for package removal. Installing requires network
access to the Arch package mirrors and root (via pkExec per AGENTS.md §1).

**Relationship to the sleep work:** read-only instrumentation for Step 13.
Changes no power-management behaviour, disables nothing, restricts no wake
source. Rule 3 not breached.

---

## C13 — temporarily reload `mbp_ec_read` to inspect EC registers

**What.** `insmod mbp_ec_read.ko` (rebuilt against 7.2.11-arch1-1), read `/proc/mbp_ec`,
then `rmmod`. Only the EC register values are read; no writes to the EC.

**Why.** To verify the hypothesis from the DSDT disassembly: `EC.EWDK` (0x69 bit 5) is set
by `_PTS` on S3 entry but never cleared by `_WAK`, and `EC.EWLO` (0x68 bit 0) is set by
`LID0._PSW(1)` when lid wake is enabled. Reading their current values (and `EC.WKRS` at
0x06) confirms whether these wake-enable bits are asserted.

**Where.** Runtime only; `/proc/mbp_ec` appears while module is loaded, gone after `rmmod`.
No files installed, no persistent changes.

**Worked.** `not yet tested` — written before the load.

**Undo.** `sudo rmmod mbp_ec_read` — verified empty `lsmod` afterwards.

**Relationship to the sleep work:** read-only diagnostic for Step 13 hypothesis testing.
Does not change power-management behaviour.

---

## C14 — temporarily mask GPE 0x4E for diagnosis

**What.** `echo mask > /sys/firmware/acpi/interrupts/gpe4E`, then observe whether the
machine still wakes immediately from idle suspend. Afterwards `echo unmask > .../gpe4E`
to restore. Both commands are run via pkExec.

**Why.** GPE 0x4E is the Apple EC's event GPE (confirmed from boot log, F42) and it
fires 4–8 times per second while idle (F25). Masking it is the upstream-sanctioned
workaround path (bug 117481, F37) and is the only remaining way to test whether this
GPE is the immediate-wake source. Result is diagnostic only — either outcome narrows
the cause.

**Where.** `/sys/firmware/acpi/interrupts/gpe4E` — runtime sysfs attribute, gone on
reboot. Nothing installed to disk.

**Worked.** `yes` — machine stayed asleep ~20 seconds with GPE 0x4E masked (was
waking immediately before), and resumed normal immediate-wake behavior after
unmask. Recorded in `docs/progress.md` F55–F56.

**Undo.** `echo unmask > /sys/firmware/acpi/interrupts/gpe4E` — restores the default
`enabled unmasked` state observed at F33. Verified by re-reading the file and by
confirming the counter resumes incrementing (16 counts / 3 s).

**RETRACTION (same session, 2026-10-19 20:28).** The mask has been removed:
`gpe4E` is back to `EN enabled unmasked`. The machine behaves exactly as it did
before C14. **Worked: yes.**

**Known dependency.**

1. GPE 0x4E is the EC's event channel (§0a.5, F42). Masking it may suppress lid/button
   wake while masked. **The mask is held only for the duration of one suspend cycle
   and is unmasked immediately after**, so any effect is transient.
2. If masking stops the immediate wake, that confirms GPE 0x4E is the source but does
   **not** name *why* the EC asserts it — that remains open and requires the DSDT
   analysis already done (Step 13) plus EC event tracing inside the sleep transaction
   (no userspace instrument exists, Step 12 void).

**Rule 3.** The mask is temporary and fully reversible; no wake source is permanently
disabled or removed. LID0 stays `*enabled` before and after.

---

## C15 — systemd sleep hook: unmount CIFS shares before suspend

**When.** 2026-10-19 23:34.

**What.** New file `/usr/lib/systemd/system-sleep/90-cifs-suspend.sh` (mode 0755,
root:root). The hook runs `pre` → `umount -f -l` all four CIFS shares
(`/mnt/shareA`, `/mnt/shareB`, `/mnt/shareC`, `/mnt/shareD`), and `post` →
`mount` them back. Source tracked in repo at
`files/90-cifs-suspend.sh`, installed via `pkexec cp ... && chmod 755 ...`.

**Why.** The kernel freezer (`try_to_freeze_tasks` in `kernel/power/process.c`)
waits for all freezable workqueues to drain. The CIFS `serverclose` workqueue
carries `cached_dir_offload_close` items that can stay in-flight for 20+ s
(NAS latency / borg activity). When this happens, the freezer hits its hard
20-second timeout (`freeze_timeout_msecs = 20 * MSEC_PER_SEC`), **aborts the
suspend entirely**, and systemd retries as `s2idle` (also fails). The kernel's
own diagnostic dump (`show_freezable_workqueues`) named this exact work item:
`in-flight: 50:cached_dir_offload_close [cifs] for 21s`. Removing the mount
before suspend removes the blocker.

**Where.** `/usr/lib/systemd/system-sleep/90-cifs-suspend.sh` — the **only**
directory this systemd reads (`AGENTS.md §5.4`, verified with `strings` on
`/usr/lib/systemd/systemd-sleep`; `/etc/systemd/system-sleep/` is not
consulted).

**Worked.** `yes` — dry-run `pre`/`post` completed cleanly, journal shows all
four unmounted and remounted. CIFS mount at `/mnt/shareA` confirmed gone after
`pre`, restored after `post`.

**Undo.**

```sh
pkexec rm -f /usr/lib/systemd/system-sleep/90-cifs-suspend.sh
```

No systemd unit to disable, no daemon to reload. After removal the machine
behaves exactly as it did before this change.

**Known dependency.**

1. The four shares must exist in `/etc/fstab` with the names listed in the
   script's `SHARES` variable (`shareA shareB shareC shareD`). If a share is
   added/removed from fstab, the script must be updated in the same pass.
2. `umount -f -l` (force + lazy) is used because CIFS soft mounts with a busy
   server can block indefinitely; `-l` detaches the filesystem immediately and
   cleans up when the last reference drops. This means the `pre` hook **always
   succeeds and never fails the suspend** — by design, per AGENTS.md §0b.3.

**Rule 3.** Not breached. No wake source is disabled, no kernel module is
removed, Thunderbolt stays loaded. The hook only moves the mount state off the
bus during the sleep transaction; it restores it on resume.

**Relationship to the sleep work:** this is a fix for the freezer stall
identified in the current boot (0). It does not address the earlier Thunderbolt
Ethernet adapter fault (§1.1 in `docs/investigation-state.md`) which is still
present in the hardware but appears not to dominate the current boot's
behaviour (cycles 6–13 s instead of instant wake). Both may coexist; the hook
eliminates the 20-second freezer timeout.

---

## C15 UPDATE — xHCI suspend fix added to the same hook

**When.** 2026-10-20 00:58 (hook updated in place).

**What.** The same hook `/usr/lib/systemd/system-sleep/90-cifs-suspend.sh` was
extended with a `fix_xhci()` function called in `pre`:
- Sets `/sys/bus/usb/devices/1-3/power/control = on` (Bluetooth device
  `05ac:8290` on xHCI port 3) before suspend.
- Sleeps 0.1 s for USB transactions to quiesce.
- Restores `auto` in `post`.

**Why.** The 00:46:14 cycle showed:
```
xhci_hcd 0000:00:14.0: PM: pci_pm_suspend(): hcd_pci_suspend returns -16
PM: Some devices failed to suspend, or early wake event detected
```
This is `EBUSY` from xHCI — a child device (Bluetooth `1-3`) was in `auto`
runtime PM and had pending URBs, so the controller refused to suspend. The
kernel then aborted S3 and fell back to `s2idle` (24 s black screen).

Forcing the Bluetooth device to `on` before suspend prevents it from being in
a transitional autosuspend state, letting xHCI suspend cleanly.

**Worked.** `yes` — the 01:00:39 cycle entered S3 successfully (no -16 error,
no s2idle fallback). Total 14 s wall clock, S3 residence ~0.1 s.

**Undo.** Same as C15: `pkexec rm -f /usr/lib/systemd/system-sleep/90-cifs-suspend.sh`

**Known dependency.** The device path `1-3` is stable on this machine (Bluetooth
module `05ac:8290` always enumerates at USB1 port 3). If hardware topology
changes, the hook must be updated.

**Rule 3.** Not breached. No wake source disabled; Bluetooth wake still works
(its `power/wakeup` remains `enabled`). The change is temporary during the
sleep transaction only.

---

## C16 — fix `brcmfmac-resume-recover.service` trigger target

**When.** 2026-10-20 01:55.

**What.** Corrected `/etc/systemd/system/brcmfmac-resume-recover.service`:
- `After=sleep.target` (was `suspend.target`)
- `WantedBy=sleep.target` (was `suspend.target`)
- Removed `After=NetworkManager.service` (unnecessary dependency)

**Why.** `suspend.target` is reached **when entering sleep**, `sleep.target` is reached **when waking up**. The old unit ran the recovery script *during suspend*, not after resume. This caused:
- First resume (01:41:20): script **never ran**
- GNOME auto-suspend triggered second sleep (01:42:22) → script ran *during second suspend*
- Second resume (01:42:32): script finally ran, reloaded WiFi driver (01:42:42-47)

With the fix, script runs on **every resume**.

**Worked.** `yes` — `systemctl daemon-reload` succeeded, service enabled, no errors.

**Undo.**
```sh
pkexec tee /etc/systemd/system/brcmfmac-resume-recover.service >/dev/null <<'EOF'
[Unit]
Description=Reload brcmfmac if the BCM43602 firmware stops answering after a resume
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
After=NetworkManager.service
ConditionPathExists=/sys/bus/pci/drivers/brcmfmac

[Service]
Type=oneshot
ExecStart=/usr/local/bin/brcmfmac-resume-recover
TimeoutStartSec=180

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
pkexec systemctl daemon-reload
```

**Rule 3.** Not breached. No wake source disabled.

---

## C17 — disable GNOME automatic suspend

**When.** 2026-10-20 01:55.

**What.** `gsettings` changes:
- `org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'`
- `org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'`

**Why.** GNOME's 15-min idle auto-suspend (`sleep-inactive-ac-timeout=900`) triggered a **second suspend 62 s after first resume** (01:41:20 → 01:42:22), while the WiFi recovery script had not yet run (due to C16 bug). This caused the "wake → 1 min black screen → WiFi reload" sequence.

With C16 fixed, the recovery script now runs on first resume. Disabling auto-suspend is a belt-and-suspenders measure to prevent any future idle-triggered suspend during recovery.

**Worked.** `yes` — settings applied immediately, no logout needed.

**Undo.**
```sh
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'suspend'
```

**Rule 3.** Not breached. Does not disable wake sources, only prevents idle-triggered suspend.

---

## C16 RETRACTED (2026-10-20 02:10) — `suspend.target` was already correct

**Status.** Withdrawn. The change C16 describes was reversed at 02:08, see C18. The entry is kept because the reasoning error is worth reading.

**What C16 got wrong.** It claimed `suspend.target` is reached "when entering sleep" and `sleep.target` "when waking up". The real machine says the opposite. From boot -1:

| cycle | `PM: suspend exit` | recovery unit started |
|---|---|---|
| 00:46:14 | 00:46:41 | 00:46:57 |
| 01:00:39 | 01:00:53 | 01:01:09 |
| 01:15:22 | 01:15:29 | 01:15:30 |
| 01:29:11 | 01:29:22 | 01:29:22 |
| 01:42:22 | 01:42:32 | 01:42:32 |
| 01:57:28 | 01:57:39 | **never** |

Under the C16 file the unit started at **01:55:58**, one second after "The system will suspend now!" and 90 s *before* `PM: suspend entry` -- i.e. on the way into sleep. The `systemd[1]` lines make the ordering explicit: `Stopped target Sleep.` and `Reached target Suspend.` both appear at 01:57:39, at resume.

**What it cost.** The 01:57:39 resume had no recovery. brcmfmac stayed wedged (`brcmf_msgbuf_query_dcmd: Timeout on response` every ~2 s from 01:57:41), NetworkManager never got a supplicant (`Couldn't initialize supplicant interface: timed out`), and the operator saw Wi-Fi fail to connect and plugged the Thunderbolt adapter in as a stopgap. **This was a self-inflicted regression, not a new fault.**

**Housekeeping.** The first edit of C16 also left a duplicate `## C15 UPDATE` heading at the end of the file. That stray heading -- which carried no content -- is what this section replaced.

---

## C18 — restore `brcmfmac-resume-recover.service` to `suspend.target`

**When.** 2026-10-20 02:08.

**What.** `/etc/systemd/system/brcmfmac-resume-recover.service` restored to its pre-C16 ordering:
- `After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target`
- `After=NetworkManager.service`
- `[Install] WantedBy=` the same four targets.
- A comment added recording the measurement above, so the next reader does not repeat the mistake.

**Why.** Undo of C16. The unit must run *after* resume; `sleep.target` makes it run before suspend.

**Worked.** `yes` -- measured on the 2026-10-20 10:43:40 suspend. `brcmfmac-resume-recover.service: Starting` at 10:47:57, one second after `PM: suspend exit` at 10:47:57, finished at 10:48:00. Its log line for that cycle is `wifi back on its own after 3s on wlan0, no reload needed`, so it also made the correct decision. Detail: `docs/progress.md`, 2026-10-20 10:43:40 entry.

**Undo (restores C16's broken file).** Not recommended; included for completeness.
```sh
pkexec tee /etc/systemd/system/brcmfmac-resume-recover.service >/dev/null <<'EOF'
[Unit]
Description=Reload brcmfmac if the BCM43602 firmware stops answering after a resume
After=sleep.target
ConditionPathExists=/sys/bus/pci/drivers/brcmfmac

[Service]
Type=oneshot
ExecStart=/usr/local/bin/brcmfmac-resume-recover
TimeoutStartSec=180

[Install]
WantedBy=sleep.target
EOF
pkexec systemctl daemon-reload
```

**Rule 3.** Not breached. No wake source disabled.

---

## C19 — CIFS sleep hook: stop triggering automounts, bound the unmount, fix the post unit names

**When.** 2026-10-20 02:08 (pre-phase changes); 2026-10-20 10:40 (post-phase unit-name fix).

**What.** `/usr/lib/systemd/system-sleep/90-cifs-suspend.sh`, source `files/90-cifs-suspend.sh`:
- `pre`: `mountpoint -q "$target"` replaced with a `/proc/self/mountinfo` scan (`cifs_mountpoints()`), so the hook can no longer *trigger* an automount.
- `pre`: `umount -f -l "$target"` wrapped in `timeout 10`.
- `post`: unit names corrected from `/mnt-<share>.automount` to `mnt-<share>.automount`, calls made `--no-block`.
- `post`: `/mnt/shareA` re-mounted via a detached 25 s transient timer (`systemd-run --on-active=25`), because it has no automount unit (see C20).

**Why (the 90 s).** Every suspend from 23:34 -- the moment this hook was first installed -- has a ~90 s gap between the hook starting and `PM: suspend entry`. Before the hook existed the same gap was 1-2 s:

| suspend requested | pre-hook logged | `PM: suspend entry` | gap |
|---|---|---|---|
| 22:47:09 | -- (no hook) | 22:47:10 | 1 s |
| 23:03:37 | -- (no hook) | 23:03:39 | 2 s |
| 23:41:19 | 23:41:20 | 23:42:50 | 91 s |
| 00:19:05 | 00:19:06 | 00:20:36 | 91 s |
| 01:27:40 | 01:27:41 | 01:29:11 | 91 s |
| 01:55:57 | 01:55:58 | 01:57:28 | 90 s |

`systemd-sleep`'s own `_SOURCE_REALTIME_TIMESTAMP` puts 90.002 s between "User sessions remain unfrozen" and "Performing sleep operation 'suspend'", so the wait is inside the sleep transaction, not a log artefact. The operator sees it as a one-minute black screen after pressing the power key, because systemd blanks the display before `suspend(2)`.

Two CIFS mechanisms, one per observed case:
1. When a share was **not** mounted (01:40:52, 01:55:58), `mountpoint -q /mnt/shareB` `stat()`ed an `x-systemd.automount` path and *triggered the automount*. NetworkManager had already torn the link down at 01:55:57, so the mount attempt waited for the SMB timeout.
2. When a share **was** mounted (01:27:41, `/mnt/shareA`), `umount -f` waited for the SMB tree-disconnect to time out.

**Why (the post-phase unit names).** `systemctl start /mnt-shareB.automount` is parsed as a *path*, escaped to `mnt\x2dshareB.automount.mount`, and reported `not-found`:
```
$ systemctl show -p Id '/mnt-shareB.automount'
Id=mnt\x2dshareB.automount.mount
$ systemctl show -p Id 'mnt-shareB.automount'
Id=mnt-shareB.automount
```
So the post phase's automount re-arm had always been a silent no-op. Harmless for `shareB`/`shareC`/`shareD` (their automount units stay active and fire on the next access), but not for `shareA` -- see C20.

**Worked.** `partly` -- measured on the 2026-10-20 10:43:40 suspend.

- **The 90 s is gone: yes.** `Pre-suspend: fixing xHCI + unmounting CIFS` logged at 10:44:04 and `PM: suspend entry (deep)` is stamped the same second. Same run: `/mnt/shareA is not an active CIFS mount` branch untested, `/mnt/shareA` unmount path exercised, `timeout 10` did not fire.
- **The 20 s freezer risk did not materialise:** `Freezing remaining freezable tasks completed (elapsed 1.585 seconds)`.
- **The 25 s `shareA` re-mount works:** `cifs-remount-shareA.service` mounted `/mnt/shareA` at 10:48:25 and the repository was readable afterwards.
- **It did not prevent the stall that mattered.** That suspend had a **different** blocker: `Filesystems sync: 194.646 seconds`, waiting on `flush-cifs-1` writeback of a running `borg create` into `/mnt/shareA/borg-repo`. `umount -f -l` detaches the mount but leaves the superblock alive with dirty pages, so `sync_filesystem()` still waits. **The `-l` comment in C15 ("always succeeds ... by design") is true about the unmount and misleading about the suspend**: it succeeds by not flushing. See `docs/progress.md`, F62.

**Known risk (recorded before the test, not after).** If `timeout 10` kills `umount` before the CIFS teardown completes, the mount may still be present when the kernel freezes userspace, and the 20 s freezer timeout that C15 exists to prevent can return. The deciding observation is the next suspend's `Freezing remaining freezable tasks completed (elapsed N seconds)` line: anything approaching 20 s means the bound must be raised or removed.

**Undo (restores the C15 + C15-UPDATE hook exactly).**
```sh
pkexec tee /usr/lib/systemd/system-sleep/90-cifs-suspend.sh >/dev/null <<'EOF'
#!/bin/sh
# systemd sleep hook: fix xHCI suspend + CIFS unmount
# Installed to /usr/lib/systemd/system-sleep/90-cifs-suspend.sh
# Undo: pkexec rm -f /usr/lib/systemd/system-sleep/90-cifs-suspend.sh

set -eu

CIFS_SHARES="shareA shareB shareC shareD"
MOUNT_ROOT="/mnt"
LOG_TAG="cifs-suspend"

log() {
    logger -t "$LOG_TAG" "$1"
}

fix_xhci() {
    # Ensure xHCI child devices are suspended before S3
    # Bluetooth device (1-3) often causes xHCI suspend EBUSY
    for dev in /sys/bus/usb/devices/1-3; do
        [ -e "$dev/power/control" ] && echo on > "$dev/power/control" 2>/dev/null || true
    done
    # Small delay for USB transactions to quiesce
    sleep 0.1
}

case "${1:-}" in
    pre)
        log "Pre-suspend: fixing xHCI + unmounting CIFS"
        fix_xhci
        for share in $CIFS_SHARES; do
            mountpoint -q "$MOUNT_ROOT/$share" && {
                log "Unmounting $MOUNT_ROOT/$share"
                umount -f -l "$MOUNT_ROOT/$share" 2>/dev/null || log "Warning: failed to unmount $MOUNT_ROOT/$share"
            } || log "$MOUNT_ROOT/$share not mounted, skipping"
        done
        ;;
    post)
        log "Post-resume: triggering CIFS auto-mount (non-blocking)"
        for share in $CIFS_SHARES; do
            systemctl start "$MOUNT_ROOT-$share.automount" 2>/dev/null || true
        done
        systemctl start network-online.target 2>/dev/null || true
        # Restore Bluetooth device autosuspend
        for dev in /sys/bus/usb/devices/1-3; do
            [ -e "$dev/power/control" ] && echo auto > "$dev/power/control" 2>/dev/null || true
        done
        log "CIFS auto-mount triggered, xHCI restored"
        ;;
    *)
        echo "Usage: $0 {pre|post}" >&2
        exit 1
        ;;
esac
EOF
pkexec chmod 755 /usr/lib/systemd/system-sleep/90-cifs-suspend.sh
```
The repo copy `files/90-cifs-suspend.sh` gets the same content; it is still untracked in git, so `git checkout` cannot restore it.

**Rule 3.** Not breached. No wake source disabled; the hook still only moves mount state and USB runtime-PM state during the sleep transaction.

---

## C20 — `/mnt/shareA` does not come back after resume (OPEN, not changed)

**Observed.** `pre` unmounted `/mnt/shareA` at 01:27:41. It was still unmounted at 02:03 (absent from `mount`), and only reappeared after the reboot at 10:32. `mnt-shareA.mount` is a plain fstab mount; there is no `mnt-shareA.automount` unit, and the post phase's attempt to start one resolves to `not-found`.

**Cause.** fstab gives `shareA` no `x-systemd.automount`, unlike the other three shares, so nothing re-creates it after the hook removes it.

**Changed anyway (partial).** C19 adds a detached 25 s re-mount of `mnt-shareA.mount` in the post phase. That covers the normal resume path; it is not a substitute for an automount and it has not been tested.

**Not changed, needs a decision.** Making `shareA` an automount (`x-systemd.automount,x-systemd.idle-timeout=60`, matching the other three shares) would fix it permanently *and* stop `shareA` from being mounted at suspend time, which removes the last known 90 s path. It changes behaviour the operator may rely on, so it waits.

**Worked.** `not yet tested`.

**Rule 3.** Not breached.

---

## RETRACTION — the "Current system state" section above should never have existed

Written 2026-10-20 10:40, removed 2026-10-20 11:16. Rule 4.3a item 7 forbids this file from carrying one: *"It is not a snapshot of the machine and carries no 'current state' table: a state table goes stale the moment anything changes outside it, and a stale table is worse than none, because the reader trusts it."* It was stale within the hour -- it listed `mnt-shareA.mount` as active, which stopped being true at 10:59, and `files/90-cifs-suspend.sh` as uncommitted, which is a repository fact rather than a configuration one. Read the machine, and read `docs/progress.md` for behaviour.

---

## C21 — backup scripts moved from `~/bin` to `~/projects/borg_backup`

**When.** 2026-10-20 11:10-11:15.

**What.** Seven paths moved with `mv` from `~/bin/` to `~/projects/borg_backup/`:

| file | role |
|---|---|
| `backup.sh` | root-side backup of `/etc /boot /root /var/lib/NetworkManager` into the same borg repository |
| `borg-backup.service` / `.timer` | system units that run `backup.sh` hourly at :15 |
| `borg-maintenance.sh` | weekly `borg check` |
| `borg-restore.sh` | restore helper (list / find / get / mount / umount) |
| `setup-shareA-mount.sh` | one-shot root setup: writes the `shareA` fstab line, creates the repo directory |
| `vorta-excludes.txt` | exclusion list, pasted into Vorta's UI by hand (referenced by no script) |
| `.backup-20261019/` | superseded `borg-privileged.*` units, kept as history |

Two `ExecStart=` lines were changed in the same pass. Without them the move breaks both timers:

- `/etc/systemd/system/borg-backup.service`: `ExecStart=~/bin/backup.sh` -> `~/projects/borg_backup/backup.sh`
- `~/.config/systemd/user/borg-maintenance.service`: `ExecStart=%h/bin/borg-maintenance.sh` -> `%h/projects/borg_backup/borg-maintenance.sh`

The `~/bin/...` usage strings inside `borg-maintenance.sh`, `borg-restore.sh` and `setup-shareA-mount.sh` were rewritten to the new path, so the printed help is not a lie.

**Why.** Operator request at 11:07: backup material did not belong in `~/bin` next to unrelated `grub-*.sh`. Everything else this machine keeps lives under `~/projects/`.

**Not moved, deliberately.** `grub-font-40.sh` and `grub-menu-en.sh` are unrelated to backups. `~/bin` is **not** on `PATH` (`~/.zshrc:9` is commented out), so no shell alias or invocation by name existed to update -- checked before moving.

**Order of operations.** `borg-backup.timer` was stopped first, so the move could not race a scheduled run; it was restarted by the same `pkexec` that installed the edited unit.

**Worked.** `yes` -- verified, not assumed:
- `systemctl cat borg-backup.service` -> `ExecStart=~/projects/borg_backup/backup.sh`.
- `systemctl --user cat borg-maintenance.service` -> `ExecStart=%h/projects/borg_backup/borg-maintenance.sh`.
- `bash -n` clean on all four scripts.
- `borg-backup.timer` `active`, next elapse recomputed to 11:15:07; `borg-maintenance.timer` still `active`.
- The first scheduled run after the move is recorded in `docs/progress.md`.

**Undo.**
```sh
mv -v ~/projects/borg_backup/backup.sh ~/projects/borg_backup/borg-backup.service \
      ~/projects/borg_backup/borg-backup.timer ~/projects/borg_backup/borg-maintenance.sh \
      ~/projects/borg_backup/borg-restore.sh ~/projects/borg_backup/setup-shareA-mount.sh \
      ~/projects/borg_backup/vorta-excludes.txt ~/projects/borg_backup/.backup-20261019 ~/bin/
pkexec install -m 644 -o root -g root \
    /etc/systemd/system/borg-backup.service.bak.20261020-1115 \
    /etc/systemd/system/borg-backup.service
pkexec systemctl daemon-reload
sed -i 's|%h/projects/borg_backup/borg-maintenance.sh|%h/bin/borg-maintenance.sh|' \
    ~/.config/systemd/user/borg-maintenance.service
systemctl --user daemon-reload
sed -i 's|~/projects/borg_backup/|~/bin/|g' \
    ~/bin/borg-maintenance.sh ~/bin/borg-restore.sh ~/bin/setup-shareA-mount.sh
```

**Backup taken before the edit:** `/etc/systemd/system/borg-backup.service.bak.20261020-1115`. The installed unit and `~/bin/borg-backup.service` were byte-identical before the move (`diff` printed nothing but the `ExecStart` line after the edit), so restoring the `.bak` restores the prior state exactly.

**Rule 3.** Not breached.

**Rule 0 note.** `backup.sh`, `borg-maintenance.sh`, `borg-restore.sh` and `setup-shareA-mount.sh` are commented in Chinese. They live outside this repository and rule 0 does not reach them. They were moved byte-for-byte and not translated: translating working backup code was not asked for and would risk breaking it.

---

## C22 — the sleep hook now stops borg writers before the CIFS teardown

**When.** 2026-10-20 11:33.

**What.** `files/90-cifs-suspend.sh` gained two shell functions and one call site:

- `borg_pids()` -- prints the PID of every running borg process, matched by reading `/proc/*/cmdline` and requiring `argv[0]`'s basename to be `python*` and `argv[1]`'s basename to be `borg`.
- `stop_backup_writers()` -- SIGTERM to those PIDs, wait up to `BORG_KILL_WAIT` (3 s, checked every 100 ms), then SIGKILL the survivors.
- Called from the `pre` branch **before** the unmount loop. `BORG_KILL_WAIT=3` is a new constant at the top.

Installed to `/usr/lib/systemd/system-sleep/90-cifs-suspend.sh` (`install -m 755 -o root -g root`), which is the only directory this systemd-sleep reads (AGENTS.md §5.4).

**Why.** Operator decision at 11:20: when a backup and a suspend collide, **the suspend wins**. The 194.646 s `Filesystems sync` of 10:44 was a live `borg create` writing into `/mnt/shareA/borg-repo` while `wlan0` was already down; `sync_filesystem()` cannot converge while a writer keeps dirtying pages onto a dead link. Vorta will not stop the job itself -- `vorta/scheduler.py:132` is `if not suspend:` (F65) -- so it has to be stopped from outside. Plan step: `docs/root-cause-plan.md` Step 14.

**Why not `pgrep -f borg`.** That pattern also matches `~/projects/borg_backup/` in any command line, including the harness command that invokes this very investigation. Killing on that pattern would be a self-inflicted outage. Verified with a decoy: a `sh -c '... # ~/projects/borg_backup/backup.sh'` process is **not** matched, while `/usr/bin/python3 .../borg create ::archive` **is**.

**Why SIGTERM first.** `borg/archiver.py:5886` installs `raising_signal_handler(SigTerm)`, so SIGTERM aborts the transaction and releases the repository lock cleanly. SIGKILL is the 3 s fallback and is not destructive: a stale lock whose hostname matches and whose PID is dead is cleared by borg on the next run -- measured the same morning at 11:15, "Killed stale lock host@189924302000355.6604-0".

**Backup taken before the edit:** `/var/backups/90-cifs-suspend.sh.20261020-1140`.
**Deliberately NOT** left as `90-cifs-suspend.sh.bak.20261020-1140` inside `/usr/lib/systemd/system-sleep/`. That was the first thing tried and it was wrong: systemd-sleep executes **every executable file** in that directory and a `.bak` suffix does not disable a hook. AGENTS.md §5 records exactly this trap having already cost a night (`50-brcmfmac.sh.bak.20261014-130630` ran on every suspend until 2026-10-17). Verified afterwards that `find /usr/lib/systemd/system-sleep -type f -perm -u+x` lists exactly one file.

**Worked.** `not yet tested` -- and it must not be described as working. What **is** verified is only mechanical:
- `sh -n` clean.
- Unit-tested in isolation (`/tmp/opencode/borgtest/`, the extracted functions) against three cases: cooperative process ("borg exited within 1s of SIGTERM"), process ignoring SIGTERM ("borg still alive after 1s, sending SIGKILL", killed), and no process ("no borg writer running, nothing to stop").
- Decoy path (`borg_backup/` in a cmdline) not matched; real borg form matched.

What is **not** verified is the only thing that matters: that a real suspend taken during a real borg job now shows `Filesystems sync` under 5 s instead of 194 s. That is `docs/root-cause-plan.md` Step 14, and its `Result:` line still reads `Not run.`

**Undo.**
```sh
pkexec install -m 755 -o root -g root \
    /var/backups/90-cifs-suspend.sh.20261020-1140 \
    /usr/lib/systemd/system-sleep/90-cifs-suspend.sh
```
That restores the pre-C22 hook in full (it is a byte copy of what was installed at 10:38). No `daemon-reload` is needed: systemd-sleep re-reads the directory on every suspend.

**Rule 3.** Not breached. The hook kills a userspace backup process; it does not disable Thunderbolt, mask a unit, or remove any wake source.

**Addendum, same entry (11:41) — a `set -e` hazard in the first version.** The first `borg_pids()` read the argv vector twice with
`a0=$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null | sed -n 1p)`.
The hook runs under `set -eu`, and if a short-lived process exits between the
`[ -r "$d/cmdline" ]` test and that read, the shell reports the failed
redirection itself — `2>/dev/null` is attached to `tr`, not to the shell's
redirection — so the hook would either print noise into the journal or exit
before the unmount loop, which is **worse than the pre-C22 hook**. Replaced
with a single read wrapped in a group redirect:

```sh
argv=$( { tr '\0' '\n' < "$d/cmdline"; } 2>/dev/null ) || continue
```

Verified that `set -e` does not fire on `[ ... ] && continue` (tested
explicitly, not assumed: a loop containing `[ "$i" = "9" ] && continue` runs to
completion) and that the group redirect suppresses the shell's own error. Copied
into place again afterwards; `find /usr/lib/systemd/system-sleep -type f -perm -u+x`
still lists exactly one file.

---

## RETRACTION under C22 — it did not work, and its own implementation made the black screen three minutes long

Written 2026-10-20 12:10. The `Worked: not yet tested` line above is superseded
by this.

C22 was exercised exactly once, at 11:55:04 on 2026-10-20, and the result was
**FAILED** — worse than the state it replaced.

| measurement | value | criterion |
|---|---|---|
| `Filesystems sync` | **95.554 s** | expected under 5 s |
| suspend requested -> `PM: suspend exit` | **3 min 13 s** | -- |
| real S3 residence (`CLOCK_BOOTTIME - CLOCK_MONOTONIC`) | **2.443 s** | -- |
| `stop_backup_writers` actual duration | **36.5 s** | `BORG_KILL_WAIT=3` |

**Two defects of my own, and both are mine:**

1. `borg_pids()` walked `/proc` and spawned `sed` twice per process. Measured in
   isolation afterwards: **1339 ms per call** with 231 processes running. The
   100 ms polling loop called it 30 times, so a constant named
   `BORG_KILL_WAIT=3` delivered **36.5 s** — the hook logged
   `stopping borg writer(s)` at 11:55:07 and `still alive after 3s` at 11:55:43.
2. `timeout 10 umount` cannot bound anything. The umount blocked on the dead
   CIFS link in **state D**, where SIGTERM and SIGKILL are both undeliverable, so
   `timeout` fired at 10 s and then waited forever. The hook logged `Unmounting`
   at 11:55:43 and the umount process was still in D at 11:57:47.

**And the substance did not work either.** Killing the writer did not remove the
stall, because the pages already in the page cache still had to be written to a
link that was already gone. Step 14 was written with that branch spelled out in
advance — *"Failure: still above 60 s. That means the dirty-page backlog, not the
live writer, dominates"* — and that is the branch that fired.

**CORRECTION 2026-10-20 12:40 — the paragraph above is wrong, twice over. See
F73.** The process C22 killed was `borg prune` (`backup.sh:87`), not `borg create`;
`create` had already returned, so there was no dirty backlog at all. And the
95.554 s `Filesystems sync` ended 265 ms after the kernel's CIFS reconnect deadline
expired — `3 * echo_interval` = 180 s — so it was a timeout being waited out, not
pages being flushed. C22 is still retired, but on a corrected reason: there is
nothing for it to abort, and it cannot shorten a deadline.

**Consequence that must be recorded with it.** The SIGKILL left
`lock.exclusive/host@189924302000355.51572-0` on `/mnt/shareA/borg-repo` with
PID 51572 dead. Borg did not treat it as stale: the 12:16 privileged run burned its
full `--lock-wait 900` and failed, and the 12:31 run skipped with
`repo occupied by Vorta`. **Two hourly backups were lost to this change.** Any
future variant of C22 must run `borg break-lock` after a kill, or must not kill a
process holding the repository lock.

Superseded by C23. The failing implementation is kept at
`/var/backups/90-cifs-suspend.sh.buggy-C22.20261020-1205`.

---

## C23 — the hook's `pre` phase is bounded: fast borg lookup, unmount never awaited

**When.** 2026-10-20 12:09.

**What.** Three changes to `files/90-cifs-suspend.sh`, installed to
`/usr/lib/systemd/system-sleep/90-cifs-suspend.sh` (`install -m 755 -o root -g root`).

1. `borg_pids()` is now one call:
   `pgrep -f '^/[^ ]*/python[0-9.]* /[^ ]*/borg( |$)'` — **21 ms**, down from
   1339 ms.
2. The `while ... sleep 0.1` polling loop is replaced by two fixed checks (1 s,
   then 2 s). Number of process spawns matters more than the resolution of the
   wait.
3. `umount -f -l "$target" >/dev/null 2>&1 &` — backgrounded, never awaited.
   `UNMOUNT_TIMEOUT` deleted, because it was never doing anything.

**Why.** The `pre` phase is where the operator's black screen comes from: systemd
blanks the display before `suspend(2)`, so any blocking call in the hook is time
spent staring at a black screen. C22 made that phase **3 minutes** long while
believing it was bounded at 3 seconds.

The anchor in the pgrep pattern is not decoration: without it the pattern would
match `~/projects/borg_backup/` in any command line, including the
harness's own.

**Why the unmount is no longer awaited — the measurement that settles it.** The
`Filesystems sync` time tracks the amount of **dirty data**, not whether the
mount is still present:

| cycle | unmount | writer | `Filesystems sync` |
|---|---|---|---|
| 10:44 | timed out, mount left up | `borg create` of `/` | 194.646 s |
| 10:59 | timed out, mount left up | none | **0.014 s** |
| 11:55 | blocked 52 s, mount left up | root borg, killed at +36 s | **95.554 s** |

Waiting for the unmount has never once changed the outcome, and it repeatedly
cost the operator minutes.

**Worked.** `not yet tested`. Mechanically verified only:
- `sh -n` clean; installed copy byte-identical to the repo copy.
- Function-level timings, measured with `date +%s%N`: cooperative borg **1044 ms**,
  borg ignoring SIGTERM **3063 ms**, nothing running **20 ms**. Against 36.5 s before.
- Three cases still behave: cooperative process killed by SIGTERM, SIGTERM-immune
  process killed by SIGKILL, no process -> explicit "nothing to stop" log line.
- Decoy command line containing `borg_backup/` still not matched; a real
  `/usr/bin/python .../borg create` still matched.

What is **not** verified is whether the remaining stall is now acceptable. It
will not be removed by this change — C23 only stops the hook from *adding* to it.
The 95.554 s `Filesystems sync` is a separate problem and is recorded as such in
`docs/root-cause-plan.md` Step 14.

**Undo.**
```sh
pkexec install -m 755 -o root -g root \
    /var/backups/90-cifs-suspend.sh.buggy-C22.20261020-1205 \
    /usr/lib/systemd/system-sleep/90-cifs-suspend.sh
```
(That restores the C22 version, which is 3 minutes slow but is what was installed
immediately before this entry. To go all the way back to the pre-C22 hook, use
`/var/backups/90-cifs-suspend.sh.20261020-1140` instead.)

**Rule 3.** Not breached.

## C24 — `mbp-sleep` installed as the machine's only sleep program

**When.** 2026-10-20 14:38, reinstalled at 14:46 and 14:50 with two fixes found
during the first run (see C28 and the `cifs_unmount` fix below).

**What.** `/usr/local/sbin/mbp-sleep`, mode 0755, root:root, installed from the
repository file of the same name. It is the program behind C25-C27.

**Why.** Five separately written hooks and units had drifted apart, and three of
them carried a defect that could not be seen from outside: the CIFS hook killed
the backup (C22, C23), the Wi-Fi service only reacted after resume, and the
wake-source unit's `ExecStart` pointed into this repository. Consolidating them
was the operator's instruction for this session.

**Worked.** `not yet tested` as a sleep path. What was verified:

- `python3 -m py_compile` clean; installed copy byte-identical to the repo copy.
- `mbp-sleep report --boot 0` reproduced the three known cycles exactly
  (194.646 s, 0.014 s, 95.554 s of `Filesystems sync`), which is what makes the
  tool trustworthy rather than merely plausible.
- `mbp-sleep status` reads the machine correctly, including the distinction
  between a real CIFS mount (`/mnt/shareA`) and the three `x-systemd.automount`
  points (`/mnt/shareB`, `/mnt/shareC`, `/mnt/shareD`), which are idle trampolines
  and must not be unmounted.

**Fixes found during the first run.** Three, all of them found by watching the
installed daemon rather than the code:

1. `cifs_unmount` used `os.path.ismount()`, which is true for an autofs
   trampoline as well as for a real mount, so the hook would have torn down the
   automount units for three shares and changed how they come back. It now reads
   the filesystem type from `/proc/mounts` and only touches `cifs`.
2. The process scan behind "is a backup running" cost **7.3 ms** for the whole
   process table, once a second. It is now an `os.open`/`os.read` loop with a
   literal byte prefilter (1.5 ms) at a 2 s interval, and the lid and the bus
   force a fresh scan whenever the answer decides something.
3. `dbus-monitor` run as root gets a **monitor connection**, which receives every
   message on the system bus — the filter argument only sets a match rule, and a
   monitor does not need one, so the output is unfiltered. Parsing that stream
   line by line was the bulk of the daemon's CPU. The watcher now reads in 64 KB
   chunks and, more importantly, **only runs while a block lock is held**, which
   is the only time a suspend can be refused and therefore the only time it is
   needed.

Measured on the installed service, idle: **1.4% -> 0.33%** of one core, and no
`dbus-monitor` process between backups.

**Undo.**
```sh
pkexec rm -f /usr/local/sbin/mbp-sleep
```
or, to undo everything in this group at once, `sudo ./uninstall.sh --restore
/var/backups/mbp-sleep/20261020-143804`.

**Rule 3.** Not breached.

---

## C25 — `/etc/mbp-sleep.conf` installed

**When.** 2026-10-20 14:38.

**What.** `/etc/mbp-sleep.conf`, mode 0644, copied from `macbook.conf`. The
installer **does not overwrite an existing file**: a re-run keeps whatever the
operator has since edited. Every switch in it is `on` except `freeze_sessions`,
which is `off` and means "install the freeze drop-in" (C32).

**Why.** The operator's requirement for this session: every behaviour controlled
by a setting, and every setting on by default.

**Worked.** `not yet tested`. `mbp-sleep status` reads the installed file and
reports all seven switches.

**Undo.**
```sh
pkexec rm -f /etc/mbp-sleep.conf
```

**Rule 3.** Not breached.

---

## C26 — `mbp-sleep.service` installed, enabled and started

**When.** 2026-10-20 14:38.

**What.** `/etc/systemd/system/mbp-sleep.service`, `Type=simple`,
`ExecStart=/usr/local/sbin/mbp-sleep daemon`, `Restart=always`,
`RestartSec=2`, `WantedBy=multi-user.target`. Enabled and started.

**Why.** The daemon is what applies the ACPI wake sources at every boot, owns
the lid switch, and holds the logind block lock that makes a suspend wait for a
running backup.

**Worked.** Verified mechanically: `systemctl is-active` -> `active`,
`is-enabled` -> `enabled`, and the daemon logged
`started; lid is open; defer_on_backup=on`.

**Known dependency — read this before moving the repository.** The unit
deliberately points at `/usr/local/sbin/mbp-sleep`, not into the checkout, so
moving or deleting the repository cannot silently disable the machine's sleep
handling. The *reverse* is now true: **the installed copy is what runs, and a
change in the repository does nothing until `install.sh` is run again.** This is
the same class of failure as the C2 dependency it replaces.

**Undo.**
```sh
pkexec systemctl disable --now mbp-sleep.service
pkexec rm -f /etc/systemd/system/mbp-sleep.service
pkexec systemctl daemon-reload
```

**Rule 3.** Not breached.

---

## C27 — sleep hook `50-mbp-sleep` installed

**When.** 2026-10-20 14:38.

**What.** `/usr/lib/systemd/system-sleep/50-mbp-sleep`, mode 0755. A three-line
shim that calls `/usr/local/sbin/mbp-sleep "$1"`, so `pre` and `post` are the
same program as the daemon.

**Why.** This systemd reads only `/usr/lib/systemd/system-sleep/` (rule 5.4).
The hook is where the device work happens: CIFS unmount, then the Thunderbolt
endpoint off the bus, then the Wi-Fi (disconnect before unload, or
wpa_supplicant is left in state D and the suspend never completes).

**Worked.** `not yet tested` — no sleep cycle has run since it was installed.

**Undo.**
```sh
pkexec rm -f /usr/lib/systemd/system-sleep/50-mbp-sleep
```

**Rule 3.** Not breached: the Wi-Fi and the Thunderbolt endpoint are restored on
resume, and no wake source is touched.

---

## C28 — logind told to ignore the lid switch (`HandleLidSwitch=ignore`)

**When.** 2026-10-20 14:38 written; **14:40 reloaded**, which the installer had
forgotten to do.

**What.** `/etc/systemd/logind.conf.d/50-mbp-sleep.conf`:

```
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

and `systemctl kill -s HUP systemd-logind`.

**Why.** The daemon has to know about a lid close even when a backup is running,
because a suspend request refused by the block lock is silently dropped. logind
handles the lid internally without a bus message, so the only way to see it is to
own it.

**The defect in the first run.** `install.sh` wrote the drop-in and ran
`daemon-reload`, which does not apply logind configuration. logind kept
`HandleLidSwitch=suspend` and read back `s "suspend"` a minute after the install.
It was reloaded by hand at 14:40 and now reads `s "ignore"`. `install.sh` was
fixed in the same pass and now sends the SIGHUP itself.

**Worked.** `not yet tested` for the behaviour. Verified: `busctl get-property
org.freedesktop.login1 /org/freedesktop/login1
org.freedesktop.login1.Manager HandleLidSwitch` returns `s "ignore"`.

**Known dependency.** If the daemon is stopped while this drop-in is present, a
closed lid does nothing at all. `uninstall.sh` removes the drop-in and reloads
logind; if a run ever ends with the service dead and the drop-in present, the lid
is dead until one of those two things happens.

**Undo.**
```sh
pkexec rm -f /etc/systemd/logind.conf.d/50-mbp-sleep.conf
pkexec systemctl kill -s HUP systemd-logind
```

**Rule 3.** Not breached — a lid close still suspends the machine, through the
daemon instead of through logind.

---

## C29 — `/usr/lib/systemd/system-sleep/90-cifs-suspend.sh` removed

**When.** 2026-10-20 14:38.

**What.** Removed from the hook directory. The file itself is preserved at
`/var/backups/mbp-sleep/20261020-143804/90-cifs-suspend.sh`.

**Why.** `mbp-sleep pre` does the CIFS unmount now, without killing the backup.
C22 and C23 both belonged to this file, and C22's kill cost two backups on
2026-10-20.

**Worked.** `not yet tested` — the replacement behaviour has not run yet.

**Undo.**
```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-143804/90-cifs-suspend.sh \
    /usr/lib/systemd/system-sleep/90-cifs-suspend.sh
```

**Rule 3.** Not breached.

---

## C30 — `brcmfmac-resume-recover.service` removed

**When.** 2026-10-20 14:38 (disabled, then removed; was enabled for
`suspend.target`, `hibernate.target`, `hybrid-sleep.target` and
`suspend-then-hibernate.target`).

**What.** `/etc/systemd/system/brcmfmac-resume-recover.service` and its script
`/usr/local/bin/brcmfmac-resume-recover`, plus the `*.wants/` symlinks.

**Why.** It only reacted after a resume. `mbp-sleep post` now unloads the Wi-Fi
driver *before* the sleep — which is what stops the D3 refusal that aborts the
suspend in the first place — and its detached `wifi-verify` step does the same
"reload once if the interface does not come back" recovery after resume.

**Worked.** `not yet tested`.

**Undo.**
```sh
pkexec install -m 644 -o root -g root \
    /var/backups/mbp-sleep/20261020-143804/brcmfmac-resume-recover.service \
    /etc/systemd/system/brcmfmac-resume-recover.service
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-143804/brcmfmac-resume-recover \
    /usr/local/bin/brcmfmac-resume-recover
pkexec systemctl enable brcmfmac-resume-recover.service
```
(Re-enabling is a separate act on purpose: the unit comes back dormant, so a
restore cannot silently start two things that both try to reload the driver.)

**Rule 3.** Not breached.

---

## C31 — `mbp-wakeup.service` removed

**When.** 2026-10-20 14:38.

**What.** `/etc/systemd/system/mbp-wakeup.service` and its `.wants/` symlink.
Preserved at `/var/backups/mbp-sleep/20261020-143804/mbp-wakeup.service`.

**Why.** Its `ExecStart` pointed into the repository checkout, so a moved or
deleted repository silently left `SPIT` disabled — and `SPIT` disabled is a
reduction of wake sources, which rule 3 forbids. The daemon now re-arms `SPIT`,
`XHC1` and `LID0` at every start, from the installed program.

**Worked.** Verified: `/proc/acpi/wakeup` lists `SPIT`, `XHC1` and `LID0` as
`*enabled` after the daemon started, and the daemon logs nothing that reads
"still disabled".

**Undo.**
```sh
pkexec install -m 644 -o root -g root \
    /var/backups/mbp-sleep/20261020-143804/mbp-wakeup.service \
    /etc/systemd/system/mbp-wakeup.service
pkexec systemctl enable mbp-wakeup.service
```

**Rule 3.** Not breached — this change protects rule 3 rather than weakening it.

---

## C32 — the freeze drop-in is kept, and deliberately not rewritten

**When.** 2026-10-20 14:38 (first install), 14:46, 14:50 (re-runs).

**What.** Nothing changed.
`/etc/systemd/system/systemd-suspend.service.d/10-no-freeze.conf` still holds the
2026-10-19 content, including the operator's own annotations.
`install.sh` checks for `^Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false`
and leaves the file alone when it is already there; only a missing file is
created.

**Why.** C1 is the operator's long-term setting (rule 5.1). The first draft of
the installer rewrote the file unconditionally, which would have thrown away the
comments explaining why it exists.

**Worked.** `not yet tested` — unchanged from C1, which was already in effect.

**Undo.** None needed; nothing was changed.

**Rule 3.** Not breached.

## C33 — four corrections to `mbp-sleep`, found by the first real sleep (C24 updated)

**When.** 2026-10-20 16:48, installed over C24. Nothing else about the setup
changed: same unit, same hook, same drop-ins, same configuration file name.

**What.** Four changes to the program, each one a defect that the 16:09 cycle
exposed (`docs/progress.md`, 2026-10-20 16:09):

1. **The CIFS remount after a resume is detached and retried.** `post` used to
   call `cifs_mount()` once, inside the hook, where NetworkManager has not yet
   brought the interface back. On 16:09 that attempt failed one second after the
   Wi-Fi driver was reloaded, and `/mnt/shareA` stayed down for eight minutes. It
   is now a detached `mbp-sleep cifs-reconnect` that retries every 3, 6, 12 ...
   seconds for up to `cifs_reconnect_wait` (120 s).
2. **The Wi-Fi modules are unloaded in the order they are listed**, not reversed.
   The list is `brcmfmac_wcc brcmfmac`, and reversing it produced
   `Module brcmfmac is in use` before `brcmfmac_wcc` succeeded anyway.
3. **`mbp-sleep status` no longer reports a running daemon as NOT RUNNING.**
   `kill(pid, 0)` returns `EPERM` for a root process seen from a user shell, and
   that was being treated as "gone".
4. **A backup is detected by process, not by text.** The configuration key
   `backup_match` (a regular expression over the joined command line) is replaced
   by `backup_names` (program names compared against `argv`). The regex matched
   any command line that merely contained the word `borg`, and a false positive
   here **stops the machine sleeping**, which is the exact failure this project
   exists to remove. Verified both ways: a fake `/tmp/opencode/borg` process is
   detected, a shell command containing the word is not.

**Why.** The 16:09 cycle proved the approach works — `Filesystems sync` fell from
95.554 s to **0.019 s** — and then failed its own criterion on the remount.

**Worked.** Partly, and only the part that can be exercised while awake:

| check | result |
|---|---|
| `cifs-reconnect` after a manual `umount /mnt/shareA` | remounted in **562 ms**, `/mnt/shareA cifs //syncs.asuscomm.com/shareA` |
| idle CPU of the daemon | **0.28%** (was 1.1-1.4% before C24's watcher gating) |
| `dbus-monitor` processes between backups | **0** |
| `mbp-sleep status` first line | `daemon : running, pid 148302` |

Not yet verified: that the remount works after a **real** suspend, which is the
condition that actually failed. That is the remaining criterion of Step 15.

**Known leftover.** The installed `/etc/mbp-sleep.conf` still carries the old
`backup_match` line from the 16:02 install, which is now inert. It is harmless —
`backup_names` falls back to `borg` — but it should be deleted the next time that
file is edited by hand. `install.sh` never overwrites an existing configuration
file, on purpose.

**Undo.**
```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-164858/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec systemctl restart mbp-sleep.service
```
(That is the 16:02 build: sleep works, the share does not come back.)

**Rule 3.** Not breached.

## C34 — the suspend watcher now sees `SuspendWithFlags`, and the lock has a release valve

**When.** 2026-10-20 17:11, installed over C33 (`/var/backups/mbp-sleep/20261020-171138`).

**Why.** Between 16:54:30 and 16:55:27 a backup was running and the daemon held
its block lock. The operator pressed suspend twice; both were refused by
`logind`, and the daemon **never recorded the requests**, so nothing would have
been re-issued when the backup ended. The refusal is correct behaviour; losing
the request is not.

**What.**

1. **The bus filter no longer matches on the method name.** It was
   `member='Suspend'`, and a D-Bus match rule compares the member *exactly*.
   The suspend key on this machine is handled by `/usr/lib/gsd-media-keys`,
   which calls **`SuspendWithFlags`** (the string is in the binary), so the
   watcher received nothing at all. The filter is now the interface alone, and
   the needle `member=Suspend` matches as a prefix, which covers `Suspend`,
   `SuspendWithFlags`, `SuspendThenHibernate` and their variants.
2. **The block lock is released after `defer_max_wait`.** The safety valve
   existed only for the *pending* request: it stopped re-issuing the suspend but
   left the lock held. A backup that hung would therefore have made the machine
   unable to suspend for good — the exact failure this project exists to remove.
   A backup outliving the limit is now treated as hung: the lock is released,
   the reason is logged, and the lock is not re-taken until that backup ends
   (`gave_up`). The new fields are `lock_since` and `gave_up`.

**Verified.** Live, on the real machine, with a stand-in backup:

| step | result |
|---|---|
| fake `borg` process started, daemon saw it | `lock: block on sleep held` |
| `SuspendWithFlags` sent as uid 1000 (what the keyboard does) | refused: `BlockedByInhibitorLock` |
| daemon reaction | `suspend: deferred until the backup ends (asked on the bus)` |

**Worked.** The request is now recorded, which it was not before. Not yet
observed end to end: a real backup ending and the machine then suspending
itself. That is the remaining half of Step 16.

**Known consequence.** While a backup runs, a suspend request still makes
GNOME offer the password prompt for `org.freedesktop.login1.suspend-ignore-inhibit`
("force it anyway"). Cancelling it is harmless — the request is remembered and
the machine suspends when the backup ends. Whether to silence that prompt with a
`polkit` rule is an open decision, recorded as T33 in `docs/progress.md`.

**Undo.**
```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-171138/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec systemctl restart mbp-sleep.service
```
(That is the C33 build: `SuspendWithFlags` is invisible and the lock has no
release valve.)

**Rule 3.** Not breached.

## C35 — `silence_force_prompt`: the "force it anyway" prompt is a setting, not a hardened system

**When.** 2026-10-20 17:31-17:44, installed by `install.sh`
(`/var/backups/mbp-sleep/20261020-174322` is the newest full manifest). Operator's
ruling: *"this setting change must be part of our project, ideally controllable
from the configuration file."*

**Why.** With the backup lock held, a suspend request from the desktop makes
polkit offer the password that would force the suspend past the lock (action
`org.freedesktop.login1.suspend-ignore-inhibit`). On 16:55 that prompt was
mistaken for a fault. The request is now remembered and re-issued when the
backup ends (C34), so the prompt only adds confusion — but it must not be
removed by editing system policy behind the project's back.

**What.**

1. **A new switch**, `silence_force_prompt`, default `on`, in both
   `macbook.conf` and the compiled-in defaults.
2. **`mbp-sleep` generates the rule itself** at daemon start:
   `/etc/polkit-1/rules.d/49-mbp-sleep-no-force-suspend.rules`. It denies only
   `org.freedesktop.login1.suspend-ignore-inhibit`, for every local subject. It
   is rewritten only when its content would change, deleted when the switch is
   turned off, and never touches a file that does not carry its
   `generated by mbp-sleep` marker.
3. **C35a.** `/etc/mbp-sleep.conf` gained the same switch, with its comment
   block, appended by hand at 17:31 (prior file copied to
   `/var/backups/mbp-sleep/20261020-173114/mbp-sleep.conf.before-silence`).
   `install.sh` never overwrites an existing configuration; it now **prints the
   switches that exist in `macbook.conf` but not in the installed file**, so the
   next added switch cannot be invisible.
4. **C35b.** `install.sh` creates `/etc/polkit-1/rules.d` (`install -d`, root:root
   0755). It did not exist on this machine, and polkitd only watches directories
   that exist when it starts — a rule written into a directory created later was
   invisible until polkitd was reloaded.
5. **C35c.** `mbp-sleep` reloads polkit after writing or deleting the rule
   (`systemctl reload polkit`). Without it, the rule written at 17:31 was not
   applied: `pkcheck` still answered `auth_admin_keep`.
6. `uninstall.sh` removes the rule, but only if it carries the marker.

**Verified**, on the real machine, by asking polkit directly as the desktop user
(`pkcheck --action-id org.freedesktop.login1.suspend-ignore-inhibit --process $$`):

| state | answer |
|---|---|
| switch `on` | `polkit.result=no`, `Not authorized.` — no prompt |
| switch `off`, service restarted | file deleted, `polkit.result=auth_admin_keep` |
| switch `on` again | file rewritten, `polkit.result=no` |
| `org.freedesktop.login1.suspend` (the real suspend action) | unchanged, `auth_admin_keep` |

The first version of the rule matched `subject.local` as well, and **did
nothing**: for a process subject that property came back unset, the rule was
skipped, and the action kept its default. The rule now matches the action alone.

**Cost, stated plainly.** While the switch is on, `suspend-ignore-inhibit`
cannot be authorized at all, so a suspend cannot be forced past *any* block
inhibitor. If this project's own lock ever misbehaves, the escape hatch is
`systemctl stop mbp-sleep` (which releases the lock and does not remove the
rule), or turn the switch off and restart the service.

**Undo.**
```sh
pkexec sed -i 's/^silence_force_prompt.*/silence_force_prompt = off/' /etc/mbp-sleep.conf
pkexec systemctl restart mbp-sleep.service     # removes the rule and reloads polkit
```
And to remove the switch from the configuration file entirely, restore the copy
named above with `pkexec cp -a .../mbp-sleep.conf.before-silence /etc/mbp-sleep.conf`.

**Rule 3.** Not breached: no wake source was touched, Thunderbolt is untouched.

**Correction (same day).** C35's header names the backup directory
`/var/backups/mbp-sleep/20261020-174322`, which does not exist. The last
manifest written by the install that carried C35 is
`/var/backups/mbp-sleep/20261020-174224`.

## C36 — network filesystems are discovered, not named

**When.** 2026-10-20 18:09, installed by `install.sh`
(`/var/backups/mbp-sleep/20261020-180946`).

**Why.** Operator's question: `/mnt/shareA` is machine-specific, so a project
that hard-codes it cannot be a general solution. He is right, and it was a real
limitation of the code rather than of the idea.

**What.**

1. **`cifs_auto` (default `on`).** The mount points to take down before sleep
   are read from `/proc/mounts` by filesystem type, not from a list of share
   names. `network_fstypes` (default `cifs smb3 nfs nfs4 fuse.sshfs`) decides
   which types count. A machine with NFS, with other SMB shares, or with none at
   all needs no code change.
2. **`cifs_shares` is only read when `cifs_auto` is off.** That is the old
   behaviour, kept so an existing configuration file keeps working.
3. **What was taken down is remembered** in `/run/mbp-sleep/network-unmounted`
   and cleared once the shares are back. After a resume the mount table no
   longer contains them, so discovery alone could not answer "what do I put
   back".
4. `mbp-sleep status` now lists the network filesystems it actually found.

**Verified**, on this machine:

| check | result |
|---|---|
| discovery with `cifs_auto = on` | `/mnt/shareA` only — the three idle `automount` shares are invisible, which is exactly right |
| discovery with `cifs_auto = off` | the four configured paths, as before |
| real cycle: `cifs_unmount` → `cifs-reconnect` | unmounted `/mnt/shareA (cifs)`, remembered it, remounted in **0 s**, then cleared the record |
| after touching `/mnt/shareC` | it appeared as `(cifs)` and became a target automatically — no configuration change |

**Worked.** Yes, for everything measurable while awake.

**C36a.** The same keys were appended to `/etc/mbp-sleep.conf` at 18:10 (prior
file copied to
`/var/backups/mbp-sleep/20261020-181021/mbp-sleep.conf.before-auto`).

**Undo.**
```sh
pkexec sed -i 's/^cifs_auto.*/cifs_auto = off/' /etc/mbp-sleep.conf
pkexec systemctl restart mbp-sleep.service
```
which restores the named-list behaviour. The binary itself reverts with the
backup directory above.

**Rule 3.** Not breached.

## C37 — the shipped defaults no longer contain anyone's shares

**When.** 2026-10-20 18:40, installed by `install.sh`
(`/var/backups/mbp-sleep/20261020-184030`).

**Why.** Operator's ruling while the README was being written: personal content
does not belong in a project that is meant to be general. Two places still
carried it.

**What.**

1. **`cifs_shares` defaults to empty.** Since C36 the mounts are discovered by
   type, so a list of share names is only meaningful when `cifs_auto = off`, and
   then it is the operator's list, not the author's. `macbook.conf` and the
   compiled-in default are now `cifs_shares =` with a comment saying so.
2. **The installed unit's `Documentation=` line** pointed at
   `file://~/sync/projects/...`, which is a path that exists on exactly
   one machine. It now points at `man:systemd-suspend.service(8)`, which is
   installed by systemd itself.

**Verified.** `install.sh` installed the new unit
(`Documentation=man:systemd-suspend.service(8)`), the service is active, and the
compiled-in default is `''` while discovery still returns the same targets as
before.

**Not changed, on purpose.** The live `/etc/mbp-sleep.conf` keeps its own
`cifs_shares` line. That file belongs to the machine, not to the project, and
the line is inert while `cifs_auto = on`.

**Correction (same day).** C37's header names the backup directory
`/var/backups/mbp-sleep/20261020-184030`, which does not exist; the manifest
written by that install is `/var/backups/mbp-sleep/20261020-183911`.

**Undo.**
```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-183911/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec install -m 0644 -o root -g root \
    /var/backups/mbp-sleep/20261020-183911/mbp-sleep.service \
    /etc/systemd/system/mbp-sleep.service
pkexec systemctl daemon-reload && pkexec systemctl restart mbp-sleep.service
```

**Rule 3.** Not breached.

---
## C38 — the documentation was cut back to what describes the project now

**When.** 2026-10-20 19:20, by the operator's instruction: *"these contents are
all useless — check the documents, keep only what relates to the project's
current state."*

**Why.** The investigation is over and its record had become the repository: 23k
of the tree's 24k lines were test logs, retractions and instruments for a
question that has an answer. A reader looking for "how do I use this" had to
first know which of seven documents was still true, and two of them said in their
own first paragraph that they were retracted. It also cleared the last rule 0
violation in the tree: the two Chinese quotations in this file (C7 and C10) were
the only CJK left, and both are now English.

**What.**

1. Removed from `docs/`: `progress.md` (16,989 lines), `root-cause-plan.md`
   (2,025), `diagnosis.md` (225), `investigation-state.md` (218),
   `systemd-freeze-dropin.md` (205), `ec-keys.md` (171), `smc-keys.md` (383),
   `diagnosis-ec-gpe4e.md` (94, itself marked retracted), and the data behind
   them: `acpi-dump/` (44 files), `ref-acpi/` (8 files, other people's ACPI
   attachments from kernel bug 101681), `artifacts/` (4 old wakeup snapshots).
2. Removed from `scripts/`: the investigation instruments `hang-sampler.sh`,
   `hang-snap-read.sh`, `heartbeat.sh`, `nvs-snap.sh`, `smc-dump.sh`,
   `step7-run.sh`, `test-wedge.sh`, `vt-ftrace.sh`, `udp-log-5555.py`,
   `root-cause-trace.sh`, `wakeup-snap.sh`, `wakeup-snap2.sh`,
   `disable-wakeup.sh`, and the kernel module source `mbp-nvs-read.c` with its
   `Makefile`; also `session-export.py`, whose only input was `docs/sessions/`.
   Kept: `diagnose.sh`, `test-suspend.sh`, `run-report.sh`, `set-wake.sh`.
3. Added `docs/background.md`: the machine, the three measured faults, the
   "do not read these as ruled out" caveat, the pruned-file list, and the
   `git show local-history:<path>` recipe for reading any of it.
4. Rewrote `AGENTS.md`, 739 lines to about 150. Kept every rule that still
   bites (English, pkexec, Wayland, the three hardware constraints, record every
   change with an undo, consent before anything that needs the operator, look it
   up first, verification, no artifacts outside the repo). Dropped the ones whose
   subject no longer exists: the numbered root-cause plan and its step discipline,
   the four-questions-per-run protocol, the prior-art tables for instruments that
   are gone, and the §5 invariant narratives.
5. Removed `.gitattributes` (it existed only to keep rule 0's CJK grep from
   matching bytes inside `docs/ref-acpi/*`) and the `.gitignore` rules for the
   files that went with it.
6. Fixed the references that survived: `README.md` (three), `CHANGELOG.md` (a
   note at the top), `macbook.conf` (three), `mbp-sleep` (one comment),
   `scripts/test-suspend.sh` (two comments). Citations inside this file were
   **not** rewritten — it is append-only — so the note at its top now explains
   them.

**Verified.** Rule 0's CJK grep prints nothing. No tracked file references a
removed document except the append-only citations described above. `bash -n`
passes on both edited scripts. `git status` reports no untracked leftovers, and
the program, configuration and installer were not modified by this entry.

**Not changed.** `docs/config-changes.md` itself, in full: it is the only record
of how to undo what is installed on the machine, including the freeze drop-in
and the `mbp-sleep` unit, so deleting it would have removed the undos along with
the history.

**Worked.** Yes — the tree now describes what the program does and why, and
nothing else.

**Undo.** Everything removed is in the local `local-history` branch (its tip
before the prune was `f20b44b`), which is not published.
```sh
cd ~/sync/projects/mbp-sleep
git revert --no-edit "$(git log --format=%H --grep='Prune the documentation' -1)"
```

**Rule 3.** Not breached.


---
## C39 — the record was corrected with real S3 residence, and a five-minute sleep was measured

**When.** The sleep test ran 2026-10-20 20:17:54 → 20:22:56. This entry and the
document correction were written at 20:35. Neither changed any machine state.

**Why.** The documentation pass that was interrupted at 19:20 had begun to
retract the Thunderbolt explanation using two S3 figures — "100.5 s and 5.9 s" —
that were read from the wrong column. They are the *awake* times of the 11:56
and 10:59 cycles on boot -1; the real S3 residences are **2.443 s** and
**57.450 s**. The 2.443 s cycle is an instant wake, so it cannot support "the
adapter attached is harmless". The operator's report that the two-second wake
had stopped and the wrong numbers needed the same measurement.

**What.** No change to the machine. Documents changed:

1. `README.md`: one usage statement corrected — it no longer says
   `mbp-sleep report` answers "which wake source fired". The measurements stay
   out of the README, which describes the program for other users; this file and
   `docs/background.md` carry the test record.
2. `docs/background.md`: the retraction section is replaced by the two symptoms
   measured separately, with the per-boot table and the distinction between
   correlation and attribution.
3. `docs/config-changes.md`: this entry.

**How the number is measured.** `journalctl -b N -o json`, then for the
`PM: suspend entry` / `PM: suspend exit` pair:

```
S3 = (__REALTIME_TIMESTAMP_exit - __REALTIME_TIMESTAMP_entry)
   - (__MONOTONIC_TIMESTAMP_exit - __MONOTONIC_TIMESTAMP_entry)
```

Monotonic time does not advance in S3. The wall-clock figure printed by
`mbp-sleep report` includes the pre-suspend work (the 194.6 s and 95.6 s syncs
are in it) and is not S3.

**What the measurement showed.**

| cycle | devices before sleep | S3 |
|---|---|---|
| boot -2, 23 of 24 sleeps | adapter absent for most of them; `brcmfmac` loaded | 1.6–2.9 s |
| boot -1, 10:59 | adapter `0-3` attached, authorised (no hook) | 57.450 s |
| boot -1, 11:56 | adapter `0-1` attached, authorised (no hook) | 2.443 s |
| boot -1, 16:09 | `0-1 authorized=0`; `brcmfmac` unload FAILED (`in use`) | 2.466 s |
| boot 0, 16:55 | `brcmfmac_wcc` + `brcmfmac` unloaded; `0-1 authorized=0` | 17.630 s |
| boot 0, 19:46 | same | 13.531 s |
| boot 0, 20:17 | same | **297.616 s** |

The Thunderbolt adapter was absent for most of boot -2's two-second wakes, and
de-authorising its endpoint at 16:09 did not stop one. Every two-second wake had
`brcmfmac` loaded, and the three cycles in which it actually unloaded did not have
one — but loaded is not sufficient (57.450 s and 1851 s also had it loaded).
**Correlation, not attribution**; the mechanism is unknown and the wake source is
not written to the journal.

**The 20:17 test.** Queued 20:17:38, `PM: suspend entry` 20:17:54, wake
20:22:56 (operator, power button), `Restarting tasks` normal, Wi-Fi and adapter
restored. It is the first cycle in the retained journal that slept longer than
57 s under the current hook, and the first with no two-second wake after a
successful Wi-Fi unload. It says nothing about staying asleep unattended: the
operator ended it.

**Defect found in the same test, not fixed.** `/mnt/tmcap2` did not come back.
The hook logged `cifs reconnect took 0.00s` (it spawns a detached
`mbp-sleep cifs-reconnect`), but no `cifs: all shares are back` and no
`gave up` line followed — not even the one the child prints after its 120 s
deadline. `/run/mbp-sleep/network-unmounted` still contains `/mnt/tmcap2`, and
`mbp-sleep status` reported it "not back yet" nine minutes later. The server was
reachable at the time (TCP 445 to `syncs.asuscomm.com` succeeded).

**Likely mechanism, not verified.** The child is started with
`start_new_session=True`, which changes the session but not the cgroup.
`systemd-suspend.service` has `KillMode=control-group` and `Type=oneshot`, so
when the hook returns the unit stops and systemd kills what is left in its
cgroup — including the child, before NetworkManager has brought the network
back. That would produce exactly what was seen: no output at all from the child.
The same spawn pattern is used for `wifi-verify`. C33's remaining criterion — a
real sleep followed by a successful remount — is still not met.

**Not changed.** The program. S3 residence is still only obtainable by hand from
the journal; `mbp-sleep report` prints wall clock.

**Worked.** The measurement is reproducible from `journalctl -b 0/-1/-2 -o json`.
The "no two-second wake after a successful Wi-Fi unload" statement is n=3 and one
of the three was ended by hand; it is not a fix claim.

**Undo.** The text this pass replaced is in `HEAD`:
```sh
git show HEAD:README.md > README.md
git show HEAD:docs/background.md > docs/background.md
```

**Rule 3.** Not breached: no wake source, module or Thunderbolt router was
changed. The test detached devices for the sleep and restored them on resume, as
the program always does.

---
## C40 — the post-resume helpers run in their own transient units

**When.** 2026-10-20 21:08, installed by `install.sh`
(`/var/backups/mbp-sleep/20261020-210841`). `/etc/mbp-sleep.conf` was kept.

**Why.** `/mnt/tmcap2` has not come back after a sleep since 16:48. The cause is
not C36's discovery: the 16:55 cycle still used the old named list (its log has
`cifs: /mnt/hx is autofs, nothing to unmount`) and failed the same way.

The cause is how C33 detached the helper. The old hook ran

```
systemd-run --no-block --on-active=25 --unit=cifs-remount-tmcap2 \
    systemctl start mnt-tmcap2.mount
```

a transient timer in its own unit. It worked: `cifs-remount-tmcap2.timer` and
`.service` remounted the share at 10:48:25, 11:01:07 and 11:58:53, 29-40 s after
resume. C33 replaced it with `subprocess.Popen(..., start_new_session=True)`.
`start_new_session` changes the session, not the cgroup: the child stays in
`systemd-suspend.service`, which is `Type=oneshot` with `KillMode=control-group`.
When the hook returns the unit stops and systemd kills the child. Measured:
16:55:37, 19:46:26 and 20:17:40 each unmounted the share; the reconnect then
left **no log at all**, not even the `gave up` line it prints after 120 s. The
mounts at 17:17:14 and 20:16:59 were `borg-backup.service` pulling in the mount,
not the reconnect.

**What.** `mbp-sleep` gains `spawn_detached()`. It starts the helper as

```
systemd-run --unit=mbp-sleep-<command>-<pid>-<epoch> --collect --no-block
```

so the helper is in its own cgroup and is not killed with the sleep unit. If
`systemd-run` fails, it falls back to the old `Popen` and says so in the log.
Both `wifi-verify` and `cifs-reconnect` use it.

**Where.** `mbp-sleep` (source) -> `/usr/local/sbin/mbp-sleep`; `do_post()`.

**Verified while awake.**

| check | result |
|---|---|
| `python3 -m py_compile mbp-sleep` | passes |
| a `setsid` child of a `KillMode=control-group` oneshot unit | killed (no file after 6 s) |
| the same command under `systemd-run --collect --no-block` | survived (file present) |
| installed hash | `f3e7bfe3778572692886a33473e59182cc028a42794515ef259928e49aa6f92d` |

**Not yet tested.** That the remount works after a **real** suspend, and after
the equivalent `post`-under-a-oneshot-unit test. That is the criterion; until it
is met this entry reads `not yet tested`.

**Known, not fixed.** C36's discovery has one edge: if a share is already
unmounted before sleep and `/run/mbp-sleep/network-unmounted` is empty, the
target list is empty, `cifs_satisfied()` returns true for the empty list, and
nothing tries to mount it. The old named list did try. It did not cause the
observed failures (the share was mounted at each of those sleeps), but it is a
real hole in "discover by type".

**Undo.**

```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-210841/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec systemctl restart mbp-sleep.service
```

**Rule 3.** Not breached.

**C40a — the equivalent test passed (2026-10-20 21:15).** `/mnt/tmcap2` was
already unmounted and `/run/mbp-sleep/network-unmounted` held it. `post` was
started inside `mbp-post-test-211426.service` with `Type=oneshot` and
`KillMode=control-group` — the condition that killed the old child. The parent
deactivated at 21:15:04; `mbp-sleep-cifs-reconnect-51870-1792502104.service`
stayed alive and logged `cifs: started mnt-tmcap2.mount` and
`cifs: all shares are back` at 21:15:09. The state file was gone. The
`wifi-verify` helper also ran in its own unit and exited cleanly.

The real-suspend criterion is still untested: in this test the network was
already up, so the retry path (which the real resume needs) was not exercised.

**C40b — the real-suspend test passed (2026-10-20 21:21-21:31).** Suspend
requested 21:21:49, `PM: suspend entry (deep)` 21:21:51, wake 21:31:32. S3
residence **573.422 s** (realtime delta minus monotonic delta); no two-second
wake. The post hook started
`mbp-sleep-cifs-reconnect-52822-1792503094.service` at 21:31:34. The first two
mount attempts failed while the network was still down (21:31:34 and 21:31:38),
`wlan0` connected at 21:31:39, and the third attempt logged
`cifs: started mnt-tmcap2.mount` and `cifs: all shares are back` at 21:31:44.
`/mnt/tmcap2` was mounted and `/run/mbp-sleep/network-unmounted` was cleared.

**The C40 criterion is met.** The helper survived the stop of
`systemd-suspend.service`, and the retry path works after a real resume. C40's
`not yet tested` is superseded for this criterion; the "share already down
before sleep and no state record" hole noted there is still open.

---
## C41 — the installed program reports its version

**When.** 2026-10-20 22:28, `install.sh`
(`/var/backups/mbp-sleep/20261020-222800`).

**Why.** C40's binary was installed at 21:08, before the version source existed.
It had no `--version`, and `/usr/local/share/mbp-sleep/VERSION` did not exist, so
the installed program could not say which release it was.

**What.** Installed the current `mbp-sleep` (0.1.1: C40 plus `--version`) and
copied `VERSION` to `/usr/local/share/mbp-sleep/VERSION`. No configuration
change.

**Where.** `/usr/local/sbin/mbp-sleep`,
`/usr/local/share/mbp-sleep/VERSION`.

**Verified.**

| check | result |
|---|---|
| `mbp-sleep --version` | `mbp-sleep 0.1.1` |
| `/usr/local/share/mbp-sleep/VERSION` | `0.1.1` |
| installed hash | `ba0bc6ea3f5020b6c37f700e80f43c3ae110fa9e005c151093aa422ce3be4cfa` (same as the repository file) |
| service | active / enabled |
| `mbp-sleep status` | no backup running, not deferring, share mounted |

**Worked.** Yes for the version output and the install. The C40 behaviour was
already exercised on a real sleep (C40b).

**Undo.**

```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261020-222800/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec rm -f /usr/local/share/mbp-sleep/VERSION
pkexec rmdir /usr/local/share/mbp-sleep 2>/dev/null || true
pkexec systemctl restart mbp-sleep.service
```

**Rule 3.** Not breached.

---
## C42 — retraction: unloading `brcmfmac` does not prevent the two-second wake

**When.** Noticed 2026-10-21 09:51 in the journal of boot 0. No machine change.

**Why.** C39 and C40 recorded a correlation: every two-second wake had
`brcmfmac` loaded, and the cycles in which it actually unloaded slept 13-573 s.
The 23:06 cycle on 2026-10-20 falsifies it.

**What the machine shows.**

| cycle | devices before sleep | S3 residence |
|---|---|---|
| 23:06:19 | `brcmfmac_wcc` + `brcmfmac` unloaded; Thunderbolt `0-1 authorized=0` | **2.749 s** |
| 23:20:22 | same | **37753.242 s** |

The first is an instant wake with the Wi-Fi driver absent, so a loaded driver is
not necessary. The second is the first unattended ten-hour sleep in the retained
journal: resumed 09:49:40, CIFS reconnect started 09:49:42, share back 09:49:53.

The 23:06 attempt followed `Lid closed.` at 23:06:17; the machine woke at
23:06:30 and stayed up until `Lid opened.` at 23:17:35. No
`/sys/class/wakeup/*/event_count` snapshot was taken for that cycle, so the
source of that wake is not known.

**What was changed.** `docs/background.md`: the instant-wake section and the
"what is established" row now record the 23:06 counterexample instead of the
correlation; the boot-0 row includes the 2.749 s and 37753.24 s cycles.

**Worked.** Not a fix; the retraction is the change. Attributing the wake needs a
wakeup snapshot taken around the sleep, which the 23:06 cycle did not have.

**Undo.** `git revert` this commit; the prior text is in the parent commit.

**Rule 3.** Not breached.

---
## C43 — a self-wake with the lid shut is followed by a sleep, and the wake counters are logged

**When.** 2026-10-25. Repository change written first; the install and the sleep
test follow and are recorded in C43b.

**Why.** The machine woke itself twice on 2026-10-23 with the lid shut
(12:03:10 → 12:04:09, 59 s; 19:45:27 → 23:22:13, 21646 s) and nothing sent it
back to sleep: logind's lid handling is off here by design, and `mbp-sleep` acts
only on an open→closed edge. The second one left the machine awake for
**38 h 7 min**, lid shut, until the operator opened the lid on 2026-10-25
13:29:31. `systemd-logind` logged no `Lid opened.` in between, so no lid event
was missed and these were not lid wakes.

The wake source is **not identified**, and this change does not identify it.
Masking the EC's GPE `0x4E` did not stop the wake (F58, retracted), and the
sources Linux can turn off are `SPIT`, `XHC1` and `LID0`, which the operator
needs (AGENTS.md rule 3). So the wake is left alone and its consequence is
removed; `wake_log` is what makes the next attribution possible.

**What.**

| file | change |
|---|---|
| `mbp-sleep` | `Daemon.detect_resume()` / `maybe_resuspend()`: `CLOCK_BOOTTIME - CLOCK_MONOTONIC` jumps by the S3 residence, so a resume is visible inside the daemon without a new hook. A resume with the lid still closed schedules a suspend after `resuspend_delay`; the count resets after a sleep of 300 s or more, or when the lid opens; `resuspend_max` caps a wake/suspend loop. `read_wake_counters()`, `wake_snapshot()` (called at the end of `pre`) and `wake_report()` (start of `post`) log which `event_count`/GPE counters moved. New defaults: `resuspend`, `resuspend_delay`, `resuspend_max`, `wake_log`. `status` lists the two new switches; `report` points at the log. |
| `macbook.conf` | section 7 (self-wake) added; the session-freeze section renumbered to 8. |
| `README.md`, `docs/background.md`, `CHANGELOG.md` | the behaviour, the 2026-10-23 measurement, and the unreleased entry. |

**Where.** `/usr/local/sbin/mbp-sleep`; the four keys are added to
`/etc/mbp-sleep.conf` by hand, because `install.sh` keeps the existing file and
only reports the switches that are missing from it.

**Verified so far.** The script compiles; a harness against the real counters
moved `wakeup37` by +1 and `gpe4E` by +123 and the log line named both;
`detect_resume()` logged `21646s`, scheduled attempt 1/3, `maybe_resuspend()`
issued the request, four short wakes stopped at the cap, and an open-lid resume
reset the count. **No sleep has been exercised with this code yet.**

**Undo.** The previous program is the one `install.sh` backs up to
`/var/backups/mbp-sleep/<timestamp>/mbp-sleep` (the installer prints the
timestamp; the previous source is `git show a94e1b1:mbp-sleep`, and its sha256
is `ba0bc6ea3f5020b6c37f700e80f43c3ae110fa9e005c151093aa422ce3be4cfa`, which is
what `/usr/local/sbin/mbp-sleep` has held since C41 — verified again before this
entry was written).

```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/<timestamp>/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec sed -i -e '/^resuspend *=/d' -e '/^resuspend_delay *=/d' \
    -e '/^resuspend_max *=/d' -e '/^wake_log *=/d' /etc/mbp-sleep.conf
pkexec systemctl restart mbp-sleep.service
```

`resuspend = off` alone stops the new behaviour without reinstalling; the
counters keep being logged until `wake_log = off`.

**Worked.** Not yet tested — the change is written into the repository only; the
install and the sleep test have not happened yet, and C43b records them.

**Rule 3.** Not breached. No wake source is disabled or removed: `LID0`,
`SPIT` and `XHC1` stay enabled. The change only decides to sleep again after a
wake nobody asked for.

## C43b — C43 was installed after all: the program, and the four configuration keys

**When.** 2026-10-25, 16:37:19 to 16:38:43. This entry was written at 23:40 the
same day, after the fact.

**Why.** C43 ends with "Not yet tested — the change is written into the
repository only; the install and the sleep test have not happened yet, and C43b
records them." The install *did* happen, sixteen minutes after C43 was
committed, and nothing recorded it. As written, C43 tells a reader that this
machine still runs the C41 program. It does not. C43 itself is not edited
(rule 5: append, never edit), so this entry is the correction.

**What.** No source change; nothing here is new behaviour, it is the install of C43.

| where | what | evidence |
|---|---|---|
| `/usr/local/sbin/mbp-sleep` | replaced with the C43 program | mtime 16:37:19, sha256 `2f7c31b408d7e97e6607894ab93f669015f1976411ff34829e710760d72204e6`, identical to `git show 8315b5b:mbp-sleep` |
| `/etc/mbp-sleep.conf` | `resuspend`, `resuspend_delay`, `resuspend_max`, `wake_log` added, by hand | mtime 16:38:00; the keys are at lines 120-123 with the values `on`, `10`, `3`, `on` |
| `/var/backups/mbp-sleep/20261025-163719/` | what the installer saved before writing | `mbp-sleep` sha256 `ba0bc6ea…` (= `git show a94e1b1:mbp-sleep`, the program C41 installed); `mbp-sleep.conf.before-c43` sha256 `6e66daba…` |
| `/etc/systemd/system/mbp-sleep.service`, `/usr/lib/systemd/system-sleep/50-mbp-sleep` | rewritten by `install.sh`, content unchanged | both mtime 16:37:19, sha256 identical to the copies in the backup directory |
| `mbp-sleep.service` | restarted | `ActiveEnterTimestamp=Sun 2026-10-25 16:38:43 CST` |

**Where.** `/usr/local/sbin/mbp-sleep`, `/etc/mbp-sleep.conf`, plus the two
units that `install.sh` rewrites from the same source.

**Verified so far.** The installed file is byte-identical to `8315b5b`, so the
program on the machine is C43 and nothing else. The daemon then logged
`resume: 896s of sleep; lid is open` at 16:56:28 for the sleep it requested at
16:41:04, which is `detect_resume()` doing exactly what C43 says — the
`CLOCK_BOOTTIME` difference, named in seconds, once per resume. **The
re-suspend path has not been exercised**: every resume since the install found
the lid open, so `maybe_resuspend()` has never had to send the machine back to
sleep.

**Undo.** Restores both files to their pre-C43 content and restarts the daemon:

```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261025-163719/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec install -m 644 -o root -g root \
    /var/backups/mbp-sleep/20261025-163719/mbp-sleep.conf.before-c43 \
    /etc/mbp-sleep.conf
pkexec systemctl restart mbp-sleep.service
```

Nothing has been added to `/etc/mbp-sleep.conf` since 16:38, so restoring that
backup loses no later setting. `resuspend = off` alone would also stop the new
behaviour without reinstalling anything.

**Worked.** Partly. Installed and running, and resume detection exercised; the
self-wake re-suspend, which is the point of C43, is still `not yet tested`.

## C44 — the record of shares to remount is written before the unmount, and `umount`'s exit code is not believed

**When.** 2026-10-25, from 23:30. Repository change only; the install and the
sleep test that follow it are for C44b. One machine action was taken first, and
is recorded below because it changed the machine: at 23:27:17
`pkexec systemctl start mnt-tmcap2.mount` returned 0 and `findmnt` then showed
`//syncs.asuscomm.com/tmcap2` on `/mnt/tmcap2`; at 23:32 both shares were
mounted. That action is not part of the fix and needs no undo (a reboot, or the
automount's own idle timeout, returns the machine to the same state).

**Why.** On four resumes the machine lost `/mnt/tmcap2` and the log said the
shares were back. The 16:41 cycle is the clearest, and it is one defect in two
halves:

| time | journal | what it means |
|---|---|---|
| 16:41:05.796 | `cifs: could not unmount /mnt/pastime rc=32` (target busy) | pastime really was still mounted, so it was not recorded |
| 16:41:05.799 | systemd: `mnt-tmcap2.mount: Deactivated successfully` | the kernel dropped tmcap2 three milliseconds later |
| 16:41:20.799 | `cifs: could not unmount /mnt/tmcap2 rc=124 timed out after 15s` | the `umount` *command* was killed in the socket teardown, 15 s after the mount it was asked to remove had already gone |
| — | `/run/mbp-sleep/network-unmounted` was never written in that boot | both unmounts "failed", and the old code only recorded the ones that returned 0 |
| 16:56:30.260 → .407 | `cifs-reconnect` started, then `cifs: all shares are back` | 0.14 s: the list `post` checked was rebuilt from the live mount table, which by then contained only pastime |
| — | no `cifs: started mnt-tmcap2.mount` anywhere in the boot | nothing ever tried to remount it |

Two design faults, one in each half. The exit code of `umount` was treated as
the fact, although on a CIFS share it is the exit code of a process that can
hang after the mount is gone. And the list of shares to restore was derived
*after* the fact from `/proc/mounts`, which cannot name a share that has
already disappeared — so the one share that needed putting back was exactly the
one the list could not contain.

This is not a one-off: the same three lines appear at 2026-10-23 05:56 and
19:45 and at 2026-10-25 14:04 and 16:41. The 2026-10-23 19:45 case left
`/mnt/tmcap2` unmounted until 2026-10-24 00:16:21 — 4 h 31 min — even though a
reconnect ran at 23:22:15 and said all shares were back; its
`systemctl start mnt-tmcap2.mount` had failed at 23:22:13 and, because the share
was not in the record, nothing tried again.

**What.**

| file | change |
|---|---|
| `mbp-sleep` | `cifs_unmount()` records every share it is about to unmount **before** the first `umount`, keeps any share an earlier sleep still owes, and — when `umount` returns non-zero — asks `mount_table()` again instead of believing it: a path that is gone is logged as unmounted "although umount exited N". With `cifs_auto = off` the record is trimmed to the configured shares, so a share removed from the configuration stops being owed. New `cifs_list()` is the one place that answers "which shares does this sleep care about" (record first, live table only as a fallback). New `cifs_reconnected()` prints `all shares are back (/mnt/pastime, /mnt/tmcap2)` — the shares it actually checked — or `no network shares to restore`; `cifs_reconnect()` logs `still down: …` when it gives up, instead of only that it gave up. |
| `scripts/test-cifs-record.py` | new: six scenarios against a made-up mount table, no root and no share. It reproduces rc=124 with the mount already gone, rc=32 with the mount still there, a share left over from a failed reconnect, `cifs_auto = off`, "no shares at all", and the give-up message. |
| `README.md` | the network-filesystem section says when the record is written, that a failed `umount` is checked rather than believed, and names the test script. |
| `CHANGELOG.md` | two entries under *Unreleased / Fixed*. |

**Where.** The repository, until C44b installs it: `mbp-sleep` sha256
`24400faad2374f386df41c29de7d63387359bb8777384f343bb74d8098499531`,
`scripts/test-cifs-record.py` sha256
`639118c09763676b2acece3a967d54d1b37fb7bcad58ee114970e7c2401dd21d`.
No configuration key is added or changed, so `/etc/mbp-sleep.conf` is not
touched.

**Verified so far.** The program compiles and `scripts/test-cifs-record.py`
passes 6/6. The harness was also run against the **previous** program
(`8315b5b`), which reproduces the defect exactly — `cifs: could not unmount
/mnt/tmcap2 rc=124 timed out after 15s` with the record left as
`['/mnt/pastime']`, which is what the 16:41 boot did — and the new program
against the same input logs
`unmounted /mnt/tmcap2 (cifs), although umount exited 124; the mount table says
it is gone`, records both shares, remounts tmcap2 and prints
`all shares are back (/mnt/pastime, /mnt/tmcap2)`.
**No sleep has been exercised with this code.** The harness proves the decision
logic, not the machine.

**Known limits of the fix, stated so nobody has to discover them again.** The
record can survive a reboot-free boot forever if a recorded share can never be
mounted again (its unit deleted while the machine stays up): every resume then
spends `cifs_reconnect_wait` and logs `gave up`. With discovery on there is no
authoritative list of wanted shares to prune against, and inventing one would
mean compiling share names into the program, which C36 deliberately removed. A
reboot clears `/run/mbp-sleep` and with it the record.

**Undo.** `install.sh` backs up the program it replaces; the file to put back is
the one installed now:

```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/<timestamp>/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec systemctl restart mbp-sleep.service
```

where `<timestamp>` is the directory `install.sh` printed; its `mbp-sleep` must
have sha256 `2f7c31b408d7e97e6607894ab93f669015f1976411ff34829e710760d72204e6`.
To undo only the repository side, `git revert` the C44 commit. Nothing outside
`/usr/local/sbin/mbp-sleep` and the repository is changed, so nothing else needs
undoing; `/run/mbp-sleep/network-unmounted` is runtime state and can be deleted
at any time.

**Worked.** Not yet tested on the machine. The next real sleep whose `umount`
is cut off at the timeout is the test, and C44b records it.

## C44b — C44 installed

**When.** 2026-10-25, 23:41:04 to 23:41:05, immediately after C44 was committed
and with the operator's consent given for that install.

**Why.** C44 changes what `pre` records and how a failed `umount` is read; it
does nothing until the program on the machine is replaced.

**What.** `pkexec ./install.sh` from the repository at `fcd98fb`. Only the
program changed:

| where | what | evidence |
|---|---|---|
| `/usr/local/sbin/mbp-sleep` | replaced with C44 | sha256 `24400faad2374f386df41c29de7d63387359bb8777384f343bb74d8098499531`, identical to the copy in the repository |
| `/var/backups/mbp-sleep/20261025-234104/` | what the installer saved first | `mbp-sleep` sha256 `2f7c31b4…` (the C43 program), plus `mbp-sleep.service`, `50-mbp-sleep`, `50-mbp-sleep.conf` and `VERSION`, all four byte-identical to what is installed now, so the installer rewrote them with the same content |
| `/etc/mbp-sleep.conf` | **not touched** | mtime still 16:38:00; C44 adds no configuration key |
| `mbp-sleep.service` | restarted | `ActiveEnterTimestamp=Sun 2026-10-25 23:41:05 CST`, `MainPID=421511` |

**Where.** `/usr/local/sbin/mbp-sleep`. Nothing else on the machine differs from
before the install.

**Verified so far.** The installed file is byte-identical to the committed one,
so the machine runs C44 and nothing else. One real, harmless exercise of the new
code: `mbp-sleep cifs-reconnect` against the real mount table printed
`cifs: all shares are back (/mnt/pastime, /mnt/tmcap2)` — the new message, naming
the shares, with both shares already mounted so it neither mounted nor unmounted
anything.

**Not verified.** No sleep has run with this code. Specifically, the branch that
fixes the defect — `umount` returning non-zero while the mount table says the
share is gone — needs a real sleep in which `umount` hangs, and that cannot be
arranged on demand: it happened on four of the resumes recorded in C44 and on
none of the ones before 2026-10-23. The next real sleep is the test; it is
expected to log `cifs: unmounted <path> (cifs), although umount exited N; the
mount table says it is gone` and then, after the resume, `cifs: started
mnt-tmcap2.mount` followed by `cifs: all shares are back (…)`.

**Undo.** Restores the C43 program:

```sh
pkexec install -m 755 -o root -g root \
    /var/backups/mbp-sleep/20261025-234104/mbp-sleep /usr/local/sbin/mbp-sleep
pkexec systemctl restart mbp-sleep.service
```

The four other files in that backup directory are identical to what is
installed, so there is nothing else to restore.

**Worked.** The install: yes, measured above. The behaviour it installs:
`not yet tested`.
