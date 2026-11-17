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
like ly. Entries with `Hidden=true` or `NoDisplay=true` (case-insensitive)
are skipped, and `TryExec=` is honored: the entry is hidden when its binary
is missing. `Exec=` runs through `/bin/sh -c`, so commands with arguments,
env prefixes, or redirects work as the freedesktop spec expects; field
codes (`%U`, `%f`, …) are stripped. KryptOS ships
`kryptos-hyprland.desktop` (`Exec=/usr/bin/start-hypr`, `DesktopNames=Hyprland`).

The session receives `XDG_SESSION_TYPE=wayland|tty`, the `DesktopNames`
(first entry) as `XDG_CURRENT_DESKTOP` and `XDG_SESSION_DESKTOP`, plus
`XDG_VTNR` on tty session launches — enough for xdg-desktop-portal and
friends to pick the right backend.

## Configuration

Optional `/etc/axon/config`:

    animation=unimatrix   # or colormix, blank
    autologin=user        # passwordless login at boot (ly-autologin-style;
                          # uses /etc/pam.d/axon-autologin, refuses root)
    power_reboot=...      # override reboot command (default /sbin/reboot)
    power_poweroff=...    # override poweroff command (default /sbin/poweroff)
    power_suspend=...     # override suspend command (default: auto, from
                          # /sys/power/mem_available)

Autologin needs the account to exist and runs its login shell; it is
disabled at boot and the greeter falls back to manual sign-in if the
autologin attempt fails.

## Keys

    TAB / ← / →  cycle sessions
    ENTER        log in (confirm power action in the confirm dialog)
    Ctrl-C       quit the greeter
    F2           reboot      (with Enter/Esc confirm)
    F3           power off
    F4           suspend
