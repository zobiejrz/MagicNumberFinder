import Foundation
import zBitboard

// --------------------
// Masks & sliding
// --------------------

func rookMask(forSquare sq: Square) -> Bitboard {
    let file0 = sq.rawValue & 7
    let rank0 = sq.rawValue >> 3
    
    var mask = Bitboard.empty
    
    // directions as (dx, dy): East, West, North, South
    let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    
    for (dx, dy) in dirs {
        var f = file0 + dx
        var r = rank0 + dy
        while f >= 0 && f <= 7 && r >= 0 && r <= 7 {
            // if we reached an edge square, stop and do NOT add it to the mask.
            if (dx == 1 && f == 7) ||     // moving east, stop when you hit file h (don't include h)
                (dx == -1 && f == 0) ||    // moving west, stop when you hit file a (don't include a)
                (dy == 1  && r == 7) ||    // moving north, stop when you hit rank 8 (don't include 8)
                (dy == -1 && r == 0) {     // moving south, stop when you hit rank 1 (don't include 1)
                break
            }
            mask |= Bitboard.squareMask(Square(rawValue: (r*8) + f)!)
            f += dx
            r += dy
        }
    }
    return mask
}

func bishopMask(forSquare sq: Square) -> Bitboard {
    let file0 = sq.rawValue & 7
    let rank0 = sq.rawValue >> 3
    
    var mask = Bitboard.empty
    
    // diagonal directions: NE, NW, SE, SW
    let dirs = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
    
    for (dx, dy) in dirs {
        var f = file0 + dx
        var r = rank0 + dy
        while f >= 0 && f <= 7 && r >= 0 && r <= 7 {
            // stop before the edge square
            if f == 0 || f == 7 || r == 0 || r == 7 {
                break
            }
            mask |= Bitboard.squareMask(Square(rawValue: (r*8) + f)!)//bit(squareIndex(file: f, rank: r))
            f += dx
            r += dy
        }
    }
    return mask
}

// MARK: - Attack Generators

func slidingRookAttacks(at sq: Square, blockers: Bitboard = Bitboard.empty) -> Bitboard {
    let file0 = sq.rawValue & 7
    let rank0 = sq.rawValue >> 3
    
    var attacks = Bitboard.empty
    
    let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    for (dx, dy) in dirs {
        var f = file0 + dx
        var r = rank0 + dy
        while f >= 0 && f <= 7 && r >= 0 && r <= 7 {
            let s = Square(rawValue: (r*8) + f)!
            attacks |= Bitboard.squareMask(s)
            if (blockers & Bitboard.squareMask(s)) != 0 {
                // hit a blocker — include it and stop this ray
                break
            }
            f += dx
            r += dy
        }
    }
    
    return attacks
}

func slidingBishopAttacks(at sq: Square, blockers: Bitboard = Bitboard.empty) -> Bitboard {
    let file0 = sq.rawValue & 7
    let rank0 = sq.rawValue >> 3
    
    var attacks = Bitboard.empty
    
    let dirs = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
    for (dx, dy) in dirs {
        var f = file0 + dx
        var r = rank0 + dy
        while f >= 0 && f <= 7 && r >= 0 && r <= 7 {
            let s = Square(rawValue: (r*8) + f)!
            attacks |= Bitboard.squareMask(s)
            if (blockers & Bitboard.squareMask(s)) != 0 {
                break // include blocker and stop
            }
            f += dx
            r += dy
        }
    }
    
    return attacks
}

// --------------------
// Subset helpers
// --------------------

/// Convert an index in [0 .. 2^N) into a subset bitboard of `mask`.
/// The ordering of mask bits is low-to-high by scanning mask's set bits in ascending square order.
func indexToSubset(_ index: Int, mask: Bitboard) -> Bitboard {
    var subset: Bitboard = 0
    var m = mask
    var bit = 0
    // iterate each set-bit in mask in ascending order
    while m != 0 {
        let lsb = m & (~m + 1)
        if (index & (1 << bit)) != 0 {
            subset |= lsb
        }
        m &= m - 1
        bit += 1
    }
    return subset
}

// --------------------
// Magic search
// --------------------

func randomCandidate() -> UInt64 {
    // bias to sparse numbers: AND multiple randoms
    return UInt64.random(in: UInt64.min...UInt64.max)
    & UInt64.random(in: UInt64.min...UInt64.max)
    & UInt64.random(in: UInt64.min...UInt64.max)
}

func testMagic(
    candidate: UInt64,
    relevantBits: Int,
    occupancies: [Bitboard],
    attacks: [Bitboard]
) -> Bool {
    let tableSize = 1 << relevantBits
    var used = [Bitboard](repeating: 0, count: tableSize)
    
    let shift = 64 - relevantBits
    for i in 0..<tableSize {
        // cast to UInt64 for wrapping multiply
        let occ = occupancies[i]
        let idx = Int((occ &* Bitboard(candidate)) >> UInt64(shift))
        if used[idx] == 0 {
            used[idx] = attacks[i]
        } else if used[idx] != attacks[i] {
            return false // collision
        }
    }
    return true
}

func findMagic(
    square: Square,
    maskForSquare: (Square) -> Bitboard,
    slidingAttacks: (Square, Bitboard) -> Bitboard
) -> UInt64 {
    let mask = maskForSquare(square)
    let relevantBits = mask.nonzeroBitCount
    let subsetCount = 1 << relevantBits
    
    var occupancies = [Bitboard]()
    var attacks = [Bitboard]()
    occupancies.reserveCapacity(subsetCount)
    attacks.reserveCapacity(subsetCount)
    
    for i in 0..<subsetCount {
        let subset = indexToSubset(i, mask: mask)
        occupancies.append(subset)
        attacks.append(slidingAttacks(square, subset))
    }
    
    var attempts = 0
    while true {
        let candidate = randomCandidate()
        attempts += 1
        if testMagic(candidate: candidate, relevantBits: relevantBits, occupancies: occupancies, attacks: attacks) {
            log("  ✔ Found after \(attempts) attempts")
            return candidate
        }
        if attempts % 1_000_000 == 0 {
            log("  … \(attempts / 1_000_000)M attempts tried, still searching")
        }
    }
}

// --------------------
// logging helpers
// --------------------

func log(_ message: String) {
    fputs(message + "\n", stderr)
}

// --------------------
// CLI main
// --------------------

print("static let rookMagics: [UInt64] = [")

for sq in Square.allCases {
    log("Finding rook magic for \(sq)...")
    let magic = findMagic(square: sq, maskForSquare: rookMask(forSquare:), slidingAttacks: slidingRookAttacks)
    print("    0x\(String(magic, radix: 16)),")
}
print("]\n")

print("static let bishopMagics: [UInt64] = [")

for sq in Square.allCases {
    log("Finding bishop magic for \(sq)...")
    let magic = findMagic(square: sq, maskForSquare: bishopMask(forSquare:), slidingAttacks: slidingBishopAttacks)
    print("    0x\(String(magic, radix: 16)),")
}
print("]")
