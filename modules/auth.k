// Copyright 2026 The Krypton Authors.
// Licensed under the Apache License, Version 2.0 (see LICENSE or
// http://www.apache.org/licenses/LICENSE-2.0).
// auth.k — credential check for axon.
//
// v1 strategy: hand the tty over to `su`; it prints its own "Password:"
// prompt, reads (and hides) the password itself, and answers with an exit
// status. The greeter never sees the password — this is deliberately
// password-free in Krypton code until stdlib grows a SHA-512 crypt and
// the PAM/libcrypt FFI (Phase VII) lands.
//
// Contract:  exit code 0 = login accepted, anything else = rejected.

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

// verify(user) -> su's exit code (0 on success).
// Runs with inherited stdio so su reads/prints directly on the tty.
func authVerify(user) {
    let rc = shellRun("su - " + shellQuote(user) + " -s /bin/sh -c true")
    emit toInt(rc)
}
