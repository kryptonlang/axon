// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/modules/sessions.k — enumerate display sessions ly-style.
//
// ly scans /usr/share/wayland-sessions/*.desktop and offers one entry per
// file that has both Name= and Exec=. Axon does the same: every .desktop
// entry is appended after the built-in "Login shell" (a tty login), and its
// Exec= command is handed to axon-pam as the third argument. Field codes
// (%U, %f, …) are stripped from Exec=.
//
// STATE HAS TO LIVE IN A HEAP STRUCT, NOT IN MODULE-LEVEL `let`: an
// imported module's top-level variables do not persist across calls into it
// (verified on the Linux backend — see stdlib/wayland.k's removed wlNewId),
// so any session list kept in module globals is silently empty at runtime.
// buildSessions() returns the populated struct; the caller (axon.k) stores
// it in its own main-module global and passes it to every query function.

module axon_sessions

// sh-safe single-quoting: 'it'\''s'
func _shellQuote(s) {
    let out = "'"
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "'" { out = out + "'\\''" }
        else { out = out + c }
        i = i + 1
    }
    out = out + "'"
    emit out
}

// freedesktop booleans are case-insensitive; accept true / 1.
func _isTruthy(v) {
    let s = _trimHead(_trimTail(v))
    let out = ""
    let i = 0
    while i < len(s) {
        let c = s[i]
        let code = charCode(c)
        if code >= 65 && code <= 90 { out = out + fromCharCode(code + 32) }
        else { out = out + c }
        i = i + 1
    }
    if out == "true" || out == "1" { emit 1 }
    emit 0
}

func _trimTail(s) {
    let end = len(s)
    while end > 0 {
        let v = charCode(s[end - 1])
        if v == 32 || v == 9 || v == 13 || v == 10 {
            end = end - 1
        } else {
            break
        }
    }
    emit substring(s, 0, end)
}

func _trimHead(s) {
    let start = 0
    while start < len(s) {
        let v = charCode(s[start])
        if v == 32 || v == 9 {
            start = start + 1
        } else {
            break
        }
    }
    emit substring(s, start, len(s))
}

// Strip freedesktop field codes (" %U", " %f", …) from an Exec= line.
// A field code is '%' followed by one ASCII letter; a preceding space is
// removed with it. Escaped %% becomes a single %.
func _stripFieldCodes(e) {
    let out = ""
    let i = 0
    while i < len(e) {
        let c = e[i]
        if c == "%" && i + 1 < len(e) {
            let nxt = e[i + 1]
            if nxt == "%" {
                out = out + "%"
                i = i + 2
                continue
            }
            let v = charCode(nxt)
            if (v >= 65 && v <= 90) || (v >= 97 && v <= 122) {
                // drop the code and a preceding space if present
                if len(out) > 0 && charCode(out[len(out) - 1]) == 32 {
                    out = substring(out, 0, len(out) - 1)
                }
                i = i + 2
                continue
            }
        }
        out = out + c
        i = i + 1
    }
    emit out
}

// Value of the first "Key=value" line in an INI-style desktop entry, trimmed.
func _desktopKey(content, key) {
    let prefix = key + "="
    let plen = len(prefix)
    let total = lineCount(content)
    let i = 0
    while i < total {
        let line = getLine(content, i)
        if len(line) >= plen {
            if substring(line, 0, plen) == prefix {
                emit _trimHead(_trimTail(substring(line, plen, len(line))))
            }
        }
        i = i + 1
    }
    emit ""
}

// freedesktop spec key: DesktopNames=a;b;c — first entry wins for
// XDG_CURRENT_DESKTOP / XDG_SESSION_DESKTOP.
func _firstDesktopName(v) {
    let out = ""
    let i = 0
    while i < len(v) {
        let c = v[i]
        if c == ";" { break }
        out = out + c
        i = i + 1
    }
    emit _trimHead(_trimTail(out))
}

func buildSessions() {
    let s = structNew()
    let count = 1
    s = setField(s, "count", "1")
    let SESS_DIR = "/usr/share/wayland-sessions"
    s = setField(s, "name1", "")
    s = setField(s, "exec1", "")
    s = setField(s, "desk1", "")
    s = setField(s, "name2", "")
    s = setField(s, "exec2", "")
    s = setField(s, "desk2", "")
    s = setField(s, "name3", "")
    s = setField(s, "exec3", "")
    s = setField(s, "desk3", "")
    let entries = exec("ls -1A " + SESS_DIR + " 2>/dev/null")
    if len(entries) == 0 {
        emit s
    }
    let total = lineCount(entries)
    let i = 0
    while i < total && count < 4 {
        let f = getLine(entries, i)
        if len(f) > 8 {
            if substring(f, len(f) - 8, len(f)) == ".desktop" {
                let content = readFile(SESS_DIR + "/" + f)
                // freedesktop: Hidden (deleted-by-user) and NoDisplay both
                // mean "don't show this entry in a picker".
                if _isTruthy(_desktopKey(content, "Hidden")) == 1 {
                    i = i + 1
                    continue
                }
                if _isTruthy(_desktopKey(content, "NoDisplay")) == 1 {
                    i = i + 1
                    continue
                }
                // TryExec: skip the entry when its binary is unavailable.
                let tryExec = _desktopKey(content, "TryExec")
                if len(tryExec) > 0 {
                    let found = exec("command -v " + _shellQuote(tryExec) + " 2>/dev/null")
                    if len(_trimTail(found)) == 0 {
                        i = i + 1
                        continue
                    }
                }
                let name = _desktopKey(content, "Name")
                let exec = _stripFieldCodes(_desktopKey(content, "Exec"))
                let desk = _firstDesktopName(_desktopKey(content, "DesktopNames"))
                if len(name) > 0 && len(exec) > 0 {
                    count = count + 1
                    if count == 2 {
                        s = setField(s, "name1", name)
                        s = setField(s, "exec1", exec)
                        s = setField(s, "desk1", desk)
                    } else if count == 3 {
                        s = setField(s, "name2", name)
                        s = setField(s, "exec2", exec)
                        s = setField(s, "desk2", desk)
                    } else {
                        s = setField(s, "name3", name)
                        s = setField(s, "exec3", exec)
                        s = setField(s, "desk3", desk)
                    }
                }
            }
        }
        i = i + 1
    }
    s = setField(s, "count", toStr(count))
    emit s
}

func sessionCount(s) {
    emit toInt(getField(s, "count"))
}

func sessionName(s, i) {
    if i == 0 { emit "Login shell" }
    let k = "name" + toStr(i)
    emit getField(s, k)
}

// Session DesktopNames (first entry); "" when the entry doesn't set it.
func sessionDesktop(s, i) {
    let k = "desk" + toStr(i)
    emit getField(s, k)
}

// Session command handed to axon-pam. "" means tty login shell.
func sessionExec(s, i) {
    if i == 0 { emit "" }
    let k = "exec" + toStr(i)
    emit getField(s, k)
}
