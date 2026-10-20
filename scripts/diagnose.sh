#!/usr/bin/env bash
#
# mbp-sleep diagnostic report
#
# Read-only. Prints the suspend/hibernate-related state of this machine so a
# problem can be diagnosed without guessing. Save it and attach it to a report:
#
#   scripts/diagnose.sh | tee diagnose-$(date +%F).txt
#
# Some fields (e.g. /sys/power/disk, sleep history) are more complete when run
# as root, but the script does not require it.

set -uo pipefail

section() { printf '\n===== %s =====\n' "$*"; }
show() {
  # show <label> <command...>
  local label="$1" out
  shift
  out="$("$@" 2>&1 || true)"
  printf '%-34s %s\n' "$label" "$out"
}

section "System"
show "kernel"       uname -r
show "distro"       sh -c '. /etc/os-release && printf "%s %s\n" "$NAME" "$VERSION_ID"'
show "session"      sh -c 'printf "XDG_SESSION_TYPE=%s DESKTOP=%s\n" "${XDG_SESSION_TYPE:-?}" "${XDG_CURRENT_DESKTOP:-?}"'
show "systemd"      systemctl --version
show "product"      cat /sys/class/dmi/id/product_name

section "Power state"
show "/sys/power/state"   cat /sys/power/state
show "/sys/power/mem_sleep" cat /sys/power/mem_sleep
show "/sys/power/disk"    cat /sys/power/disk
show "mem_sleep_default"  sh -c 'grep -ho "mem_sleep_default=[a-z0-9]*" /proc/cmdline /etc/default/grub 2>/dev/null | sort -u'

section "Swap / resume"
show "/proc/swaps"  cat /proc/swaps
show "swap devices" sh -c 'for d in $(awk "NR>1{print \$1}" /proc/swaps); do printf "%s " "$d"; blkid -s UUID -o value "$d" 2>/dev/null; done'
show "resume= (cmdline)"  sh -c 'tr " " "\n" < /proc/cmdline | grep "^resume=" || echo "(none)"'
show "resume= (grub)"     sh -c 'grep -oE "resume=UUID=[a-fA-F0-9-]+" /etc/default/grub 2>/dev/null | sort -u || echo "(none)"'
show "initramfs resume"   sh -c 'if command -v lsinitcpio >/dev/null 2>&1 && lsinitcpio /boot/initramfs-linux.img >/dev/null 2>&1; then lsinitcpio /boot/initramfs-linux.img | grep -E "systemd-hibernate-resume|bin/resume" | head -3; else echo "(needs root; the systemd hook ships systemd-hibernate-resume + generator)"; fi'

section "Configured systemd settings (highest precedence)"
# cat-config prints the main file first, then drop-ins in order; the LAST
# occurrence of a key is the effective one.
sleep_eff() { systemd-analyze cat-config systemd/sleep.conf 2>/dev/null | grep -iE "^\s*$1=" | tail -1 || true; }
logind_eff() { systemd-analyze cat-config systemd/logind.conf 2>/dev/null | grep -iE "^\s*$1=" | tail -1 || true; }
for k in AllowSuspend AllowHibernation MemorySleepMode; do
  show "$k" sleep_eff "$k"
done
for k in HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked HandleSuspendKey HandleHibernateKey; do
  show "$k" logind_eff "$k"
done

section "Running logind values (need a reboot to match the above)"
show "logind" sh -c 'busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
  HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked HandleSuspendKey HandleHibernateKey 2>/dev/null \
  || echo "(busctl unavailable)"'

section "Hibernate units"
for unit in hibernate.target hybrid-sleep.target suspend-then-hibernate.target \
            systemd-hibernate.service systemd-suspend-then-hibernate.service; do
  show "$unit" systemctl is-enabled "$unit"
done

section "Sleep hook"
show "hook file"   sh -c 'ls -l /usr/lib/systemd/system-sleep/ 2>&1'
show "etc dir"     sh -c 'ls -l /etc/systemd/system-sleep/ 2>&1 || echo "(does not exist; this systemd reads /usr/lib/...)"'

section "Wi-Fi / brcmfmac"
show "module state"   sh -c 'lsmod | grep -E "^brcmfmac|^brcmutil|^cfg80211" || echo "(brcmfmac not loaded)"'
show "fw version"     sh -c 'v="$(dmesg 2>/dev/null | grep -i "brcmfmac.*version" | tail -1)"; [ -n "$v" ] || v="$(journalctl -k -b 2>/dev/null | grep -i "brcmfmac.*version" | tail -1)"; printf "%s\n" "$v"'
show "wlan link"      sh -c 'iw dev 2>/dev/null | grep -E "Interface|ssid" || nmcli -t -f DEVICE,STATE,CONNECTION dev status 2>/dev/null'

section "Wake sources"
show "/proc/acpi/wakeup" sh -c 'grep -E "enabled" /proc/acpi/wakeup || cat /proc/acpi/wakeup'

section "Recent suspend/resume history"
show "history" sh -c 'journalctl -b -o short-iso --no-pager 2>/dev/null | grep -iE "PM: suspend|PM: hibernate|System returned from sleep|Performing sleep operation|Reached target (Sleep|Hibernate)|brcmfmac:|brcmf_pcie" | tail -40 || echo "(no journal access; try as root)"'

section "Hook log"
show "50-brcmfmac" sh -c 'journalctl -b -t 50-brcmfmac --no-pager 2>/dev/null | tail -20 || echo "(none this boot)"'

printf '\n'
