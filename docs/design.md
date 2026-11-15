# axon design notes

A native Krypton TUI display manager. Minimal working v1; staged
for a Phase VII / cosmic-greeter-like progression.

## Layout

```
stdlib/termios.k        — raw tty mode via raw ioctls (no libc, no FFI)
stdlib/ansi.k           — box/colors/cursor rendering
modules/auth.k   — su-based password handoff (v1 shim)
modules/ui.k     — login-box rendering
modules/session.k — pty spawn (ptyMaster/ptyForkExec) + pump
axon.k     — the TUI loop (config, prompt, spawn)
axon.init  — SysV fragment (not enabled by default)
```

## What's missing for a production greeter

These are ordered roughly by importance and match the Phase VII roadmap:

1. **FFI on the Linux path** — to call libpam/libcrypt directly instead of
   shelling out to `su`. The macho macOS backend already has an FFI; land
   an ELF-backend foreign-call path first. When that lands, `greeter/auth`
   should be rewritten to use PAM (`pam_authenticate`, `pam_acct_mgmt`,
   `pam_open_session`) exactly once per login.
2. **Pure-Krypton crypto** — `sha512crypt`/`sha256crypt` (`$5$`/`$6$`) plus
   a fast SHA-512 (currently `hashlib.sha512` is a stub; `crypto.sha256`
   on Linux is a stub too). Needed for direct /etc/shadow verification
   without PAM or `su`.
3. **Session enumeration & configuration** — read `/usr/share/xsessions/*.desktop`
   (sddm/cosmic-greeter style) with a small ini/xml parser (stdlib has
   `ini.k` already) and expose a cycle-able session list in the UI.
4. **Seat/login handling** — proper logind-style session tracking is beyond
   v1; instead, spawn the session under `start-stop-daemon` with a status
   file so `init` can reap cleanly (or switch to `seatd`/`libseat` if FFI lands).
5. **cosmic-greeter-like surface** — once 4 lands and a Wayland surface is
   needed, the smackui example app (`socam_linux_demo`) already exercises
   the shape of a GPU-less Wayland greeter: window + render + input
   events. That example is the direct template.
6. **VT switching** — `/usr/bin/chvt` and `/usr/bin/fgconsole` via exec are
   enough for v1; FFI would give direct ioctls (`VT_OPENQRY`, `VT_ACTIVATE`).

## Build & try

```
KRYPTON_ROOT=<krypton> kcc_driver_linux_x86_64 axon.k -o /tmp/axon
/tmp/axon
```

The example expects a tty (it checks `termIsTTY(0)`). It draws a box, reads
a username, calls `su` for the password check, and spawns `/bin/sh` on a
pty for the session. The init fragment at `axon.init` is not
enabled by default; the default greeter remains a configurable boot-time choice.

## Notes

- `termios.k` needs VM Linux x86_64 `TCGETS`/`TCSETS` (0x5401/0x5402) —
  the ioctl builtin handles them; macOS would need its own numbers and a
  mac-side `cfmakeraw` equivalent.
- `bufNew`/`bufSetByte` are used for the tty ioctl buffers because that's
  what the backend implements; avoid raw pointer math here.
- `substring` (not `substr`) is the backend's string slice builtin.
- No global state; every greeter invocation is independent of the next.
