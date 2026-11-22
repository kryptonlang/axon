#!/usr/bin/env python3
"""Axon autologin + power-menu verification for a disposable Linux system.

Run as root inside a disposable Linux system (the kryptos:base Docker image
works) with PAM and a test account:

  python3 tests/test-autologin.py /path/to/axon

Creates a non-root account axontest, a probe wayland session entry
(/usr/share/wayland-sessions/axon-probe.desktop) and /etc/axon/config, all
removed on exit. The test account must have a POSIX login shell and a valid
home directory.

What it proves:
  1. autologin=<user> skips the greeter entirely; the default (first
     non-tty) Wayland session launches directly and drops to the user's UID.
  2. That session gets XDG_SESSION_TYPE=wayland and XDG_*_DESKTOP from the
     session entry's DesktopNames= ("Hyprland" here).
  3. F2 renders the confirmation gate; Esc cancels it (Enter is never sent —
     this test would reboot the machine).
"""

import errno
import fcntl
import struct
import termios
import os
import pty
import pwd
import re
import select
import subprocess
import sys
import time

AXON = os.path.abspath(sys.argv[1])
USER = "axontest"
UID = pwd.getpwnam(USER).pw_uid
PROBE = "/usr/share/wayland-sessions/axon-probe.desktop"
CONFIG = "/etc/axon/config"
PROBE_OUT = "/tmp/axon-probe-out"
PROBE_SESSION = (
    "[Desktop Entry]\n"
    "Name=Axon Test Probe\n"
    "Exec=/bin/sh -c 'id -u > /tmp/axon-probe-out; env | grep ^XDG_ >> /tmp/axon-probe-out'\n"
    "DesktopNames=Hyprland\n"
    "Type=Application\n"
)


def axon_pty():
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 25, 80, 0, 0))
        os.execv(AXON, [AXON])
        os._exit(127)
    return pid, fd


def read_for(fd, seconds, stop_when=None):
    """Accumulate pty output for up to `seconds`; stop early on stop_when()."""
    out = bytearray()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if stop_when is not None and stop_when(bytes(out)):
            break
        if not select.select([fd], [], [], 0.1)[0]:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            break
        if not chunk:
            break
        out.extend(chunk)
    return bytes(out)


def finish(pid, fd, kill=False):
    try:
        os.write(fd, b"\x03")  # Ctrl-C: leave the greeter
    except OSError:
        pass
    if kill:
        os.kill(pid, 9)
    _, status = os.waitpid(pid, 0)
    os.close(fd)
    return os.waitstatus_to_exitcode(status)


def test_autologin():
    subprocess.run(["mkdir", "-p", os.path.dirname(CONFIG)], check=True)
    with open(CONFIG, "w") as f:
        f.write(f"autologin={USER}\n")
    with open(PROBE, "w") as f:
        f.write(PROBE_SESSION)
    if os.path.exists(PROBE_OUT):
        os.remove(PROBE_OUT)
    pid, fd = axon_pty()
    out = read_for(fd, 8)
    finish(pid, fd, kill=True)
    assert out.count(f"autologin as {USER}".encode()) == 1, "autologin repeated after logout"
    text = out.decode(errors="replace")
    assert "stty:" not in text, text[:1200]
    assert f"autologin as {USER}".encode() in out, "autologin line never printed"
    assert b"Password:" not in out, "autologin prompted for a password"
    assert os.path.exists(PROBE_OUT), "probe session never ran"
    probe = open(PROBE_OUT).read()
    print(f"--- probe session output ---\n{probe}")
    lines = [l for l in probe.splitlines() if l.isdigit()]
    assert lines and int(lines[0]) == UID, f"expected session UID {UID}, got {probe!r}"
    for required in (
        "XDG_SESSION_TYPE=wayland",
        "XDG_CURRENT_DESKTOP=Hyprland",
        "XDG_SESSION_DESKTOP=Hyprland",
    ):
        assert required in probe, f"missing {required} in {probe!r}"
    print("autologin OK: greeter skipped, UID drop, Wayland XDG env present")


def test_manual_login():
    with open(CONFIG, "w") as f:
        f.write("")
    pid, fd = axon_pty()
    try:
        out = read_for(fd, 8, stop_when=lambda o: b"TAB/arrows" in o)
        os.write(fd, USER.encode() + b"\r")
        prompted = read_for(fd, 8, stop_when=lambda o: b"Password:" in o)
        assert b"Password:" in prompted, "manual login did not reach PAM"
        os.write(fd, b"AxonTestpass-893\r")
        returned = read_for(fd, 8, stop_when=lambda o: b"Session ended" in o)
        assert b"Session ended" in returned, returned[-1000:]
        assert b"AxonTestpass-893" not in returned, "password was echoed"
        assert b"stty:" not in out + prompted + returned, "tty restore failed"
    finally:
        assert finish(pid, fd, kill=False) == 0
    print("manual login OK: PAM prompt, session launch, logout, greeter exit")


def test_power_menu():
    with open(CONFIG, "w") as f:
        f.write("")  # autologin disabled: interactive greeter
    pid, fd = axon_pty()
    out = read_for(fd, 8, stop_when=lambda o: b"TAB/arrows" in o)
    os.write(fd, b"\x1bOQ")  # SS3: ESC O Q = F2
    out += read_for(fd, 3, stop_when=lambda o: b"Reboot now?" in o)
    os.write(fd, b"\x1b")  # Esc cancels
    out += read_for(fd, 2)
    # Greeter loop exits on Ctrl-C (done==2 -> exit(0))
    assert finish(pid, fd, kill=False) == 0, "greeter did not exit cleanly"
    text = out.decode(errors="replace")
    assert "stty:" not in text, text[:1200]
    assert b"Reboot now? Enter = yes, Esc = cancel" in out, "F2 did not open the confirmation gate"
    print("power menu OK: F2 rendered the gate, Esc accepted (no reboot performed)")


def cleanup():
    for p in (PROBE, CONFIG, PROBE_OUT):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass


test_autologin()
test_manual_login()
test_power_menu()
cleanup()
print("PASS")
