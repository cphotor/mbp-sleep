# Background — what was wrong, what fixed it, and where the rest went

`README.md` describes what the program is and how to use it. This page is the
minimum needed to understand the code: the machine, what is actually established,
what is still open, and why the investigation that produced it is no longer in
the tree.

## The machine

MacBookPro12,1 (2015 13" MacBook Pro), EndeavourOS, kernel 7.2.x, GNOME on
Wayland, S3 (`deep`). The internal Apple/Samsung SSD is both root and swap. The
operator's Thunderbolt-to-Gigabit-Ethernet adapter (`ens9`, `tg3`) is expected to
stay plugged in.

## The two symptoms, measured separately

The project was written for one visible failure — "it sleeps and never comes
back" — and the investigation later found a second, different one: "it wakes by
itself about two seconds after sleeping". They are not the same event, and they
do not rest on the same evidence.

### Instant wake: measured, cause not known

S3 residence for every cycle the journal still holds. It is measured from
`journalctl -b N -o json`, because monotonic time does not advance in S3:

```
S3 = (__REALTIME_TIMESTAMP_exit - __REALTIME_TIMESTAMP_entry)
   - (__MONOTONIC_TIMESTAMP_exit - __MONOTONIC_TIMESTAMP_entry)
```

for the `PM: suspend entry` / `PM: suspend exit` pair. Wall clock is not S3: it
also contains the pre-suspend work.

| boot | cycles that really slept | S3 residence |
|---|---|---|
| -2 (10-19 16:22 → 10-20 02:09) | 24 | **23 at 1.6–2.9 s**; one at 1851 s |
| -1 (10-20 10:32 → 16:53) | 4 | 21.7 s (after a 194.6 s sync), 57.45 s, **2.443 s**, **2.466 s** |
| 0 (10-20 16:53 → 10-21 09:49) | 6 | 17.63 s, 13.53 s, 297.62 s, 573.42 s, **2.749 s**, **37753.24 s** |

What separates them:

- The Thunderbolt adapter was **absent** for most of boot -2's two-second wakes;
  it first appears at 23:44:45. It is not the cause of this symptom.
- At 16:09 the Thunderbolt endpoint was already `authorized=0` and the wake still
  came after **2.466 s**. De-authorising that endpoint does not stop it.
- That same cycle failed to unload `brcmfmac` (`Module brcmfmac is in use` — the
  ordering bug fixed at 16:48). Every cycle after the fix unloaded
  `brcmfmac_wcc` and `brcmfmac`, and slept **17.63 s, 13.53 s, 297.62 s and
  573.42 s**.

**Unloading the Wi-Fi driver does not prevent the two-second wake.** That was
the working correlation until 2026-10-20 23:06: every two-second wake had
`brcmfmac` loaded, and the four cycles in which it actually unloaded had slept
13-573 s. At 23:06:19 the hook unloaded `brcmfmac_wcc` and `brcmfmac`,
de-authorised the Thunderbolt endpoint, and the machine still woke after
**2.749 s**. The same detachment then slept **37753.24 s** at 23:20. The wake is
intermittent, not tied to the driver state, and the mechanism is not known.

The 23:06 attempt followed `Lid closed.` at 23:06:17; the machine woke at
23:06:30 and stayed up until `Lid opened.` at 23:17:35. No
`/sys/class/wakeup/*/event_count` snapshot was taken for that cycle, so its wake
source is unknown. The 23:20 cycle is the first unattended ten-hour sleep in the
retained journal.

### The consequence: a self-wake with the lid shut is not followed by a sleep

Measured 2026-10-23/25 on boot 0, from the kernel journal and
`systemd-logind`'s own lid messages:

| suspend entered | resumed | lid | awake afterwards |
|---|---|---|---|
| 12:03:10 | 12:04:09 (**59 s**) | closed the whole time | **7 h 14 min**, until `Lid opened.` at 19:18:55 |
| 19:45:27 | 23:22:13 (**21646 s**) | closed the whole time | **38 h 7 min**, until `Lid opened.` at 2026-10-25 13:29:31 |

logind logged **no `Lid opened.` between the close and the resume**, so these
were not lid wakes, and no lid event was missed: the lid was shut from
`Lid closed.` at 19:45:10 until 2026-10-25 13:29:31. Because logind's lid
handling is off by design and the daemon acts only on an open→closed edge,
nothing re-suspended the machine; it sat awake with the lid shut.

The GNOME session history marks the session active for five minutes after each
of these resumes (23:22:17 → 23:27:17 is exactly `idle-delay`, and the same
signature appears at 12:04:14 → 12:09:14). That is the resume, not an operator:
on 12:04 logind proves nobody opened the lid.

**Not established:** who woke it. The counters moved (same per-cycle signature
as F23), the source stays unattributed. **What changed:** `resuspend` sends the
machine back to sleep when a resume finds the lid still closed, and `wake_log`
records the counter deltas (C43).

### "It sleeps but never comes back": not established

Four boots in the retained journal end at `PM: suspend entry` with no exit
(10-18 20:40:25, 10-19 01:20:55, 10-19 11:39:01, 10-20 02:09:10). All four had
the Thunderbolt adapter attached and the Wi-Fi loaded. But sleeps with the same
two devices also resumed: 57.45 s in S3 with the adapter authorised on boot -1,
and four two-second wakes with it attached on boot -2. **Attachment is not
sufficient to hang a resume**, and the old `tg3` / `dpm_resume_start()`
explanation cannot be checked against any journal this machine still has.

One lead for a future investigation, not a finding: boot -2's hang at 02:09:10
came after the Wi-Fi device had reached `phy20` (repeated registrations since
boot) and a burst of `brcmfmac ... Failed to reserve space ... err=-12`
immediately before `PM: suspend entry`.

### What is established

| # | claim | evidence |
|---|---|---|
| 1 | **A CIFS/NFS mount with unwritten data whose server is gone blocks the sleep.** `Filesystems sync` took **194.646 s** and **95.554 s** on 2026-10-20; the same operation took **0.014–0.031 s** once the share was unmounted before `suspend(2)`. | Both figures are in `journalctl -b -1` and can be re-read at any time. |
| 2 | **`/proc/acpi/wakeup` comes back from every boot with the internal keyboard/touchpad source (`SPIT`) disabled.** | Read `/proc/acpi/wakeup` after a cold boot; the daemon re-arms what `wake_devices` lists. |
| 3 | **The "instant wake" is an S3 residence of about two seconds; neither de-authorising the Thunderbolt endpoint nor unloading `brcmfmac` stops it.** | Boot -2: 23 of 24 real sleeps at 1.6–2.9 s. Boot -1 16:09: `authorized=0`, S3 2.466 s. Boot 0 23:06:19: both `brcmfmac` modules unloaded, `authorized=0`, S3 2.749 s. |

### On record, not re-verified

**`brcmfmac` could be loaded in a state that refuses to be suspended**, aborting
the transaction with `-EIO`. The runs that produced that are no longer in the
journal. The program unloads the module before sleep regardless, because a
module that is not loaded cannot refuse.

A loaded `brcmfmac` was the suspect for the two-second wake until 2026-10-20
23:06; that cycle woke with the module unloaded, so it is not a sufficient
cause. The wake source is not written to the journal. One candidate for this
model, the EC's GPE `0x4E`, was masked and the machine still woke at 2.47 s, so
it was not the source on that run. It has never been confirmed as a source on
any other, and the 23:06 cycle has no wakeup counter snapshot.

## Not worth re-testing

The list below was accumulated during the investigation. **Read it as "none of
these made the difference in the runs that were done", not as "ruled out"**:
those runs used console `loglevel=4`, which prints only `KERN_ERR`, while every
line that locates a fault is `KERN_INFO` — so the console records of them are
nearly empty by construction.

`d3cold_allowed=0`, CPU offline, `s2idle` versus `deep`, every wake-source
combination, and the EC's GPE `0x4E` as a source of spurious wakes. The VT/wakeup
handshake (`vt_waitactive()`, upstream bug 219716) was measured four times at
**17-21 ms**: real upstream race, never the blocker here.

**`brcmfmac` unload ordering is not on this list.** The earlier runs tried it
around the wrong problem and did not settle it; on 16:09 the reversed order
produced `Module brcmfmac is in use` and the two-second wake came back. The
listed order (`brcmfmac_wcc`, then `brcmfmac`) is load-bearing.

## Why the long history is not in this repository

On 2026-10-20 the operator had the documentation cut back to what describes the
project **now**. Removed: `docs/progress.md` (16,989 lines of test logs),
`docs/diagnosis.md`, `docs/diagnosis-ec-gpe4e.md` (retracted), `docs/root-cause-plan.md`,
`docs/investigation-state.md`, `docs/systemd-freeze-dropin.md`, the SMC/EC key
references, the ACPI dumps and reference attachments, and the instruments that
were written for the investigation (`hang-sampler`, `smc-dump`, `nvs-snap`,
`vt-ftrace`, `test-wedge` and the rest).

**Nothing was lost.** The pre-publication history is kept locally in the
`local-history` branch (the public history starts at 0.1.0). Every removed file
is readable from it:

```sh
git show local-history:docs/progress.md | less
git show local-history:docs/diagnosis.md
git log --oneline local-history -- docs/progress.md
```

## Where current state lives

| document | holds |
|---|---|
| `README.md` | behaviour, every switch, install and uninstall |
| `docs/config-changes.md` | every change made to the machine, with an undo |
| `macbook.conf` | the shipped defaults, fully commented |
| `git log` | what changed, when, and why |
