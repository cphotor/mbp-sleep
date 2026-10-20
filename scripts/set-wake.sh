#!/usr/bin/env bash
#
# set-wake.sh - set ACPI wake sources explicitly and verify the result.
#
# WHY
# ---
# Writing a device name to /proc/acpi/wakeup TOGGLES it. It does not set it.
# Every "just echo XHC1" instruction on the internet, including the one in the
# AUR package, therefore re-enables what it just disabled if run twice, and
# leaves state that depends on boot order. This script reads the current state
# and only writes when a change is actually needed, then reads back and prints
# what it actually got.
#
# USAGE
#   scripts/set-wake.sh on  XHC1 SPIT
#   scripts/set-wake.sh off XHC1 SPIT
#   scripts/set-wake.sh show
#
# Run it as root, or let it re-exec through pkexec/sudo.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  if   command -v pkexec >/dev/null 2>&1; then exec pkexec "$REPO_DIR/scripts/set-wake.sh" "$@"
  elif command -v sudo   >/dev/null 2>&1; then exec sudo   "$REPO_DIR/scripts/set-wake.sh" "$@"
  else printf 'Needs root to write /proc/acpi/wakeup.\n' >&2; exit 1
  fi
fi

state() { awk -v d="$1" '$1 == d { print $3 }' /proc/acpi/wakeup 2>/dev/null || true; }

show() {
  printf '  %-6s %-3s %s\n' "DEV" "S" "STATUS"
  awk 'NR>1 { printf "  %-6s %-3s %s\n", $1, $2, $3 }' /proc/acpi/wakeup
}

case "${1:-show}" in
  show)
    show
    ;;
  on|off)
    # /proc/acpi/wakeup spells the states "enabled"/"disabled", not on/off.
    case "$1" in on) want=enabled ;; off) want=disabled ;; esac
    shift
    [ "$#" -gt 0 ] || { printf 'Usage: %s {on|off} DEV...\n' "$0" >&2; exit 2; }
    for dev in "$@"; do
      st="$(state "$dev")"
      if [ -z "$st" ]; then
        printf 'warning: %s is not present in /proc/acpi/wakeup\n' "$dev" >&2
        continue
      fi
      # *enabled / *disabled -> enabled / disabled
      cur="${st#\*}"
      if [ "$cur" = "$want" ]; then
        printf '  %-6s already %s\n' "$dev" "$cur"
        continue
      fi
      echo "$dev" > /proc/acpi/wakeup
      got="$(state "$dev")"; got="${got#\*}"
      if [ "$got" = "$want" ]; then
        printf '  %-6s %s -> %s\n' "$dev" "$cur" "$got"
      else
        printf '  %-6s FAILED: wanted %s, got %s\n' "$dev" "$want" "$got" >&2
      fi
    done
    echo
    show
    ;;
  -h|--help|'') sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) printf 'Usage: %s {on|off|show} [DEV...]\n' "$0" >&2; exit 2 ;;
esac
