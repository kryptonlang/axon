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
import "modules/auth.k"
import "modules/ui.k"
import "modules/anim.k"
import "modules/sessions.k"

// Terminal control via stty(1) — the Krypton ELF backend has no working
// termios ioctl on the pinned in-image toolchain, so we don't need one.
let _savedTty = ""

func _isTTY() {
    emit shellRun("test -t 0")
}

func _rawMode() {
    _savedTty = _trimTail(exec("stty -g"))
    if len(_savedTty) == 0 { emit 0 }
    shellRun("stty -icanon -echo -isig -ixon min 1 time 0")
    emit 1
}

func _pollingMode() {
    shellRun("stty min 0 time 0")
}

func _restoreMode() {
    if len(_savedTty) > 0 {
        shellRun("stty " + _savedTty)
    }
}

func _winsize() {
    // "stty size" prints "rows cols"; axon wants "cols,rows".
    let s = _trimTail(exec("stty size"))
    let i = 0
    while i < len(s) && s[i] != " " { i = i + 1 }
    let rows = substring(s, 0, i)
    let cols = _trimHead(substring(s, i + 1, len(s)))
    emit cols + "," + rows
}

// Backdrop animation: unimatrix (default), colormix, or blank. Override in
// /etc/axon/config with a line like:  animation=colormix
let g_anim = "unimatrix"
let g_sess = 0

func _sessCount() {
    emit sessionCount(g_sess)
}

func _sessName(i) {
    emit sessionName(g_sess, i)
}

func _sessMode(i) {
    if len(sessionExec(g_sess, i)) == 0 { emit "tty" }
    emit "wayland"
}

// ly defaults to the first non-tty session when one exists; index 0 is the
// built-in tty login shell.
func _defaultSess() {
    if _sessCount() > 1 { emit 1 }
    emit 0
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

func _readConfig() {
    let cfg = exec("cat /etc/axon/config 2>/dev/null")
    if len(cfg) == 0 { emit 0 }
    let total = lineCount(cfg)
    let i = 0
    while i < total {
        let line = getLine(cfg, i)
        let eq = indexOf(line, "=")
        if eq > 0 {
            let k = substring(line, 0, eq)
            let v = _trimTail(_trimHead(substring(line, eq + 1, len(line))))
            if k == "animation" {
                if v == "colormix" || v == "unimatrix" || v == "blank" { g_anim = v }
            } else if k == "power_reboot" {
                if len(v) > 0 { g_powerReboot = v }
            } else if k == "power_poweroff" {
                if len(v) > 0 { g_powerOff = v }
            } else if k == "power_suspend" {
                g_powerSuspend = v
            } else if k == "save_session" {
                if v == "off" || v == "false" || v == "0" { g_saveSession = 0 }
                else { g_saveSession = 1 }
            } else if k == "autologin" {
                g_autologin = v
            }
        }
        i = i + 1
    }
    emit 0
}

// Write the session NAME (not index — the list can reorder) to the state
// file.  Mode 0600 via umask; the file is root-owned and never world-read.
func _saveSession() {
    if g_saveSession == 0 { emit 0 }
    let q = ""
    let s = _sessName(g_sessIdx)
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "'" { q = q + "'\\''" }
        else { q = q + c }
        i = i + 1
    }
    exec("umask 077; printf '%s' '" + q + "' > /etc/axon/session-info")
    emit 1
}

// Load the last-chosen session name and select its index.  No file →
// keep the default (first non-tty session, or index 0).
func _loadSession() {
    let cur = exec("cat /etc/axon/session-info 2>/dev/null")
    if len(cur) == 0 { emit 0 }
    let saved = _trimTail(cur)
    let n = _sessCount()
    let i = 0
    while i < n {
        if _sessName(i) == saved { g_sessIdx = i; emit 1 }
        i = i + 1
    }
    emit 0
}

// ly stores the last-chosen session under /etc/ly/ly-session_info and
// pre-selects it at the next boot. Axon does the same, gated by
// save_session = on|off (default on) in /etc/axon/config.
let g_saveSession = 1

