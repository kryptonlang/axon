// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/modules/sessions.k — enumerate display sessions ly-style.
//
// ly scans /usr/share/wayland-sessions/*.desktop and offers one entry per
// file that has both Name= and Exec=. Axon does the same: every .desktop
// entry is appended after the built-in "Login shell" (a tty login), and its
// Exec= command is handed to axon-pam as the third argument. Field codes
// (%U, %f, …) are stripped from Exec=.
//
// The list is resolved once per greeter start; it is not reactive to
// filesystem changes while the greeter is running.

module axon_sessions

let _count = 1
let _name1 = ""
let _exec1 = ""
let _name2 = ""
let _exec2 = ""
let _name3 = ""
let _exec3 = ""

let SESS_DIR = "/usr/share/wayland-sessions"

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

func buildSessions() {
    _count = 1
    _name1 = ""
    _exec1 = ""
    _name2 = ""
    _exec2 = ""
    _name3 = ""
    _exec3 = ""
    let entries = exec("ls -1A " + SESS_DIR + " 2>/dev/null")
    if len(entries) == 0 {
        emit _count
    }
    let total = lineCount(entries)
    let i = 0
    while i < total && _count < 4 {
        let f = getLine(entries, i)
        if len(f) > 8 {
            if substring(f, len(f) - 8, len(f)) == ".desktop" {
                let content = readFile(SESS_DIR + "/" + f)
                let name = _desktopKey(content, "Name")
                let exec = _stripFieldCodes(_desktopKey(content, "Exec"))
                if len(name) > 0 && len(exec) > 0 {
                    _count = _count + 1
                    if _count == 2 {
                        _name1 = name
                        _exec1 = exec
                    } else if _count == 3 {
                        _name2 = name
                        _exec2 = exec
                    } else {
                        _name3 = name
                        _exec3 = exec
                    }
                }
            }
        }
        i = i + 1
    }
    emit _count
}

func sessionCount() {
    emit _count
}

func sessionName(i) {
    if i == 0 { emit "Login shell" }
    else if i == 1 { emit _name1 }
    else if i == 2 { emit _name2 }
    emit _name3
}

// Session command handed to axon-pam. "" means tty login shell.
func sessionExec(i) {
    if i == 0 { emit "" }
    else if i == 1 { emit _exec1 }
    else if i == 2 { emit _exec2 }
    emit _exec3
}
