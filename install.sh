#!/bin/bash
# install.sh -- install mbp-sleep on this machine.
#
# Idempotent: running it twice changes nothing the second time.  Every file it
# replaces is copied to /var/backups/mbp-sleep/<timestamp>/ first, and
# uninstall.sh knows how to put them back.
#
# It also removes the pieces of the previous design that this program replaces,
# so the machine ends up with one service and one hook, not five of each.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HERE}/macbook.conf"
PROGRAM="${HERE}/mbp-sleep"
SOURCE_VERSION="$(cat "${HERE}/VERSION" 2>/dev/null || echo unknown)"

BIN="/usr/local/sbin/mbp-sleep"
CONF="/etc/mbp-sleep.conf"
VERSION_FILE="/usr/local/share/mbp-sleep/VERSION"
UNIT="/etc/systemd/system/mbp-sleep.service"
HOOK="/usr/lib/systemd/system-sleep/50-mbp-sleep"
SLEEP_DROPIN="/etc/systemd/system/systemd-suspend.service.d/10-no-freeze.conf"
LID_DROPIN="/etc/systemd/logind.conf.d/50-mbp-sleep.conf"
RULES_DIR="/etc/polkit-1/rules.d"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/var/backups/mbp-sleep/${STAMP}"

info() { printf '  %s\n' "$*"; }
fail() { printf '\n  FAILED: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || { command -v pkexec >/dev/null && exec pkexec "$0" "$@"; }

[[ -r "$CONFIG" ]] || fail "macbook.conf not found next to install.sh"
[[ -r "$PROGRAM" ]] || fail "mbp-sleep not found next to install.sh"

conf_get() {
	# read one key from the configuration the installer is about to copy
	local file="$1" key="$2" default="$3"
	[[ -r "$file" ]] || { echo "$default"; return; }
	local value
	value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\([^#]*\).*/\1/p" "$file" | tail -1 | sed 's/[[:space:]]*$//')"
	echo "${value:-$default}"
}

# The configuration in force is the installed one if it exists, so a re-run
# honours whatever the operator has since edited.
EFFECTIVE_CONF="$CONF"
[[ -r "$CONF" ]] || EFFECTIVE_CONF="$CONFIG"

mkdir -p "$BACKUP"
: >"${BACKUP}/manifest.tsv"

# polkitd only watches rules directories that exist when it starts, so the
# directory has to be there before the daemon drops a rule into it (measured
# 2026-10-20: the rule was invisible until polkitd was reloaded).
install -d -m 0755 "$RULES_DIR"
save() {
	local target="$1"
	[[ -e "$target" || -L "$target" ]] || return 0
	cp -a "$target" "${BACKUP}/$(basename "$target")" || return 0
	# The manifest is what lets uninstall.sh put the file back where it was
	# without having to guess.
	printf '%s\t%s\n' "$target" "$(basename "$target")" >>"${BACKUP}/manifest.tsv"
	info "backed up $target"
}

echo
echo "mbp-sleep installer ${SOURCE_VERSION}"
echo "-------------------"
echo

# ---------------------------------------------------------------------------
# 1. the program and its configuration
# ---------------------------------------------------------------------------
save "$BIN"
install -D -m 0755 "$PROGRAM" "$BIN" || fail "cannot install $BIN"
info "installed $BIN"
save "$VERSION_FILE"
install -D -m 0644 "$HERE/VERSION" "$VERSION_FILE" || fail "cannot install $VERSION_FILE"
info "installed $VERSION_FILE ($SOURCE_VERSION)"

if [[ -r "$CONF" ]]; then
	info "kept the existing $CONF (not overwritten)"
	# A switch added to macbook.conf after this file was installed exists only
	# as a compiled-in default until someone adds it by hand.  Say so: a
	# setting the operator cannot find is a setting that does not exist.
	missing="$(comm -23 \
		<(grep -oE '^[a-z_]+' "$CONFIG" | sort -u) \
		<(grep -oE '^[a-z_]+' "$CONF" | sort -u) | tr '\n' ' ')"
	if [[ -n "${missing// /}" ]]; then
		info "these switches are NEW and not in $CONF yet (defaults apply):"
		info "  $missing"
	fi
else
	install -D -m 0644 "$CONFIG" "$CONF" || fail "cannot install $CONF"
	info "installed $CONF"
fi

# ---------------------------------------------------------------------------
# 2. the service
# ---------------------------------------------------------------------------
save "$UNIT"
cat >"$UNIT" <<'UNIT_EOF'
[Unit]
Description=mbp-sleep -- wake sources, lid, and backup-aware suspend deferral
Documentation=man:systemd-suspend.service(8)
After=local-fs.target
Before=sleep.target
ConditionPathExists=/usr/local/sbin/mbp-sleep

[Service]
Type=simple
ExecStart=/usr/local/sbin/mbp-sleep daemon
Restart=always
RestartSec=2
# A machine that is awake because this failed is better than a machine that
# slept through a backup, so it always comes back.
[Install]
WantedBy=multi-user.target
UNIT_EOF
info "installed $UNIT"

# ---------------------------------------------------------------------------
# 3. the sleep hook (a two-line shim into the same program)
# ---------------------------------------------------------------------------
save "$HOOK"
install -D -m 0755 /dev/stdin "$HOOK" <<'HOOK_EOF'
#!/bin/sh
# 50-mbp-sleep -- hands the systemd-sleep phase to mbp-sleep.
#
# This systemd reads only /usr/lib/systemd/system-sleep/ (AGENTS.md rule 5.4).
# The hook never fails: a sleep that cannot be prepared is still better than a
# machine that refuses to sleep.
/usr/local/sbin/mbp-sleep "$1" || true
exit 0
HOOK_EOF
info "installed $HOOK"

# ---------------------------------------------------------------------------
# 4. the two drop-ins
# ---------------------------------------------------------------------------
FREEZE="$(conf_get "$EFFECTIVE_CONF" freeze_sessions off)"
if [[ "$FREEZE" == "off" ]]; then
	if grep -qs '^Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false' "$SLEEP_DROPIN"; then
		# Already there, and it may carry the operator's own annotations.
		# Rewriting it would only lose them.
		info "kept the existing $SLEEP_DROPIN"
	else
		save "$SLEEP_DROPIN"
		install -D -m 0644 /dev/stdin "$SLEEP_DROPIN" <<'DP_EOF'
# Installed by mbp-sleep's install.sh.
# Long-term operator setting: do not freeze user sessions before the sleep target.
# See docs/config-changes.md C1 and AGENTS.md rule 5.1.
[Service]
Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
DP_EOF
		info "installed $SLEEP_DROPIN"
	fi
else
	info "freeze_sessions=on, no freeze drop-in"
fi

LID="$(conf_get "$EFFECTIVE_CONF" lid_watch on)"
if [[ "$LID" == "on" ]]; then
	save "$LID_DROPIN"
	install -D -m 0644 /dev/stdin "$LID_DROPIN" <<'DP_EOF'
# Installed by mbp-sleep's install.sh.
# mbp-sleep.service owns the lid switch: it suspends on close, unless a backup
# is running, in which case it waits and suspends when the backup ends.
# Removing this file restores logind's own HandleLidSwitch=suspend.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
DP_EOF
	info "installed $LID_DROPIN"
	# Writing the file is not enough: logind reads its configuration once at
	# start and on SIGHUP.  Without this the drop-in sits on disk looking
	# correct while logind still suspends on the lid itself.
	systemctl kill -s HUP systemd-logind 2>/dev/null \
		&& info "logind reloaded" \
		|| info "logind could not be reloaded; it will apply after a reboot"
else
	info "lid_watch=off, logind keeps the lid switch"
fi

# ---------------------------------------------------------------------------
# 5. remove what this program replaces
# ---------------------------------------------------------------------------
echo
info "removing the pieces of the previous design"
for unit in brcmfmac-resume-recover.service mbp-wakeup.service; do
	if [[ -e "/etc/systemd/system/$unit" ]]; then
		systemctl disable --now "$unit" >/dev/null 2>&1
		save "/etc/systemd/system/$unit"
		rm -f "/etc/systemd/system/$unit"
		find /etc/systemd/system -type l -name "$unit" -delete 2>/dev/null
		info "removed $unit"
	fi
done
if [[ -e /usr/local/bin/brcmfmac-resume-recover ]]; then
	save /usr/local/bin/brcmfmac-resume-recover
	rm -f /usr/local/bin/brcmfmac-resume-recover
	info "removed /usr/local/bin/brcmfmac-resume-recover"
fi
for old in /usr/lib/systemd/system-sleep/*; do
	[[ -e "$old" ]] || continue
	[[ "$old" == "$HOOK" ]] && continue
	save "$old"
	rm -f "$old"
	info "removed old hook $(basename "$old")"
done

# ---------------------------------------------------------------------------
# 6. start it
# ---------------------------------------------------------------------------
echo
systemctl daemon-reload || fail "daemon-reload failed"
systemctl enable mbp-sleep.service >/dev/null 2>&1
# restart, not just enable --now: a re-run with a new mbp-sleep must replace the
# daemon that is already holding the old code in memory.
systemctl restart mbp-sleep.service || fail "mbp-sleep.service did not start"
sleep 1

# ---------------------------------------------------------------------------
# 7. verify
# ---------------------------------------------------------------------------
echo "verification"
info "version        : $("$BIN" --version 2>/dev/null)"
info "service        : $(systemctl is-active mbp-sleep.service 2>/dev/null) / $(systemctl is-enabled mbp-sleep.service 2>/dev/null)"
info "hook           : $(ls /usr/lib/systemd/system-sleep/ | tr '\n' ' ')"
info "freeze drop-in : $([[ -e $SLEEP_DROPIN ]] && echo present || echo absent)"
info "lid drop-in    : $([[ -e $LID_DROPIN ]] && echo present || echo absent)"
info "wake sources   : $(grep -E '^SPIT' /proc/acpi/wakeup | awk '{print $1" "$3}')"
echo
"$BIN" status
echo
echo "backups of anything replaced: $BACKUP"
echo
echo "The service reads $CONF.  Change a switch there and run:"
echo "  systemctl restart mbp-sleep.service"
echo