// ── confirm-gated power menu (F2 reboot, F3 poweroff, F4 suspend) ──
let g_power = 0            // 0=idle, 1=reboot, 2=poweroff, 3=suspend
let g_powerReboot = "/sbin/reboot"
let g_powerOff = "/sbin/poweroff"
let g_powerSuspend = ""    // "" = pick from /sys/power/mem_available
let g_susok = ""           // "" unknown, "1" available, "0" not
let g_autologin = ""
let g_flash = ""

func _suspendOk() {
    if g_susok == "1" { emit 1 }
    if g_susok == "0" { emit 0 }
    let s = exec("cat /sys/power/mem_available 2>/dev/null")
    if indexOf(s, "deep") >= 0 || indexOf(s, "mem") >= 0 || indexOf(s, "s2idle") >= 0 {
        g_susok = "1"
        emit 1
    }
    g_susok = "0"
    emit 0
}

func _suspendCmd() {
    if len(g_powerSuspend) > 0 { emit g_powerSuspend }
    let s = exec("cat /sys/power/mem_available 2>/dev/null")
    if indexOf(s, "deep") >= 0 { emit "echo deep > /sys/power/state" }
    if indexOf(s, "mem") >= 0 { emit "echo mem > /sys/power/state" }
    if indexOf(s, "s2idle") >= 0 { emit "echo s2idle > /sys/power/state" }
    emit "echo mem > /sys/power/state"
}

func _powerKey(kind) {
    if kind == 3 {
        if _suspendOk() == 0 {
            g_flash = "Suspend not available on this system"
            emit 0
        }
    }
    g_power = kind
    emit 0
}

func _doPower() {
    if g_power == 1 { emit toInt(shellRun(g_powerReboot)) }
    else if g_power == 2 { emit toInt(shellRun(g_powerOff)) }
    else if g_power == 3 { emit toInt(shellRun(_suspendCmd())) }
    emit 1
}

func _trimHead(s) {
    let start = 0
    while start < len(s) {
        let c = s[start]
        if c == " " || c == "\t" {
            start = start + 1
        } else {
            break
        }
    }
    emit substring(s, start, len(s))
}

// value of the esc-sequence collector for CSI tilde sequences
let g_escNum = 0

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

// Handle one input byte of an ESC sequence. g_esc states: 0=none, 1=ESC seen,
// 2=ESC [ seen (CSI), 3=ESC O seen (SS3), 4=collecting CSI digits for ~.
// Shared state passed via globals for brevity — a greeter runs once per boot.
let g_user = ""
let g_esc = 0       // 0=normal, 1=ESC seen, 2=ESC+[ CSI, 3=ESC+O SS3, 4=CSI digits
let g_escAt = 0     // timestamp() when ESC seen (lone-Esc timeout)
let g_sessIdx = 0

func _escByte(c) {
    if g_esc == 1 {
        if c == 91 { g_esc = 2 }        // [
        else if c == 79 { g_esc = 3 }   // O (SS3; F1-F4)
        else { g_esc = 0 }
        emit 0
    } else if g_esc == 2 {
        if c >= 48 && c <= 57 { g_escNum = g_escNum * 10 + (c - 48)  g_esc = 4  emit 0 }
        else if c == 65 {                     // A — previous session
            g_sessIdx = (g_sessIdx + _sessCount() - 1) % _sessCount()
        } else if c == 66 || c == 67 {   // B/C — next session
            g_sessIdx = (g_sessIdx + 1) % _sessCount()
        } else if c == 68 {              // D — previous session
            g_sessIdx = (g_sessIdx + _sessCount() - 1) % _sessCount()
        }
        g_esc = 0
        emit 0
    } else if g_esc == 3 {
        if c == 81 { _powerKey(1) }      // Q — F2: reboot
        else if c == 82 { _powerKey(2) } // R — F3: poweroff
        else if c == 83 { _powerKey(3) } // S — F4: suspend
        else if c == 85 { exec("chvt 2") }   // U — F6: rescue TTY (getty on tty2)
        g_esc = 0
        emit 0
    } else if g_esc == 4 {
        if c >= 48 && c <= 57 {
            g_escNum = g_escNum * 10 + (c - 48)
            emit 0
        }
        if c == 126 {                    // ~ — end of CSI tilde sequence
            if g_escNum == 12 { _powerKey(1) }    // F2
            else if g_escNum == 13 { _powerKey(2) }  // F3
            else if g_escNum == 14 { _powerKey(3) }  // F4
        }
        g_escNum = 0
        g_esc = 0
        emit 0
    }
    g_esc = 0
    emit 0
}

