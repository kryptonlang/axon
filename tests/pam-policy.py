#!/usr/bin/env python3
"""Run only inside the isolated-linux.py chroot; mutates its test shadow file."""
import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import time

helper = "/usr/local/libexec/axon-pam"


def attempt(username, command, expected):
    pid, fd = pty.fork()
    if pid == 0:
        rc = subprocess.call([sys.executable, "-I", helper, username, "autologin", command])
        os._exit(rc)
    output = b""
    finished = False
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if not select.select([fd], [], [], 0.2)[0]:
                continue
            try:
                chunk = os.read(fd, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            output += chunk
        else:
            raise AssertionError("autologin policy attempt timed out")
        _, status = os.waitpid(pid, 0)
        finished = True
        assert os.waitstatus_to_exitcode(status) == expected, output
        assert b"Password:" not in output, output
        return output
    finally:
        os.close(fd)
        if not finished:
            os.kill(pid, 9)
            os.waitpid(pid, 0)


attempt("axontest", "/bin/sh -c 'exit 0'", 0)
assert b"status 17" in attempt("axontest", "/bin/sh -c 'exit 17'", 1)
assert b"not permitted for root" in attempt("root", "/bin/sh -c 'exit 0'", 1)
shadow = Path("/etc/shadow")
original = shadow.read_text()
try:
    records = []
    for record in original.splitlines():
        fields = record.split(":")
        if fields[0] == "axontest":
            fields[7] = "1"
        records.append(":".join(fields))
    shadow.write_text("\n".join(records) + "\n")
    assert b"Account check failed" in attempt("axontest", "/bin/sh -c 'exit 0'", 1)
finally:
    shadow.write_text(original)
print("PAM policy: root/expired autologin rejected; failed session returns failure.")
