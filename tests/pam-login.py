#!/usr/bin/env python3
"""Run as root in a disposable Linux system with PAM and a test account.

Install pam.d/axon, then run:
  python3 tests/pam-login.py ACCOUNT TEST_PASSWORD EXPECTED_UID
The test account must have a POSIX login shell and a valid home directory.
"""

import errno
import os
import pty
import select
import sys
import time

USER, PASSWORD, UID = sys.argv[1:]
HELPER = os.path.abspath(os.path.join(os.path.dirname(__file__), "../libexec/axon-pam"))


def attempt(user, password, expected_status, command=None):
    pid, fd = pty.fork()
    if pid == 0:
        # Keep a greeter-like foreground parent while the helper runs.
        import subprocess
        result = subprocess.run([sys.executable, "-I", HELPER, user, "tty"])
        print("AXON_FOREGROUND_RESTORED", os.tcgetpgrp(0) == os.getpgrp(), flush=True)
        os._exit(result.returncode)
    output = bytearray()
    prompted = False
    reaped = False
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if not select.select([fd], [], [], 0.1)[0]:
                continue
            try:
                chunk = os.read(fd, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                chunk = b""
            if not chunk:
                break
            output.extend(chunk)
            if not prompted and b"Password:" in output:
                prompted = True
                os.write(fd, password.encode() + b"\n")
                if command:
                    # PAM restores the tty after the password. Wait until
                    # the shell can accept input rather than racing that flush.
                    time.sleep(0.5)
                    os.write(fd, command)
        else:
            raise AssertionError("PAM attempt timed out")
        _, status = os.waitpid(pid, 0)
        reaped = True
        assert os.waitstatus_to_exitcode(status) == expected_status, output
        assert b"AXON_FOREGROUND_RESTORED True" in output, output
        assert password.encode() not in output, "PAM echoed the password"
        return output
    finally:
        os.close(fd)
        if not reaped:
            os.kill(pid, 9)
            os.waitpid(pid, 0)


assert b"Authentication failed" in attempt(USER, "wrong-" + PASSWORD, 1)
assert b"Authentication failed" in attempt(USER + "-nonexistent", PASSWORD, 1)
result = attempt(USER, PASSWORD, 0, b'printf "AXON_UID=%s\\n" "$(/usr/bin/id -u)"; exit\n')
assert f"AXON_UID={UID}".encode() in result, result
print("PAM accepted only valid credentials, launched under the account UID, and restored the foreground tty.")