func _key(c) {
    if g_esc != 0 {
        let r = _escByte(c)
        emit r
    }
    if g_power != 0 {
        // Confirm dialog: Enter = yes, Esc = cancel (lone Esc via timeout),
        // everything else is noise.
        if c == 13 || c == 10 { emit 3 }
        if c == 27 { g_esc = 1  g_escAt = toInt(timestamp()) }
        emit 0
    }
    if c == 27 { g_esc = 1  g_escAt = toInt(timestamp())  emit 0 }
    else if c == 9  { g_sessIdx = (g_sessIdx + 1) % _sessCount()  emit 0 }
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
        // Lone-Esc timeout: an unterminated ESC sequence is a lone Escape —
        // reset the parser; cancel any pending power confirmation.
        if g_esc == 1 {
            if toInt(timestamp()) - g_escAt >= 1 {
                g_esc = 0
                if g_power != 0 { g_power = 0 }
            }
        }
        let statusMsg = message
        if g_power == 1 { statusMsg = bold("Reboot now? Enter = yes, Esc = cancel") }
        else if g_power == 2 { statusMsg = bold("Power off now? Enter = yes, Esc = cancel") }
        else if g_power == 3 { statusMsg = bold("Suspend now? Enter = yes, Esc = cancel") }
        else if len(g_flash) > 0 { statusMsg = g_flash  g_flash = "" }
        drawLogin(cols, rows, g_user, _sessName(g_sessIdx), statusMsg)
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
    if _isTTY() != "0" {
        print("axon: stdin is not a tty — a display manager needs a terminal.")
        exit("1")
    }
    g_sess = buildSessions()
    _readConfig()
    hideCursor()
    clearScrollback()
    let saved = _rawMode()
    if saved == 0 {
        showCursor()
        print("axon: could not set raw mode.")
        exit("1")
    }
    _pollingMode()   // VMIN=0/VTIME=0: reads never block — the frame loop needs it
    let ws = _winsize()
    let cols = _colsOf(ws)
    let rows = _rowsOf(ws)

    // Display-manager loop: keep offering login forever — a DM never exits
    // just because one session ended. Returns here after every logout.
    let message = "TAB/arrows select session · Enter logs in · F6 console"
    while 1 == 1 {
        g_user = ""
        g_esc = 0
        g_sessIdx = _defaultSess()
        _loadSession()
        hideCursor()

        if len(g_autologin) > 0 {
            print("axon: autologin as " + g_autologin)
            let arc = authSession(g_autologin, "autologin", sessionExec(g_sess, g_sessIdx), sessionDesktop(g_sess, g_sessIdx))
            _saveSession()
            _pollingMode()   // re-arm polling for the next iteration
            if arc == 0 {
                message = "Session ended · Enter logs in"
                continue
            }
            // Fall back to the interactive greeter rather than loop forever.
            g_flash = "Autologin failed — signing in manually"
            message = "Autologin failed; sign in manually"
            g_autologin = ""
        }

        let done = _loginScreen(cols, rows, message)
        _restoreMode()
        showCursor()

        if done == 3 {
            // Power confirmation: Enter = perform the action. Only reached
            // when _key saw the user confirm. Greeter runs as root.
            let rc = _doPower()
            if rc == 0 {
                message = "Power command ran."
            } else {
                message = "Power command failed."
            }
            g_power = 0
            _pollingMode()
            continue
        }
        if done == 2 {          // Ctrl-C: leave the greeter (service stops/respawns by design)
            print("")
            exit("0")
        }
        if g_user == "" {
            print("")
            _pollingMode()   // re-arm polling for the next iteration
            continue
        }

        print(ansiClear())
        print("Sign in to " + _sessName(g_sessIdx))
        let rc = authSession(g_user, _sessMode(g_sessIdx), sessionExec(g_sess, g_sessIdx), sessionDesktop(g_sess, g_sessIdx))
        _saveSession()
        _restoreMode()
        if rc == 0 {
            message = "Session ended · Enter logs in"
        } else {
            message = "Sign-in failed · Enter to retry"
        }
        _pollingMode()
    }
}
