#!/usr/bin/env python3
"""Root-only integration runner: tests inside a temporary chroot, never host PAM.

Usage: sudo python3 tests/isolated-linux.py /path/to/linux-axon
Requires Python 3, ldd, openssl, and Linux-PAM on the Linux test host.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import sysconfig
import tempfile

if sys.platform != "linux" or os.geteuid() != 0:
    sys.exit("Run as root on a disposable Linux test VM.")
source = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="axon-chroot-") as directory:
    root = Path(directory)
    root.chmod(0o755)

    def copy_file(path):
        path = Path(path)
        dest = root / str(path).lstrip("/")
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists():
            shutil.copy2(path, dest)
        return dest

    def executable(path):
        copy_file(path)
        output = subprocess.check_output(["ldd", str(path)], text=True)
        for dependency in re.findall(r"(?:=>\s+)?(/[^\s()]+)", output):
            copy_file(dependency)

    executable(sys.executable)
    stdlib = Path(sysconfig.get_path("stdlib"))
    shutil.copytree(stdlib, root / str(stdlib).lstrip("/"), dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("site-packages", "dist-packages",
                                                 "__pycache__", "test", "tests",
                                                 "idlelib", "tkinter"))
    for extension in (root / str(stdlib).lstrip("/") / "lib-dynload").glob("*.so"):
        executable(Path("/") / extension.relative_to(root))
    for name in ("sh", "bash", "id", "env", "grep", "mkdir", "stty", "cat", "ls"):
        command = shutil.which(name)
        executable(command)
        # The helper and tests use conventional absolute paths.
        alias = root / "bin" / name
        alias.parent.mkdir(exist_ok=True)
        if not alias.exists():
            alias.symlink_to(command)
    for helper_name in ("unix_chkpwd", "unix_update"):
        helper_path = shutil.which(helper_name) or str(Path("/usr/sbin") / helper_name)
        if Path(helper_path).exists():
            executable(helper_path)
            alias = root / "sbin" / helper_name
            alias.parent.mkdir(exist_ok=True)
            if not alias.exists():
                alias.symlink_to(helper_path)
    cache = subprocess.check_output(["ldconfig", "-p"], text=True)
    for name in ("libpam.so.0", "libpam_misc.so.0"):
        executable(re.search(r"\b" + re.escape(name) + r"\s.*=> (\S+)", cache)[1])
    pam_module = next(Path("/lib").glob("**/security/pam_unix.so"))
    executable(pam_module)
    executable(pam_module.resolve())
    for module in ("pam_permit.so", "pam_deny.so"):
        executable(pam_module.with_name(module))
        executable(pam_module.with_name(module).resolve())
    shutil.copytree(source, root / "src", ignore=shutil.ignore_patterns(".git", "__pycache__"))
    for path in ("etc/pam.d", "etc/axon", "usr/local/libexec", "usr/bin",
                 "usr/share/wayland-sessions", "home/axontest", "tmp", "run", "dev/pts", "proc"):
        (root / path).mkdir(parents=True, exist_ok=True)
    (root / "tmp").chmod(0o1777)
    os.chown(root / "home/axontest", 1000, 1000)
    shutil.copy2(binary, root / "usr/bin/axon")
    shutil.copy2(source / "libexec/axon-pam", root / "usr/local/libexec/axon-pam")
    # Helper invokes /usr/bin/python3 even when the host uses /usr/local.
    python = root / "usr/bin/python3"
    if not python.exists():
        python.symlink_to(sys.executable)
    shutil.copytree(source / "pam.d", root / "etc/pam.d", dirs_exist_ok=True)
    (root / "etc/passwd").write_text("root:x:0:0:root:/root:/bin/sh\naxontest:x:1000:1000:Test:/home/axontest:/bin/sh\n")
    (root / "etc/nsswitch.conf").write_text("passwd: files\ngroup: files\nshadow: files\n")
    (root / "etc/group").write_text("root:x:0:\naxontest:x:1000:\n")
    password = "AxonTestpass-893"
    hashed = subprocess.check_output(["openssl", "passwd", "-6", password], text=True).strip()
    (root / "etc/shadow").write_text(f"root:!:20000:0:99999:7:::\naxontest:{hashed}:20000:0:99999:7:::\n")
    (root / "etc/shadow").chmod(0o600)
    # All mounts live in a private mount namespace and disappear on exit.
    commands = """
set -eu
mount --make-rprivate /
mount --rbind /dev "$1/dev"
mount -t proc proc "$1/proc"
chroot "$1" /usr/bin/python3 /src/tests/pam-login.py axontest AxonTestpass-893 1000
chroot "$1" /usr/bin/python3 /src/tests/pam-policy.py
chroot "$1" /usr/bin/python3 /src/tests/test-autologin.py /usr/bin/axon
"""
    subprocess.run(["unshare", "--mount", "--", "/bin/sh", "-c", commands,
                    "axon-test", str(root)], check=True)
