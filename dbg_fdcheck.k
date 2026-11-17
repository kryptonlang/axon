just run {
    let b = bufNew(16)
    print("start")
    let n = fdReadN(0, b, 4)
    print("n0=" + toStr(n))
    print("b0=" + toStr(bufGetByte(b, 0)))
    print("done")
}
