#!/usr/bin/env python3
"""Regression test for the CIFS record: which shares get remounted after sleep.

Run it from anywhere; it needs no root and no network share:

    scripts/test-cifs-record.py

`mbp-sleep` is loaded as a module and three of its inputs are replaced --
`mount_table()`, `run()` and the path of the record -- so a whole
pre-suspend / post-resume cycle runs against a made-up mount table.  Nothing
outside a temporary directory is touched.

Each case is a scenario that has actually happened on this machine, except
that the exit codes were measured in the journal rather than produced here:

  * 2026-10-25 16:41 (C44): `umount /mnt/tmcap2` was killed at its 15 s timeout,
    rc=124, while the kernel had already dropped the mount.  The exit code was
    read as "still mounted", so the share never entered the record, was never
    remounted, and `post` announced "all shares are back".
  * the same moment: `umount /mnt/pastime` failed with rc=32 (target busy) and
    the share really was still mounted -- the opposite reading of the same
    signal.

The exit status is 0 when every case passes and 1 otherwise.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import subprocess
import sys
import tempfile
from pathlib import Path

PROGRAM = Path(__file__).resolve().parent.parent / "mbp-sleep"


def load_program():
    loader = importlib.machinery.SourceFileLoader("mbp_sleep", str(PROGRAM))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Machine:
    """A pretend mount table, and the commands `mbp-sleep` runs against it.

    `unmount` maps a mount point to what `umount path` does:

      "ok"    -- rc 0, the mount is gone
      "hang"  -- rc 124, the mount is gone as well (the kernel dropped it, the
                 command sat in the socket teardown until it was killed)
      "busy"  -- rc 32, the mount is still there

    `remount_ok` says whether `systemctl start` / `mount` put a share back.
    """

    def __init__(self, module, table, unmount=None, remount_ok=True):
        self.module = module
        self.table = dict(table)
        self.unmount = dict(unmount or {})
        self.remount_ok = remount_ok
        self.commands = []

    def mount_table(self):
        return dict(self.table)

    def run(self, argv, timeout=None):
        self.commands.append(list(argv))
        if argv[0] == "umount":
            path = argv[1]
            how = self.unmount.get(path, "ok")
            if how == "ok":
                self.table.pop(path, None)
                return subprocess.CompletedProcess(argv, 0, "", "")
            if how == "hang":
                self.table.pop(path, None)
                return subprocess.CompletedProcess(
                    argv, 124, "", f"timed out after {timeout}s")
            return subprocess.CompletedProcess(argv, 32, "", "target is busy")
        if argv[0] == "systemctl" and argv[1] == "start":
            path = self._path_of_unit(argv[2])
            return self._remount(argv, path)
        if argv[0] == "mount":
            return self._remount(argv, argv[1])
        return subprocess.CompletedProcess(argv, 127, "", "not simulated")

    def _remount(self, argv, path):
        if not self.remount_ok:
            return subprocess.CompletedProcess(argv, 1, "", "network is down")
        self.table[path] = "cifs"
        return subprocess.CompletedProcess(argv, 0, "", "")

    @staticmethod
    def _path_of_unit(unit):
        return "/" + unit[:-len(".mount")].replace("-", "/")


class Case:
    def __init__(self, name):
        self.name = name
        self.failures = []

    def check(self, what, actual, expected):
        if actual != expected:
            self.failures.append(f"{what}: expected {expected!r}, got {actual!r}")


def main() -> int:
    module = load_program()
    failures = 0
    results = []

    # 1. C44 itself: the kernel dropped tmcap2, `umount` was killed at 15 s.
    tmp = tempfile.TemporaryDirectory()
    module.NETWORK_UNMOUNTED = Path(tmp.name) / "network-unmounted"
    machine = Machine(module, {"/mnt/pastime": "cifs", "/mnt/tmcap2": "cifs"},
                      {"/mnt/tmcap2": "hang"})
    module.mount_table = machine.mount_table
    module.run = machine.run
    cfg = module.Config("/nonexistent/mbp-sleep.conf")
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        module.cifs_unmount(cfg)
        record_after_pre = module.cifs_remembered()
        pre_log = out.getvalue()
        module.cifs_mount(cfg)
        back = module.cifs_reconnected(cfg)
        post_log = out.getvalue()[len(pre_log):]
    case = Case("umount cut off at the timeout, mount already gone (C44)")
    case.check("record after pre", record_after_pre,
               ["/mnt/pastime", "/mnt/tmcap2"])
    case.check("pre says the exit code was wrong",
               "although umount exited 124" in pre_log, True)
    case.check("tmcap2 was remounted",
               any(c[:2] == ["systemctl", "start"] and "tmcap2" in c[2]
                   for c in machine.commands), True)
    case.check("post reports the shares it checked",
               "all shares are back (/mnt/pastime, /mnt/tmcap2)" in post_log, True)
    case.check("post is satisfied", back, True)
    case.check("record cleared", module.cifs_remembered(), [])
    results.append((case, pre_log + post_log))

    # 2. The other reading of the same signal: rc=32 and still mounted.
    tmp2 = tempfile.TemporaryDirectory()
    module.NETWORK_UNMOUNTED = Path(tmp2.name) / "network-unmounted"
    machine2 = Machine(module, {"/mnt/pastime": "cifs", "/mnt/tmcap2": "cifs"},
                       {"/mnt/tmcap2": "busy"})
    module.mount_table = machine2.mount_table
    module.run = machine2.run
    cfg2 = module.Config("/nonexistent/mbp-sleep.conf")
    out2 = io.StringIO()
    with contextlib.redirect_stdout(out2):
        module.cifs_unmount(cfg2)
        module.cifs_mount(cfg2)
        back2 = module.cifs_reconnected(cfg2)
    case2 = Case("umount busy: the share really is still mounted")
    case2.check("record", module.cifs_remembered(), [])
    case2.check("satisfied without touching tmcap2", back2, True)
    case2.check("no second attempt at tmcap2",
                any(c[0] == "umount" and c[1] == "/mnt/tmcap2"
                    for c in machine2.commands), True)
    results.append((case2, out2.getvalue()))

    # 3. A share left in the record by a failed reconnect survives the next pre.
    tmp3 = tempfile.TemporaryDirectory()
    module.NETWORK_UNMOUNTED = Path(tmp3.name) / "network-unmounted"
    module.cifs_remember(["/mnt/tmcap2"])
    machine3 = Machine(module, {"/mnt/pastime": "cifs"})
    module.mount_table = machine3.mount_table
    module.run = machine3.run
    cfg3 = module.Config("/nonexistent/mbp-sleep.conf")
    out3 = io.StringIO()
    with contextlib.redirect_stdout(out3):
        module.cifs_unmount(cfg3)
    case3 = Case("a share that is down is not dropped by the next pre")
    case3.check("record", module.cifs_remembered(),
                ["/mnt/tmcap2", "/mnt/pastime"])
    results.append((case3, out3.getvalue()))

    # 4. cifs_auto = off: a share removed from the configuration stops being owed.
    tmp4 = tempfile.TemporaryDirectory()
    module.NETWORK_UNMOUNTED = Path(tmp4.name) / "network-unmounted"
    module.cifs_remember(["/mnt/tmcap2", "/mnt/pastime"])
    machine4 = Machine(module, {"/mnt/pastime": "cifs"})
    module.mount_table = machine4.mount_table
    module.run = machine4.run
    cfg4 = module.Config("/nonexistent/mbp-sleep.conf")
    cfg4["cifs_auto"] = "off"
    cfg4["cifs_shares"] = "pastime"
    out4 = io.StringIO()
    with contextlib.redirect_stdout(out4):
        module.cifs_unmount(cfg4)
    case4 = Case("cifs_auto=off: a share dropped from the config is not owed")
    case4.check("record", module.cifs_remembered(), ["/mnt/pastime"])
    results.append((case4, out4.getvalue()))

    # 5. Nothing mounted, nothing recorded: say so instead of "all shares".
    tmp5 = tempfile.TemporaryDirectory()
    module.NETWORK_UNMOUNTED = Path(tmp5.name) / "network-unmounted"
    machine5 = Machine(module, {})
    module.mount_table = machine5.mount_table
    module.run = machine5.run
    cfg5 = module.Config("/nonexistent/mbp-sleep.conf")
    out5 = io.StringIO()
    with contextlib.redirect_stdout(out5):
        back5 = module.cifs_reconnected(cfg5)
    case5 = Case("no shares at all")
    case5.check("satisfied", back5, True)
    case5.check("message", "no network shares to restore" in out5.getvalue(), True)
    results.append((case5, out5.getvalue()))

    # 6. Giving up names the shares that are still down.
    tmp6 = tempfile.TemporaryDirectory()
    module.NETWORK_UNMOUNTED = Path(tmp6.name) / "network-unmounted"
    module.cifs_remember(["/mnt/tmcap2"])
    machine6 = Machine(module, {}, remount_ok=False)
    module.mount_table = machine6.mount_table
    module.run = machine6.run
    cfg6 = module.Config("/nonexistent/mbp-sleep.conf")
    cfg6["cifs_reconnect_wait"] = "0"
    out6 = io.StringIO()
    with contextlib.redirect_stdout(out6):
        module.cifs_reconnect(cfg6)
    case6 = Case("giving up names what is still down")
    case6.check("message", "still down: /mnt/tmcap2" in out6.getvalue(), True)
    case6.check("record kept for the next sleep", module.cifs_remembered(),
                ["/mnt/tmcap2"])
    results.append((case6, out6.getvalue()))

    for case, log in results:
        status = "ok  " if not case.failures else "FAIL"
        print(f"{status} {case.name}")
        for line in log.strip().splitlines():
            print(f"       | {line}")
        for failure in case.failures:
            print(f"       ! {failure}")
        failures += bool(case.failures)

    print()
    print(f"{len(results) - failures}/{len(results)} cases passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
