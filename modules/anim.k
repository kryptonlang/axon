// Copyright (C) 2026 Brian Thompson (krypton-lang) — All Rights Reserved.
// axon/modules/anim.k — built-in full-screen backdrops (pure Krypton).
//
// Axon's built-in backdrop animation setting:
// deterministic full-screen frames drawn straight to the tty — no external
// binary required. Each frame is a pure function of (cols, rows, frame), so
// nothing carries over between calls and no PRNG state is needed.

module axon_anim

import "k:ansi"

let GLYPHS = "0123456789ABCDEFGHIJKLMNPQRSTUVWXYZ$#@%&"

// Cheap deterministic mix — no RNG required.
func _mix(x) {
    x = bitXor(x, shr(x, 13))
    x = x * 1103515245 + 12345
    x = bitXor(x, shr(x, 16))
    emit x
}

// Rain head row for a column moves downward with frame; classic matrix feel.
func _rainHead(c, rows, f) {
    emit (_mix(c * 911 + f * 7) % ((rows + 12) * 2))
}

func _glyph(c, r, f) {
    let i = _mix(c * 31 + r * 17 + f * 13) % len(GLYPHS)
    emit GLYPHS[i]
}

// ── colormix: rotating hue gradient, rotating hue sweep ──
// Map hue h in [0,255] onto the 6x6x6 xterm color cube (indices 16..231).
func _hue(h) {
    h = h % 256
    let sect = (h * 6) / 256          // 0..5 sector of the wheel
    let frac = ((h * 6) % 256) * 5 / 255 // 0..5 ramp within the sector
    let ri = 0
    let gi = 0
    let bi = 0
    if sect == 0 { ri = 5; gi = frac; bi = 0 }
    else if sect == 1 { ri = 5 - frac; gi = 5; bi = 0 }
    else if sect == 2 { ri = 0; gi = 5; bi = frac }
    else if sect == 3 { ri = 0; gi = 5 - frac; bi = 5 }
    else if sect == 4 { ri = frac; gi = 0; bi = 5 }
    else { ri = 5; gi = 0; bi = 5 - frac }
    emit 16 + 36 * ri + 6 * gi + bi
}

func colormixFrame(cols, rows, f) {
    let sb = cursorHome()
    let row = 0
    while row < rows {
        let col = 0
        while col < cols {
            let idx = _hue(row + col * 2 + f * 3)
            sb = sb + bg256(idx, " ")
            col = col + 1
        }
        row = row + 1
    }
    emit sb
}

// ── matrix: bright head + fading trail per column ───────────────────────────
func matrixFrame(cols, rows, f) {
    let sb = cursorHome()
    let row = 0
    while row < rows {
        let col = 0
        while col < cols {
            let head = _rainHead(col, rows, f)
            let d = head - row
            if d == 0 {
                sb = sb + brightGreen(_glyph(col, row, f))
            } else if d > 0 && d <= 4 {
                sb = sb + green(_glyph(col, row, f))
            } else if d > 4 && d <= 12 {
                sb = sb + gray(_glyph(col, row, f))
            } else {
                sb = sb + " "
            }
            col = col + 1
        }
        row = row + 1
    }
    emit sb
}

// ── blank: plain dark background, useful for debugging the overlay ────────
func blankFrame(cols, rows, f) {
    let sb = cursorHome()
    let row = 0
    while row < rows {
        let col = 0
        while col < cols {
            sb = sb + " "
            col = col + 1
        }
        row = row + 1
    }
    emit sb
}
