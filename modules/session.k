// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/modules/session.k — spawn the user's session on a fresh PTY.

module axon_session

// Run prog on a new pty (slave side becomes the controlling tty), pumping
// bytes between our tty (fd 0/1) and the master until the child exits.
// The greeter's tty is in VMIN=0 polling mode, so fdReadN returns
// immediately with 0 when nothing is pending — no O_NONBLOCK needed.
func sessionStart(prog) {
    let master = ptyMaster("/dev/ptmx")
    let slave = ptySlaveName(master)
    let pid = ptyForkExec(slave, prog)

    let running = 1
    while running == 1 {
        let iBuf = bufNew(4096)
        let inN = fdReadN(0, iBuf, 4096)
        if inN > 0 {
            fdWrite(master, iBuf, inN)
        }
        let oBuf = bufNew(4096)
        let outN = fdReadN(master, oBuf, 4096)
        if outN > 0 {
            fdWrite(1, oBuf, outN)
        }
        if procAlive(pid) == 0 { running = 0 }
        if inN <= 0 && outN <= 0 { sleepUs(0, 20000) }
    }
    fdClose(master)
    emit 0
}
