// Copyright 2026 The Krypton Authors.
// Licensed under the Apache License, Version 2.0 (see LICENSE or
// http://www.apache.org/licenses/LICENSE-2.0).
// PAM owns both credential verification and the lifetime of the session.

module greeter_auth

// sh-safe single-quoting: 'it'\''s'
func shellQuote(s) {
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

func authSession(user, mode, sessionExec) {
    if len(sessionExec) > 0 {
        emit toInt(shellRun("exec /usr/bin/python3 -I /usr/local/libexec/axon-pam " + shellQuote(user) + " " + shellQuote(mode) + " " + shellQuote(sessionExec)))
    }
    emit toInt(shellRun("exec /usr/bin/python3 -I /usr/local/libexec/axon-pam " + shellQuote(user) + " " + shellQuote(mode)))
}
