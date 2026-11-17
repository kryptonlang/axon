# Axon design notes

`axon.k` drives the greeter, and `modules/ui.k` and `modules/anim.k` draw it.
`modules/auth.k` hands the terminal to a fixed helper command;
only the quoted username and an internal session identifier travel as
arguments. Krypton emits static Linux ELF and does not call libpam directly.

`libexec/axon-pam` uses Linux-PAM's native terminal conversation so
passwords and other secrets stay out of Krypton, the command line, and the
environment. Only the quoted username, the session kind (`tty` or
`wayland`), and the `.desktop` session command cross as arguments. One PAM handle covers authentication, the account check,
expired-password changes, credential setup, and opening/closing the
session. The helper uses PAM's final username, initializes the user's
groups, and launches the selected session with that UID, GID, home,
and PAM environment. The greeter reclaims the terminal afterward.

`pam.d/axon` uses the same local-account modules as the KryptOS Ly stack.
KryptOS has no systemd or distribution-wide `login` PAM stack. The helper
requires an explicit `axon` policy and refuses null passwords. It never
falls back to `su` or a shadow-file check.

The greeter and session use a dedicated, foreground Linux virtual console.
The session list contains the login shell plus one entry per freedesktop
`.desktop` file found in `/usr/share/wayland-sessions` with both `Name=`
and `Exec=`, ly-style; `Exec=` field codes (`%U`, `%f`, …) are stripped
and the command is passed to `libexec/axon-pam` as an optional third
argument and run through `/bin/sh -c` (bare absolute paths are exec'd
directly). `Name`/`Exec` from the entry drive the picker; `Hidden` and
`NoDisplay` (case-insensitive booleans) hide the entry, and `TryExec`
hides it when the binary is unavailable. The entry's `DesktopNames`
(first value) is exported to the session as `XDG_CURRENT_DESKTOP` and
`XDG_SESSION_DESKTOP` alongside `XDG_SESSION_TYPE` and `XDG_VTNR`.
An optional `autologin=<user>` in `/etc/axon/config` logs the greeter
in at boot without a prompt via `/etc/pam.d/axon-autologin` (pam_permit,
ly-autologin style — enabled only by the config, never for root). X11, autologin, and a graphical password widget are outside
this login path. An optional `/etc/axon/config` selects the backdrop
with a single `animation=colormix|unimatrix|blank` line. KryptOS
packaging should install the three files listed in the README before
switching the boot service from Ly.

For disposable Linux integration tests, install `pam.d/axon`, create a
non-root test account with a valid password, and run
`python3 tests/pam-login.py ACCOUNT TEST_PASSWORD EXPECTED_UID` as root.
