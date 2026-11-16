# Axon

Axon is a native Krypton TUI display manager for KryptOS. Select a login shell or the session offered by
`/usr/share/wayland-sessions`, then sign in through Linux-PAM. PAM handles
password prompts and account policy; Axon starts the session as the account
PAM authenticated and returns to the greeter after logout.

## Build and install on KryptOS

Build with the KryptOS Linux x86-64 Krypton toolchain:

    KRYPTON_ROOT=<krypton> kcc_driver_linux_x86_64 axon.k -o /tmp/axon

Install these files as root. KryptOS already builds Python 3 with ctypes and
Linux-PAM, including libpam_misc. The PAM file below is the KryptOS policy;
on another Linux distribution, configure an explicit `axon` PAM service
appropriate to that system.

    install -Dm755 /tmp/axon /usr/bin/axon
    install -Dm755 libexec/axon-pam /usr/local/libexec/axon-pam
    install -Dm644 pam.d/axon /etc/pam.d/axon

Use a spare physical Linux VT with no competing getty or display manager.
Run Axon as root on the foreground controlling terminal. Keep a separate
rescue VT available. The KryptOS image currently boots Ly; installing these
files does not change that. For an init-driven trial, see `axon.init`.

The KryptOS Hyprland entry prefers `/usr/bin/start-hypr`, which currently
requires root on KryptOS. The TTY entry starts the authenticated user's
login shell. Empty passwords are rejected. See [design notes](docs/design.md)
for the login flow and current limits.

## Sessions

The greeter always offers "Login shell" (a tty login for the authenticated
account) plus one entry per freedesktop session in
`/usr/share/wayland-sessions/*.desktop` that has both `Name=` and `Exec=`,
like ly. `Exec=` field codes (`%U`, `%f`, …) are stripped. KryptOS ships
`kryptos-hyprland.desktop` (`Exec=/usr/bin/start-hypr`).

## Configuration

Optional `/etc/axon/config`:

    animation=unimatrix   # or colormix, blank
