# Background — what was wrong, what fixed it, and where the rest went

`README.md` describes what the program is and how to use it. This page is the
minimum needed to understand the code: the machine, the three faults that were
measured, and why the investigation that produced them is no longer in the tree.

## The machine

MacBookPro12,1 (2015 13" MacBook Pro), EndeavourOS, kernel 7.2.x, GNOME on
Wayland, S3 (`deep`). The internal Apple/Samsung SSD is both root and swap. The
operator's Thunderbolt-to-Gigabit-Ethernet adapter (`ens9`, `tg3`) is expected to
stay plugged in.

## What failed, and what is actually established

The rule for this page: **only the first row is backed by measurements that are
still in this machine's journal.** The rest is the history of a hypothesis, kept
because it explains why the program detaches devices — not because it has been
proved.

| # | what was observed | status of the explanation |
|---|---|---|
| 1 | **A CIFS/NFS mount with unwritten data whose server is gone blocks the sleep.** `Filesystems sync` took **194.646 s** and **95.554 s** on 2026-10-20; the same operation took **0.014–0.031 s** once the share was unmounted before `suspend(2)`. | **Established.** Both figures are in `journalctl -b -1` and can be re-read at any time. |
| 2 | **`brcmfmac` could be loaded in a state that refuses to be suspended**, aborting the transaction with `-EIO`. | **On record, not re-verified.** The runs that produced it are no longer in the journal. The program unloads the module before sleep regardless, because a module that is not loaded cannot refuse. |
| 3 | **With the Thunderbolt Ethernet adapter attached across sleep, resumes did not complete**; with it off the bus before sleep, they did. | Observable part: **on record**. The resume-path explanation once given (`tg3` stalling `dpm_resume_start()`, `thaw_processes()` never running) **cannot be checked against any journal this machine still has** and should be treated as a hypothesis. What the program relies on is the observable: take the endpoint off the bus before sleep. |

Firmware detail that the program compensates for: `/proc/acpi/wakeup` is rebuilt
at every boot and comes back with `SPIT` (the internal keyboard/touchpad path)
**disabled**. The daemon re-arms the configured wake sources at start.

## Not worth re-testing

The list below was accumulated during the investigation. **Read it as "none of
these helped while something else was broken", not as "ruled out"**: every one of
these experiments ran with the Ethernet adapter plugged in — that is, with fault
3 present — and with console `loglevel=4`, which prints only `KERN_ERR` while
every line that locates a fault is `KERN_INFO`.

`d3cold_allowed=0`, CPU offline, `s2idle` versus `deep`, every wake-source
combination, `brcmfmac` unload ordering around *suspend*, and the EC's GPE `0x4E`
as a source of spurious wakes. The VT/wakeup handshake (`vt_waitactive()`,
upstream bug 219716) was measured four times at **17-21 ms**: real upstream race,
never the blocker here.

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
