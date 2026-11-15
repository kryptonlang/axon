// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/axon.k — Axon: a native Krypton TUI display manager (Axon-style).
//
// Draws a full-screen built-in backdrop (colormix/unimatrix/blank — a builtin
// `animation` setting), overlays a login box with a selectable session,
// hands the tty to `su` for the password check, then spawns the chosen
// session on a fresh pty. Deliberately self-contained: no FFI, no PAM —
// credential crypto stays with su until Phase VII lands the FFI.
//
// Build + run on Linux:
//   KRYPTON_ROOT=<krypton> kcc_driver_linux_x86_64 axon.k -o /tmp/axon
//   /tmp/axon
//
// Keys: printable type the user; TAB / ← → cycle sessions; ENTER logs in;
// Ctrl-C quits. Empty username prints the back-exit path.

import "k:ansi"
import "k:termios"
import "modules/auth.k"
import "modules/ui.k"
import "modules/session.k"
import "modules/anim.k"

let sessName0 = "TTY (sh)"
let sessCmd0  = "/bin/sh"
let sessName1 = ""
let sessCmd1  = ""

func _buildSessions() {
    if shellRun("test -x /usr/bin/Hyprland && echo 1 || echo 0") == "1" {
        sessName1 = "Hyprland"
        sessCmd1  = "/usr/bin/Hyprland"
    }
    emit 0
}

func _sessCount() {
    if sessName1 == "" { emit 1 }
    emit 2
}

func _sessName(i) {
    if i == 0 { emit sessName0 }
    emit sessName1
}

func _sessCmd(i) {
    if i == 0 { emit sessCmd0 }
    emit sessCmd1
}

func _colsOf(s) {
    let n = len(s)
    let out = ""
    let i = 0
    while i < n && s[i] != "," {
        out = out + s[i]
        i = i + 1
    }
    emit toInt(out)
}

func _rowsOf(s) {
    let n = len(s)
    let out = ""
    let i = 0
    while i < n && s[i] != "," { i = i + 1 }
    i = i + 1
    while i < n {
        out = out + s[i]
        i = i + 1
    }
    emit toInt(out)
}

// Handle one input byte; returns 1 when the login screen wants to exit
// (submit or Ctrl-C), else 0. Shared state passed via globals for brevity —
// a greeter runs once per boot.
let g_user = ""
let g_esc = 0       // 0=normal, 1=ESC seen, 2=ESC+[ seen
let g_sessIdx = 0

func _key(c) {
    if g_esc == 1 {
        if c == 91 { g_esc = 2 }        // [
        else { g_esc = 0 }
        emit 0
    } else if g_esc == 2 {
        if c == 65 {                     // A — previous session
            g_sessIdx = (g_sessIdx + _sessCount() - 1) % _sessCount()
        } else if c == 66 || c == 67 {   // B/C — next session
            g_sessIdx = (g_sessIdx + 1) % _sessCount()
        } else if c == 68 {              // D — previous session
            g_sessIdx = (g_sessIdx + _sessCount() - 1) % _sessCount()
        }
        g_esc = 0
        emit 0
    }

    if c == 27 { g_esc = 1; emit 0 }
    else if c == 9  { g_sessIdx = (g_sessIdx + 1) % _sessCount(); emit 0 }
    else if c == 127 {
        if len(g_user) > 0 { g_user = substring(g_user, 0, len(g_user) - 1) }
        emit 0
    }
    else if c == 13 || c == 10 { emit 1 }
    else if c == 3  { emit 2 }                                        // Ctrl-C
    else if c >= 32 && c <= 126 { g_user = g_user + fromCharCode(c); emit 0 }
    emit 0
}

func _loginScreen(cols, rows) {
    let frame = 0
    let sess = _sessName(g_sessIdx)
    let done = -1
    while done == -1 {
        // Full-screen backdrop only on a slow cadence — it's ~30 KB of ANSI
        // per repaint; redrawing it every iteration is what makes input feel
        // delayed on a pty. The box redraw below is ~600 B and every key
        // lands in one iteration regardless.
        if frame % 12 == 0 { print(unimatrixFrame(cols, rows, frame)) }
        frame = frame + 1
        drawLogin(cols, rows, g_user, sess, "TAB/arrows select session · Enter logs in")
        // Drain ALL pending input bytes, not just one — an 8-15 fps frame
        // cap would otherwise swallow keystrokes one at a time.
        let b = bufNew(16)
        let any = 0
        let n = fdReadN(0, b, 16)
        while n > 0 {
            any = 1
            let off = 0
            while off < n {
                if done == -1 { done = _key(toInt(bufGetByte(b, off))) }
                off = off + 1
            }
            n = fdReadN(0, b, 16)
        }
        if any == 0 { sleepUs(0, 16000) }
    }
    emit done
}

just run {
    if termIsTTY(0) == 0 {
        print("axon: stdin is not a tty — a display manager needs a terminal.")
        exit("1")
    }
    _buildSessions()
    hideCursor()
    clearScrollback()
    let saved = termRaw(0)
    if saved == 0 {
        showCursor()
        print("axon: could not set raw mode.")
        exit("1")
    }
    termPolling(0, saved)   // VMIN=0/VTIME=0: reads never block — the frame loop needs it
    let ws = termWinsize(0)
    let cols = _colsOf(ws)
    let rows = _rowsOf(ws)

    let done = _loginScreen(cols, rows)
    termRestore(0, saved)
    showCursor()

    if done == 2 {          // Ctrl-C
        print("")
        exit("0")
    }
    if g_user == "" {
        print("")
        exit("0")
    }

    hideCursor()
    print(ansiClear())
    print("axon: handing off to `su` for" + g_user + "...")
    showCursor()
    let rc = authVerify(g_user)
    showCursor()
    if rc != 0 {
        print("Authentication failed.")
        exit("1")
    }

    print("Starting " + _sessName(g_sessIdx) + "...")
    termRaw(0)
    hideCursor()
    sessionStart(_sessCmd(g_sessIdx))
    termRestore(0, saved)
    showCursor()
    print("")
    print("Session ended. Goodbye.")
    exit("0")
}
