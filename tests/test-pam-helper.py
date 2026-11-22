"""Portable lifecycle regression tests; real PAM/VT tests are separate."""
import ctypes
import importlib.machinery
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
import sys
sys.dont_write_bytecode = True
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "libexec/axon-pam"
loader = importlib.machinery.SourceFileLoader("axon_pam", str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)


class Lifecycle(unittest.TestCase):
    def exercise(self, mode="wayland", command="/bin/sh", exitcode=0,
                 account=0, close=0, uid=1000):
        calls = []
        user = SimpleNamespace(pw_name="test", pw_uid=uid, pw_gid=1000,
                               pw_dir="/home/test", pw_shell="/bin/sh")

        def invoke(name, *args):
            calls.append((name, args))
            if name == "pam_get_item":
                ctypes.cast(args[2], ctypes.POINTER(ctypes.c_char_p))[0] = b"test"
            if name == "pam_acct_mgmt":
                return account
            if name == "pam_close_session":
                return close
            if name == "pam_getenvlist":
                return None
            return 0

        def binding(lib, name, *signature):
            return lambda *args: invoke(name, *args)

        library = SimpleNamespace(misc_conv=ctypes.c_void_p())
        with patch.object(helper.C, "CDLL", return_value=library), \
             patch.object(helper, "bind", side_effect=binding), \
             patch.object(helper.pwd, "getpwnam", return_value=user), \
             patch.object(helper.os, "getgrouplist", return_value=[1000, 44]), \
             patch.object(helper.subprocess, "run",
                          return_value=SimpleNamespace(returncode=exitcode)) as launch:
            error = None
            try:
                helper.run_session("test", mode, "/dev/tty1", command)
            except (ValueError, helper.PamError) as exc:
                error = exc
        return calls, launch, error

    def test_success_drops_identity_and_closes_session(self):
        calls, launch, error = self.exercise()
        self.assertIsNone(error)
        self.assertEqual(launch.call_args.kwargs["user"], 1000)
        self.assertEqual(launch.call_args.kwargs["extra_groups"], [1000, 44])
        names = [name for name, args in calls]
        self.assertLess(names.index("pam_authenticate"), names.index("pam_open_session"))
        self.assertEqual(names[-3:], ["pam_close_session", "pam_setcred", "pam_end"])

    def test_failed_session_is_not_success(self):
        calls, launch, error = self.exercise(exitcode=17)
        self.assertIn("status 17", str(error))
        self.assertEqual(calls[-1][0], "pam_end")

    def test_expired_account_cannot_launch(self):
        calls, launch, error = self.exercise(account=13)
        self.assertIsInstance(error, helper.PamError)
        launch.assert_not_called()
        self.assertNotIn("pam_open_session", [name for name, args in calls])

    def test_cleanup_failure_is_not_success(self):
        _, _, error = self.exercise(close=14)
        self.assertIsInstance(error, helper.PamError)

    def test_autologin_shell_is_tty(self):
        calls, launch, error = self.exercise(mode="autologin", command=None)
        self.assertIsNone(error)
        self.assertEqual(launch.call_args.args[0], ["-sh"])
        self.assertIn(("pam_putenv", (unittest.mock.ANY, b"XDG_SESSION_TYPE=tty")), calls)

    def test_root_autologin_is_rejected(self):
        _, launch, error = self.exercise(mode="autologin", uid=0)
        self.assertIn("not permitted for root", str(error))
        launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
