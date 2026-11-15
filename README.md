# axon

Axon — the native Krypton display manager for KryptOS.

Axon is a small, self-contained TUI display manager written in pure Krypton.
It draws a built-in full-screen backdrop, offers a login box and a session
picker, hands the tty to `su` for the password check, and spawns the chosen
session on a fresh pty. No FFI, no PAM dependency, no C — the same toolchain
as the rest of KryptOS.

## Build

    KRYPTON_ROOT=<krypton> kcc_driver_linux_x86_64 axon.k -o /usr/local/bin/axon

## Status

Working v1: animated backdrop, session picker (Hyprland / TTY), su-backed
authentication, pty session spawn. Staged for a Phase VII progression
(Linux FFI → libpam, pure-Krypton `$6$` verify, session enumeration from
`xsessions`, Wayland surface).

See `docs/design.md` for the module layout and the roadmap.
