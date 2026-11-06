"""Readable SHA3-256 reference model (Keccak-f[1600]).
Written to mirror the Verilog design: same lane numbering (lane = x + 5*y),
same rotation table, same round constants, same padding rule.
Checked against Python's hashlib in check_model.py."""

MASK = (1 << 64) - 1

# Rotation offsets, indexed [lane] where lane = x + 5*y
ROT = [
     0,  1, 62, 28, 27,   # y = 0 : x = 0..4
    36, 44,  6, 55, 20,   # y = 1
     3, 10, 43, 25, 39,   # y = 2
    41, 45, 15, 21,  8,   # y = 3
    18,  2, 61, 56, 14,   # y = 4
]

def make_round_constants():
    """24 round constants from the Keccak LFSR (rc(t) in the spec)."""
    def rc_bit(t):
        if t % 255 == 0:
            return 1
        r = 1
        for _ in range(t % 255):
            r <<= 1
            if r & 0x100:
                r ^= 0x171
        return r & 1
    rcs = []
    for rnd in range(24):
        v = 0
        for j in range(7):
            if rc_bit(j + 7 * rnd):
                v |= 1 << ((1 << j) - 1)
        rcs.append(v)
    return rcs

RC = make_round_constants()

def rol(v, n):
    n %= 64
    return ((v << n) | (v >> (64 - n))) & MASK if n else v

def keccak_round(A, rnd):
    # theta
    C = [A[x] ^ A[x+5] ^ A[x+10] ^ A[x+15] ^ A[x+20] for x in range(5)]
    D = [C[(x + 4) % 5] ^ rol(C[(x + 1) % 5], 1) for x in range(5)]
    T = [A[x + 5*y] ^ D[x] for y in range(5) for x in range(5)]
    # rho + pi
    B = [0] * 25
    for x in range(5):
        for y in range(5):
            B[y + 5 * ((2*x + 3*y) % 5)] = rol(T[x + 5*y], ROT[x + 5*y])
    # chi
    O = [0] * 25
    for y in range(5):
        for x in range(5):
            O[x + 5*y] = B[x + 5*y] ^ ((~B[(x+1) % 5 + 5*y] & MASK) & B[(x+2) % 5 + 5*y])
    # iota
    O[0] ^= RC[rnd]
    return O

def keccak_f(A):
    for r in range(24):
        A = keccak_round(A, r)
    return A

RATE = 136  # bytes (1088 bits) for SHA3-256

def pad(msg: bytes) -> bytes:
    n = len(msg)
    padlen = RATE - (n % RATE)
    p = bytearray(msg) + bytearray(padlen)
    p[n] ^= 0x06            # SHA-3 domain bits + first padding 1
    p[-1] ^= 0x80           # last padding bit (if padlen==1, both land on same byte -> 0x86)
    return bytes(p)

def sha3_256(msg: bytes) -> bytes:
    A = [0] * 25
    p = pad(msg)
    for off in range(0, len(p), RATE):
        blk = p[off:off + RATE]
        for i, byte in enumerate(blk):            # byte i -> lane i//8, bit 8*(i%8)
            A[i // 8] ^= byte << (8 * (i % 8))
        A = keccak_f(A)
    out = bytearray()
    for lane in range(4):                          # first 32 bytes = 4 lanes
        out += A[lane].to_bytes(8, "little")
    return bytes(out)
