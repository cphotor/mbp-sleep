#!/bin/sh
# wait-for-share.sh -- wait until a network share is mounted again after resume.
#
# Why this exists.
# Vorta starts a missed backup as soon as logind announces the resume, which is
# about 3 s after the machine wakes.  mbp-sleep unmounts the CIFS shares before
# sleep and remounts them from a transient unit, which cannot succeed until
# NetworkManager comes back -- and NetworkManager is only told to come back
# after the sleep hook returns.  On 2026-11-11 23:40:28 the machine resumed,
# Vorta checked at 23:40:31, the share came back at 23:40:41, and Vorta aborted
# with "Conditions for backup not met" / "Repo folder not mounted or moved."
# and delivered an error notification.  It then paused for 10 minutes and the
# backup ran at 23:50.
#
# This is meant to be Vorta's `pre_backup_cmd` for that profile.  Vorta runs it
# before it checks that the repository path exists (vorta/borg/create.py:141
# before :145), so waiting here turns the race into a short delay instead of a
# failed backup plus a notification.  It is deliberately *not* a sleep hook:
# hooks run inside the sleep transaction, and waiting there was rejected
# because it delays the resume of every user on the machine (C4, C40 in
# docs/config-changes.md).
#
# Usage: wait-for-share.sh [path] [seconds]
# Exit 0 as soon as <path> is a CIFS/SMB mount, 1 after <seconds> (default 60).

path=${1:-/mnt/tmcap2}
limit=${2:-60}
deadline=$(( $(date +%s) + limit ))

while :; do
    fstype=$(findmnt -n -o FSTYPE --target "$path" 2>/dev/null)
    case "$fstype" in
        cifs|smb3|smbfs) exit 0 ;;
    esac
    [ "$(date +%s)" -ge "$deadline" ] && exit 1
    sleep 1
done
