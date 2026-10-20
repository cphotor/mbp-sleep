#!/usr/bin/env bash
#
# mbp-sleep suspend test
#
# Arms the RTC to wake after N seconds, then suspends. On resume it prints a
# short report (timing, Wi-Fi, hook log) so the result is unambiguous.
#
# Usage:
#   scripts/test-suspend.sh [SECONDS]     default: 30
#
# WARNING: this machine has hung on resume before. If the machine does not come
# back within ~2x SECONDS, hold the power button to force a reboot. Save your
# work first.
#
# NOTE: this script only tests an RTC-woken resume. It says nothing about
# physical wake. To test a human wake source, suspend by hand and check the
# resume time against the armed alarm.
#
# Do not run this repeatedly in quick succession: back-to-back suspends keep the
# PCH hot and intel_pch_thermal warns that "S0ix might fail". Let the machine
# cool between tests.
#
# rtcwake needs root; the script elevates itself through pkexec once.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SECS="${1:-30}"

case "$SECS" in
  ''|*[!0-9]*) printf 'Usage: %s [SECONDS]\n' "${BASH_SOURCE[0]}" >&2; exit 2 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  if   command -v pkexec >/dev/null 2>&1; then exec pkexec "$REPO_DIR/scripts/test-suspend.sh" "$SECS"
  elif command -v sudo   >/dev/null 2>&1; then exec sudo   "$REPO_DIR/scripts/test-suspend.sh" "$SECS"
  else
    printf 'This test needs root (rtcwake), but neither pkexec nor sudo is available.\n' >&2
    exit 1
  fi
fi

command -v rtcwake >/dev/null 2>&1 || { printf 'rtcwake not found (install util-linux).\n' >&2; exit 1; }

# Epoch seconds of the first/second matching kernel line since $1.
journal_epoch() {
  journalctl -b -k --since "@$1" -o short-unix --no-pager 2>/dev/null \
    | grep -E "$2" | head -1 | awk '{ print int($1) }' || true
}

wake=$(( $(date +%s) + SECS ))

printf 'This machine has hung on resume before. If it does not come back within\n'
printf 'about %d seconds, hold the power button. Save your work now.\n' "$((SECS * 2))"
printf 'Do not run this repeatedly: back-to-back suspends keep the PCH hot.\n\n'
printf 'Arming the RTC to wake at %s (in %d s), then suspending...\n' \
  "$(date -d "@$wake" '+%F %T')" "$SECS"

rtcwake -m no -t "$wake"
t0="$(date +%s)"
systemctl suspend

# `systemctl suspend` returns *before* the kernel actually freezes (the suspend
# is asynchronous). Wait until the kernel logs "PM: suspend exit" at or after
# t0, which is the real point of resume. The process is frozen across the
# suspend, so this loop simply continues on the other side.
deadline=$(( t0 + SECS + 60 ))
entered=0
while :; do
  entry_ts="$(journal_epoch "$t0" 'PM: suspend entry')"
  exit_ts="$(journal_epoch "$t0" 'PM: suspend exit')"
  if [ -n "${entry_ts:-}" ]; then entered=1; fi
  if [ -n "${exit_ts:-}" ]; then break; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf '\nSuspend did not complete within %d s (entry seen: %s).\n' \
      "$((deadline - t0))" "$([ "$entered" -eq 1 ] && echo yes || echo no)"
    printf 'Check `systemd-inhibit --list` for a blocking inhibitor.\n'
    exit 1
  fi
  sleep 1
done

# ---- Reached only after a real resume ----
if [ -n "${entry_ts:-}" ]; then
  printf '\nSlept %d s (%s -> %s).\n' "$((exit_ts - entry_ts))" \
    "$(date -d "@$entry_ts" '+%F %T')" "$(date -d "@$exit_ts" '+%F %T')"
else
  printf '\nResumed at %s (entry timestamp unavailable).\n' "$(date '+%F %T')"
fi

printf '\n--- Wi-Fi ---\n'
# The brcmfmac reload and NetworkManager's re-activation take a few seconds
# after resume, so wait briefly for Wi-Fi to come back before reporting.
if command -v nmcli >/dev/null 2>&1; then
  for _ in $(seq 1 30); do
    if nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | grep -q ':wifi:connected'; then
      break
    fi
    sleep 1
  done
  nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status 2>&1 || true
else
  iw dev 2>&1 | grep -E 'Interface|ssid' || true
fi

printf '\n--- brcmfmac hook log (this suspend) ---\n'
journalctl -b -t 50-brcmfmac --no-pager 2>/dev/null | tail -10 || printf '(no hook log)\n'

printf '\n--- kernel sleep messages ---\n'
journalctl -b -k --no-pager 2>/dev/null \
  | grep -iE 'PM: suspend|PM: hibernate|brcmf' | tail -20 || true

printf '\nIf Wi-Fi came back connected and the hook log shows modprobe rc=0, the\n'
printf 'suspend path is healthy. For hibernation, reboot first (the GRUB resume=\n'
printf 'parameter only applies to a fresh boot), then run: systemctl hibernate\n'
