# AGENTS.md

Rules for agents (including future me) working in this repository.
**These are project rules, not style preferences.**

## What this project is

`mbp-sleep` is one daemon plus one sleep hook and one configuration file. It
makes a MacBookPro12,1 sleep when asked and wake when asked, with network shares
and a Thunderbolt Ethernet adapter attached, and it waits for a running backup
instead of killing it.

`README.md` says what it does and how to install it. `docs/background.md` says
why the code looks the way it does, and where the investigation that produced it
is stored. **Nothing else in the tree is required to work on it.**

A change belongs here if it keeps sleep and resume working on this machine, or
makes a failure diagnosable. A change that serves neither does not belong here.

## 0. Language: the whole repository is English

Code, comments, script output, log messages, `README.md`, `docs/**`,
`CHANGELOG.md`, `AGENTS.md` and commit messages are written in **English**. No
Chinese (or other non-English) text, including CJK or full-width punctuation.
The repository may be published, and its audience is not assumed to read Chinese.

Before committing, confirm this prints nothing:

```bash
git ls-files | xargs grep -lP '[\x{4e00}-\x{9fff}\x{3000}-\x{303f}\x{ff01}-\x{ff60}\x{ffe0}-\x{ffe6}]'
```

## 1. Root operations go through `pkexec`

Everything that needs root (systemd drop-ins, GRUB, module parameters) is done
through `pkexec`, so the user sees a **single graphical polkit password prompt**.

- Prefer `pkexec`; fall back to `sudo` only if `pkexec` is unavailable.
- For repeated diagnostics, `sudo -n` after one `sudo -v` is established
  practice: polkit's authentication backend on this machine *is* sudo, so one
  `sudo -v` covers both. **The sudo ticket lives 5 minutes** — no
  `timestamp_timeout` is configured. Say so when it has expired instead of
  letting a command fail.
- Scripts must be **idempotent** (safe to re-run) and must **back up** any file
  they replace.
- **Never batch a privileged operation and its announcement into one turn.**
  Anything that needs the operator's machine or attention is announced first, in
  its own message, and waited for.

## 2. Wayland only

This machine runs GNOME on **Wayland**. Never suggest an X11 workaround, an
`xinput`/`xset` command, or anything that needs an X session.

## 3. Hardware constraints — do not "fix" these

- **Do not disable Thunderbolt.** The operator relies on the Apple
  Thunderbolt→Gigabit Ethernet adapter (`ens9`, BCM57762). The program touches
  only the adapter's own endpoint, and only while the machine sleeps; the host
  controller `0-0` is out of bounds.
- **Do not restrict wake sources.** Keyboard, mouse and lid wake must keep
  working. `wake_devices` exists to *enable* sources, never to remove them.
- **Do not remove the systemd freeze drop-in.**
  `/etc/systemd/system/systemd-suspend.service.d/10-no-freeze.conf` sets
  `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false`. It is kept by **operator ruling**,
  not by evidence: it is a setting the operator wants, whether or not it helps.
  The historical "29% → 75%" figure was measured with the Ethernet adapter
  plugged in and is not trustworthy. `freeze_sessions = off` in the configuration
  is what installs it.

## 4. Real machine > docs > code inference

When they disagree, the real machine wins — then fix the docs and the comments.
A comment that states a guess as fact is worse than no comment: it stops the next
person from doubting.

- Verify behaviour with a measurement (`mbp-sleep status`, `/sys/power/*`,
  `journalctl`, `scripts/diagnose.sh`, `scripts/test-suspend.sh`), not by reading
  code.
- **Retract loudly and immediately when the evidence weakens.** A retraction in
  the same breath as the claim costs nothing; one two hours later costs the
  operator an afternoon.

## 5. Every change to the machine goes into `docs/config-changes.md`

That file is the append-only log of changes, one entry per change, each with
**what** (exactly enough to undo it), **where** it lives, **why**, and **whether
it worked**. `docs/background.md` explains why the older investigation documents
are no longer in the tree; `docs/config-changes.md` is deliberately kept, because
it is the only record of how to undo what is installed.

