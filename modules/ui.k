// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/modules/ui.k — Axon's TUI rendering: login box + session picker.

module axon_ui

import "k:ansi"


func _repeat(s, n) {
    let out = ""
    let i = 0
    while i < n {
        out = out + s
        i = i + 1
    }
    emit out
}

func _hr() { emit _repeat("-", 56) }

func _line(s) {
    let INNER = 56
    let pad = (INNER - len(s)) / 2
    if pad < 0 { pad = 0 }
    emit "|" + _repeat(" ", pad) + s + _repeat(" ", INNER - pad - len(s)) + "|"
}

func _lineNet(s) { emit "|" + s + _repeat(" ", 56 - len(s)) + "|" }

func _padTo(s, n) {
    if len(s) >= n { emit substring(s, 0, n) }
    emit s + _repeat(" ", n - len(s))
}

// Render the login box on top of whatever the backdrop painted. In practice
// this is ~600 bytes of ANSI per frame, not the 76 KB the full-screen frame
// costs, so the pty buffer stays unblocked between background sweeps.
func drawLogin(cols, rows, user, sessName, status) {
    let left = (cols - 58) / 2
    if left < 0 { left = 0 }
    let row = (rows - 11) / 2
    if row < 1 { row = 1 }
    let top = row

    print(cursorTo(top, left + 1))
    print("+" + _hr() + "+")
    print(cursorTo(top + 1, left + 1))
    print(_line(bold("Axon Display Manager")))
    print(cursorTo(top + 2, left + 1))
    print(_line("for KryptOS"))
    print(cursorTo(top + 3, left + 1))
    print(_line(""))
    print(cursorTo(top + 4, left + 1))
    print(_lineNet("  Username: [" + inverse(_padTo(user, 26)) + "]"))
    print(cursorTo(top + 5, left + 1))
    print(_line(""))
    print(cursorTo(top + 6, left + 1))
    print(_lineNet("  Session:  [ < " + _padTo(sessName, 22) + " > ]  (TAB/arrows)"))
    print(cursorTo(top + 7, left + 1))
    print(_line(""))
    print(cursorTo(top + 8, left + 1))
    print(_lineNet("  [ Enter: log in ]"))
    print(cursorTo(top + 9, left + 1))
    print("+" + _hr() + "+")
    if len(status) > 0 {
        print(cursorTo(top + 10, left + 1))
        print(dim("  " + status))
    }
    emit 1
}
