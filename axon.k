// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/axon.k — Axon: a native Krypton TUI display manager (Axon-style).
//
// Draws a full-screen built-in backdrop (colormix/unimatrix/blank — a builtin
// `animation` setting), overlays a login box with a selectable session,
// then hands the foreground terminal to a PAM-backed session launcher.
//
// Build + run on Linux:
//   KRYPTON_ROOT=<krypton> kcc_driver_linux_x86_64 axon.k -o /tmp/axon
//   /tmp/axon
//
// Keys: printable type the user; TAB / ← → cycle sessions; ENTER logs in;
// Ctrl-C quits. Empty usernames are ignored.

import "k:ansi"
import "k:termios"
import "modules/auth.k"
import "modules/ui.k"
import "modules/anim.k"
import "modules/sessions.k"

// Backdrop animation: unimatrix (default), colormix, or blank. Override in
// /etc/axon/config with a line like:  animation=colormix
let g_anim = "unimatrix"

func _buildSessions() {
    buildSessions()
    emit 0
}

func _sessCount() {
    emit sessionCount()
}

func _sessName(i) {
    emit sessionName(i)
}

func _sessMode(i) {
    if len(sessionExec(i)) == 0 { emit "tty" }
    emit "wayland"
}

func _backdropFrame(cols, rows, f) {
    if g_anim == "colormix" { emit colormixFrame(cols, rows, f) }
    else if g_anim == "blank" { emit blankFrame(cols, rows, f) }
    emit unimatrixFrame(cols, rows, f)
}

func _trimTail(s) {
    let end = len(s)
    while end > 0 {
        let c = s[end - 1]
        if c == " " || c == "\t" || c == "\r" || c == "\n" {
            end = end - 1
        } else {
            break
        }
    }
    emit substring(s, 0, end)
}

func _readBackdrop() {
    let cfg = shellRun("cat /etc/axon/config 2>/dev/null")
    if len(cfg) == 0 { emit 0 }
    let total = lineCount(cfg)
    let i = 0
    while i < total {
        let line = getLine(cfg, i)
        if len(line) >= 10 {
            if substring(line, 0, 10) == "animation=" {
                let v = _trimTail(substring(line, 10, len(line)))
                if v == "colormix" || v == "unimatrix" || v == "blank" {
                    g_anim = v
                }
            }
        }
        i = i + 1
    }
    emit 0
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

func _loginScreen(cols, rows, message) {
    let frame = 0
    let done = -1
    while done < 1 {
        // Full-screen backdrop only on a slow cadence — it's ~30 KB of ANSI
        // per repaint; redrawing it every iteration is what makes input feel
        // delayed on a pty. The box redraw below is ~600 B and every key
        // lands in one iteration regardless.
        if frame % 12 == 0 { print(_backdropFrame(cols, rows, frame)) }
        frame = frame + 1
        drawLogin(cols, rows, g_user, _sessName(g_sessIdx), message)
        // Drain ALL pending input bytes, not just one — an 8-15 fps frame
        // cap would otherwise swallow keystrokes one at a time.
        let b = bufNew(16)
        let any = 0
        let n = fdReadN(0, b, 16)
        while n > 0 {
            any = 1
            let off = 0
            while off < n {
                // done: 0=normal byte, 1=submit, 2=Ctrl-C (-1 = not started).
                // _key returns 0 for regular bytes — keep draining until a decision.
                if done < 1 { done = _key(toInt(bufGetByte(b, off))) }
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
    _readBackdrop()
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

    // Display-manager loop: keep offering login forever — a DM never exits
    // just because one session ended. Returns here after every logout.
    let message = "TAB/arrows select session · Enter logs in"
    while 1 == 1 {
        g_user = ""
        g_esc = 0
        g_sessIdx = 0
        hideCursor()

        let done = _loginScreen(cols, rows, message)
        termRestore(0, saved)
        showCursor()

        if done == 2 {          // Ctrl-C: leave the greeter (service stops/respawns by design)
            print("")
            exit("0")
        }
        if g_user == "" {
            print("")
            termPolling(0, saved)   // re-arm polling for the next iteration
            continue
        }

        print(ansiClear())
        print("Sign in to " + _sessName(g_sessIdx))
        let rc = authSession(g_user, _sessMode(g_sessIdx), sessionExec(g_sessIdx))
        termRestore(0, saved)
        if rc == 0 {
            message = "Session ended · Enter logs in"
        } else {
            message = "Sign-in failed · Enter to retry"
        }
        termPolling(0, saved)
    }
}