**A change you cannot undo is indistinguishable from damage.**

- **Write the undo before the change, not after.** By the time you discover a
  change cannot be reversed, the information needed to reverse it is gone.
- **Back up before overwriting, every time.** "I remember what it was" is not a
  backup.
- **Append only.** A wrong entry gets a retraction under it; it is never edited
  to read better.
- **`Worked` is a claim about a measurement.** An unexercised change reads
  `not yet tested`, never `yes`.
- A change that is reverted inside the same run still gets an entry, marked
  `reverted`. "It is gone now" is not discoverable by a reader six hours later.
- The test for a good entry: **hand it to someone who has not seen this session
  and let them restore the previous state from the entry alone.**

## 6. Confirm with the user before anything that needs them

Some actions are impossible to do, or impossible to undo, without the operator
physically acting. **Never start one without explicit consent first.** That
includes anything where they must act at a specific moment, must refrain from
acting, anything the agent cannot undo, anything that takes away or interrupts
the machine (reboot, suspend, a long freeze), and anything that spends a lot of
their time.

For this machine a sleep test can wedge the machine, so the announcement leads
with **absolute clock times**:

1. **The alarm time**, as a clock time — "the alarm fires at 23:17:28", never
   "+180 seconds".
2. **The deadline** — alarm plus 30 s, which is about three times the 8-9 s
   observed resume time. "If it is still black at 23:17:58, it is hung."
3. **What a working resume looks like**, so a slow resume can be told from a
   dead machine.
4. **How to recover** — hold the power button — and **how long it will take**.

**Consent is a reply that comes *after* the announcement, in a later message.**
None of these is consent: a timetable printed and then acted on; "ok"/"go" said
before the announcement or in reply to a different question; consent to an
earlier, identical run; the operator having said the work is important; silence.

Reading files, reading the journal, taking a snapshot, writing to the repository
and reporting results need no consent — do them and say what you found.

## 7. Look it up before you diagnose it

When something does not work, search before experimenting. The order is fixed:

1. **Official documentation** — upstream kernel `Documentation/`, `man`
   (`systemd-sleep`, `modinfo`, sysfs/procfs docs), the ACPI specification, the
   upstream source of the driver in question.
2. **The internet** — kernel bugzilla, mailing lists, the distro wiki, GitHub
   issues. Search the **exact model string** (`MacbookPro12,1`) as well as the
   symptom.
3. **Only then self-diagnosis** — bisecting, probe kernels, writing
   instrumentation. Last resort, not first move.

Most MacBook write-ups also say "blacklist thunderbolt". Rule 3 still applies.

## 8. Never build a wheel, and never claim a system cannot record something

**Check for prior art before writing an instrument** — a module, a script, a
dumper, a parser. If something exists and cannot be used here, say that
explicitly and why, rather than silently writing your own.

**Do not say "there is no way to log this" until you have read the
configuration.** That sentence has been wrong about `pstore`, about the EC, and
about suspend/resume — every time it was a configuration question. The sentence
required is "`<option>` is not enabled in `<component>`", naming both.

## 9. Verification before claiming success

A fix counts as done only after it has been exercised on the real machine.

- **Suspend:** `scripts/test-suspend.sh` (arms the RTC, suspends, checks resume
  and Wi-Fi). `mbp-sleep report --boot N` answers the four questions: did it
  sleep, where did it stop if not, was it a wake, and which source woke it.
- **A black screen is not a sleep.** systemd blanks the display before calling
  `suspend(2)`, so a hang anywhere in the suspend path looks identical to a
  successful sleep from the outside. "It slept" means the journal says so.
- **Hibernate is not supported** by this project and does not work on this
  hardware as configured. Do not claim it does.
- **An RTC-woken resume proves nothing about physical wake.** Test that with a
  human action, against the armed alarm.

## 10. Do not scatter artifacts

Diagnostic output and one-off scripts live in this repository. Do not leave the
project's working state in `/tmp`: it is cleared at reboot, and the project must
be reproducible from the repository alone.
