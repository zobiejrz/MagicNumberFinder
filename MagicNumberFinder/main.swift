import Foundation

// MARK: - Bitboard Helpers

@inline(__always)
func popcount(_ x: UInt64) -> Int {
    return x.nonzeroBitCount
}

@inline(__always)
func lsb(_ bb: UInt64) -> UInt64 {
    return bb & (~bb + 1)
}

func squareIndex(file: Int, rank: Int) -> Int {
    return rank * 8 + file
}

func squareName(_ sq: Int) -> String {
    let file = "abcdefgh"[sq & 7]
    let rank = "12345678"[sq >> 3]
    return "\(file)\(rank)"
}

extension String {
    subscript(i: Int) -> Character {
        return self[index(startIndex, offsetBy: i)]
    }
}

// MARK: - Masks

func rookMask(forSquare sq: Int) -> UInt64 {
    let file = sq & 7
    let rank = sq >> 3
    var mask: UInt64 = 0
    
    for f in 0..<8 where f != file {
        mask |= 1 << squareIndex(file: f, rank: rank)
    }
    for r in 0..<8 where r != rank {
        mask |= 1 << squareIndex(file: file, rank: r)
    }
    return mask
}

func bishopMask(forSquare sq: Int) -> UInt64 {
    let file = sq & 7
    let rank = sq >> 3
    var mask: UInt64 = 0
    
    var f = file + 1, r = rank + 1
    while f < 7 && r < 7 {
        mask |= 1 << squareIndex(file: f, rank: r)
        f += 1; r += 1
    }
    f = file - 1; r = rank - 1
    while f > 0 && r > 0 {
        mask |= 1 << squareIndex(file: f, rank: r)
        f -= 1; r -= 1
    }
    
    f = file + 1; r = rank - 1
    while f < 7 && r > 0 {
        mask |= 1 << squareIndex(file: f, rank: r)
        f += 1; r -= 1
    }
    f = file - 1; r = rank + 1
    while f > 0 && r < 7 {
        mask |= 1 << squareIndex(file: f, rank: r)
        f -= 1; r += 1
    }
    return mask
}

// MARK: - Attack Generators

func slidingRookAttacks(square: Int, blockers: UInt64) -> UInt64 {
    let file0 = square & 7
    let rank0 = square >> 3
    var attacks: UInt64 = 0
    
    for f in (file0+1)..<8 {
        let sq = squareIndex(file: f, rank: rank0)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
    }
    for f in stride(from: file0-1, through: 0, by: -1) {
        let sq = squareIndex(file: f, rank: rank0)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
    }
    for r in (rank0+1)..<8 {
        let sq = squareIndex(file: file0, rank: r)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
    }
    for r in stride(from: rank0-1, through: 0, by: -1) {
        let sq = squareIndex(file: file0, rank: r)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
    }
    return attacks
}

func slidingBishopAttacks(square: Int, blockers: UInt64) -> UInt64 {
    let file0 = square & 7
    let rank0 = square >> 3
    var attacks: UInt64 = 0
    
    var f = file0 + 1, r = rank0 + 1
    while f < 8 && r < 8 {
        let sq = squareIndex(file: f, rank: r)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
        f += 1; r += 1
    }
    f = file0 - 1; r = rank0 + 1
    while f >= 0 && r < 8 {
        let sq = squareIndex(file: f, rank: r)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
        f -= 1; r += 1
    }
    f = file0 + 1; r = rank0 - 1
    while f < 8 && r >= 0 {
        let sq = squareIndex(file: f, rank: r)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
        f += 1; r -= 1
    }
    f = file0 - 1; r = rank0 - 1
    while f >= 0 && r >= 0 {
        let sq = squareIndex(file: f, rank: r)
        attacks |= 1 << sq
        if blockers & (1 << sq) != 0 { break }
        f -= 1; r -= 1
    }
    return attacks
}

// MARK: - Magic Search

func indexToSubset(_ index: Int, mask: UInt64) -> UInt64 {
    var subset: UInt64 = 0
    var m = mask
    var bit = 0
    var i = index
    while m != 0 {
        let lsb = lsb(m)
        if (i & (1 << bit)) != 0 {
            subset |= lsb
        }
        m &= m - 1
        bit += 1
    }
    return subset
}

func randomCandidate() -> UInt64 {
    return UInt64.random(in: .min ... .max)
    & UInt64.random(in: .min ... .max)
    & UInt64.random(in: .min ... .max)
}

func testMagic(
    candidate: UInt64,
    relevantBits: Int,
    occupancies: [UInt64],
    attacks: [UInt64]
) -> Bool {
    let tableSize = 1 << relevantBits
    var used = [UInt64](repeating: 0, count: tableSize)
    
    for i in 0..<tableSize {
        let index = Int((occupancies[i] &* candidate) >> (64 - relevantBits))
        if used[index] == 0 {
            used[index] = attacks[i]
        } else if used[index] != attacks[i] {
            return false
        }
    }
    return true
}

func findMagic(
    square: Int,
    maskForSquare: (Int) -> UInt64,
    slidingAttacks: (Int, UInt64) -> UInt64
) -> UInt64 {
    let mask = maskForSquare(square)
    let relevantBits = popcount(mask)
    let subsetCount = 1 << relevantBits
    
    var occupancies = [UInt64]()
    var attacks = [UInt64]()
    for i in 0..<subsetCount {
        let subset = indexToSubset(i, mask: mask)
        occupancies.append(subset)
        attacks.append(slidingAttacks(square, subset))
    }
    
    var attempts = 0
    while true {
        let candidate = randomCandidate()
        attempts += 1
        if testMagic(
            candidate: candidate,
            relevantBits: relevantBits,
            occupancies: occupancies,
            attacks: attacks
        ) {
            log("  ✔ Found after \(attempts) attempts")
            return candidate
        }
        if attempts % 1_000_000 == 0 {
            log("  … \(attempts / 1_000_000)M attempts tried, still searching")
        }
    }
}

// MARK: - CLI Main (runs automatically in top-level Swift)

func log(_ message: String) {
    fputs(message + "\n", stderr)
}

print("static let rookMagics: [UInt64] = [")
for sq in 0..<64 {
    log("Finding rook magic for \(squareName(sq))...")
    let magic = findMagic(square: sq,
                          maskForSquare: rookMask(forSquare:),
                          slidingAttacks: slidingRookAttacks)
    print("    0x\(String(magic, radix: 16)),")
}
print("]\n")

print("static let bishopMagics: [UInt64] = [")
for sq in 0..<64 {
    log("Finding bishop magic for \(squareName(sq))...")
    let magic = findMagic(square: sq,
                          maskForSquare: bishopMask(forSquare:),
                          slidingAttacks: slidingBishopAttacks)
    print("    0x\(String(magic, radix: 16)),")
}
print("]")
