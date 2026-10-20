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

### Instant wake: measured, one device still standing

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
| 0 (10-20 16:53 →) | 4 | 17.63 s, 13.53 s, **297.62 s**, **573.42 s** |

What separates them:

- The Thunderbolt adapter was **absent** for most of boot -2's two-second wakes;
  it first appears at 23:44:45. It is not the cause of this symptom.
- At 16:09 the Thunderbolt endpoint was already `authorized=0` and the wake still
  came after **2.466 s**. De-authorising that endpoint does not stop it.
- That same cycle failed to unload `brcmfmac` (`Module brcmfmac is in use` — the
  ordering bug fixed at 16:48). Every cycle after the fix unloaded
  `brcmfmac_wcc` and `brcmfmac`, and slept **17.63 s, 13.53 s, 297.62 s and
  573.42 s**.

**Every two-second wake in the journal had `brcmfmac` loaded, and the four
cycles in which it actually unloaded did not have one.** That is a correlation,
not an attribution: two sleeps with it loaded also avoided the wake (57.45 s and
1851 s), so loaded is not sufficient, and the mechanism is not known. The two
longest cycles (297.62 s and 573.42 s) were ended by the operator; the machine
has not been left asleep unattended for hours.

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
| 3 | **The "instant wake" is an S3 residence of about two seconds, and de-authorising the Thunderbolt endpoint does not stop it.** | Boot -2: 23 of 24 real sleeps at 1.6–2.9 s. Boot -1 16:09: `authorized=0`, S3 2.466 s. The formula and the full table are above. |

### On record, not re-verified

**`brcmfmac` could be loaded in a state that refuses to be suspended**, aborting
the transaction with `-EIO`. The runs that produced that are no longer in the
journal. The program unloads the module before sleep regardless, because a
module that is not loaded cannot refuse.

A loaded `brcmfmac` is also the current suspect for the two-second wake (above),
but that is a correlation, not an attribution. The wake source is not written to
the journal; one candidate for this model, the EC's GPE `0x4E`, was masked and
the machine still woke at 2.47 s, so it was not the source on that run. It has
never been confirmed as a source on any other.

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
