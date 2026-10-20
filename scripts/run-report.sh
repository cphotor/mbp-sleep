#!/bin/sh
# Answer the four questions every run must answer.
#
#   1. Did it sleep?
#   2. If not, why not -- where exactly did the kernel stop?
#   3. If it did sleep, was this a wake?
#   4. If it was a wake, which source?
#
# Questions 1-3 are answered from the kernel journal, which is now durable for
# the whole pre-freeze window because RateLimitIntervalSec is 100 ms.
# Question 4 is answered from /sys/class/wakeup/*/event_count, and only for the
# boot currently running -- those counters do not survive a reboot.
set -u
BOOT="${1:-0}"
TAG="${2:-?}"
DIR=/var/log/mbp-wedge

J="journalctl -b $BOOT -k -o short-monotonic --no-pager"

printf '================================================================\n'
printf '  RUN %s   (boot %s)\n' "$TAG" "$BOOT"
printf '================================================================\n'

n_entry=$($J 2>/dev/null | grep -c 'PM: suspend entry')
n_prep=$($J 2>/dev/null | grep -c 'Preparing to enter system sleep state S3')
n_low=$($J 2>/dev/null | grep -c 'Low-level resume complete')
n_wake=$($J 2>/dev/null | grep -c 'Waking up from system sleep state S3')
n_exit=$($J 2>/dev/null | grep -c 'PM: suspend exit')
n_sync=$($J 2>/dev/null | grep -c 'Filesystems sync')

echo "Q1. Did it sleep?"
if [ "$n_prep" -gt 0 ]; then
    echo "    YES. The kernel reached 'Preparing to enter system sleep state S3'."
elif [ "$n_entry" -gt 0 ]; then
    echo "    NO.  The kernel entered the suspend path but never reached S3."
else
    echo "    NO.  The kernel never logged 'PM: suspend entry' at all."
fi

echo
echo "Q2. If not, where exactly did it stop?"
if [ "$n_entry" -gt 0 ] && [ "$n_prep" -eq 0 ]; then
    if [ "$n_sync" -eq 0 ]; then
        echo "    Inside sync_filesystem() -- the first thing suspend does."
        echo "    Evidence: 'PM: suspend entry' is present, 'Filesystems sync' is not."
        echo "    That message is printed only AFTER sync_filesystem() returns."
        echo "    Nothing about devices was even attempted."
    else
        echo "    After sync_filesystem(), but before S3. Last line in the journal:"
        $J 2>/dev/null | awk '/PM: suspend entry/{f=1} f' | tail -3 | sed 's/^/      /'
    fi
else
    echo "    n/a -- it slept."
fi

echo
echo "Q3. If it slept, was this a wake?"
if [ "$n_low" -gt 0 ]; then
    echo "    YES. 'Low-level resume complete' is present -- the platform came back."
    if [ "$n_exit" -gt 0 ]; then
        echo "    And 'PM: suspend exit' is present, so the kernel finished resume too."
        echo "    Full suspend -> S3 -> resume cycle completed."
    else
        echo "    But 'PM: suspend exit' is ABSENT: the platform resumed and the kernel"
        echo "    did not finish the resume path."
    fi
else
    echo "    NO.  There is no 'Low-level resume complete' -- it never came back."
fi

echo
echo "Q4. If it was a wake, which source?"
if [ "$n_low" -gt 0 ]; then
    n=$(grep -c 'event_count' /sys/class/wakeup/*/event_count 2>/dev/null | wc -l)
    echo "    Recorded devices with a non-zero event_count:"
    awk 'NR>2 && $4>0 {printf "      %-14s %-10s event=%s active=%s\n", $1, $2, $4, $5}' \
        "$DIR/wakeup-$TAG.txt" 2>/dev/null || echo "      (no snapshot for this run)"
    echo "    Note: these counters are per-boot and are lost on reboot."
    echo "    Compare the pre and post snapshots to see which one moved."
else
    echo "    n/a -- there was no wake."
fi
