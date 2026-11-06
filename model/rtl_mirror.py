"""Sanity checks on the Verilog WITHOUT a simulator.
 1. Parse the rotation table and round constants out of rtl/keccak_round.v and
    compare them with the verified Python model (catches typos in the tables).
 2. Cycle-by-cycle Python copy of the sha3_256.v state machine (same states,
    same padding rule, same extra-block case) checked against hashlib.
This does NOT replace running the real Verilog testbench (make sim)."""
import re, os, sys, random, hashlib
sys.path.insert(0, os.path.dirname(__file__))
from keccak_ref import ROT, RC, keccak_round, RATE

root = os.path.join(os.path.dirname(__file__), "..")
src = open(os.path.join(root, "rtl", "keccak_round.v")).read()

# ---- 1. table check ------------------------------------------------------------
rot_body = src[src.index("function integer rot_off"):src.index("endfunction", src.index("function integer rot_off"))]
rot_v = {int(a): int(b) for a, b in re.findall(r"(\d+):\s*rot_off\s*=\s*(\d+);", rot_body)}
assert [rot_v[i] for i in range(25)] == ROT, "rotation table in Verilog differs from model"
rc_body = src[src.index("function [63:0] rc"):src.index("endfunction", src.index("function [63:0] rc"))]
rc_v = {int(a): int(b, 16) for a, b in re.findall(r"(\d+):\s*rc\s*=\s*64'h([0-9A-Fa-f]+);", rc_body)}
assert [rc_v[i] for i in range(24)] == RC, "round constants in Verilog differ from model"
print("table check : rotation offsets (25) and round constants (24) in keccak_round.v match the model")

# ---- 2. state-machine mirror ---------------------------------------------------
def pad_block(d: bytes, n: int, last: bool) -> bytes:       # mirrors function pad_block
    out = bytearray(RATE)
    for i in range(RATE):
        b = d[i]
        if last and n < RATE:
            b = d[i] if i < n else (0x06 if i == n else 0x00)
            if i == RATE - 1:
                b ^= 0x80
        out[i] = b
    return bytes(out)

PAD_ONLY = bytes([0x06]) + bytes(134) + bytes([0x80])

def xor_into(A, blk):
    for i, byte in enumerate(blk):
        A[i // 8] ^= byte << (8 * (i % 8))

def run_core(msg: bytes, rng):
    """Drive the mirrored FSM with back-to-back blocks; return (digest, cycles accept->digest)."""
    nblocks = 1 if len(msg) == 0 else (len(msg) + RATE - 1) // RATE
    A = [0] * 25
    cycles = -1                         # count clock edges AFTER the accept edge (same as the testbench)
    for b in range(nblocks):
        last = b == nblocks - 1
        n = RATE if not last else (0 if len(msg) == 0 else len(msg) - RATE * (nblocks - 1))
        d = bytearray(rng.getrandbits(8) for _ in range(RATE))   # garbage in unused bytes
        d[:n] = msg[RATE * b: RATE * b + n]
        # S_IDLE -> accept edge
        xor_into(A, pad_block(bytes(d), n, last)); extra = last and n == RATE
        cycles += 1
        # S_RUN: 24 rounds, one per clock
        for r in range(24):
            A = keccak_round(A, r); cycles += 1
        if extra:                       # extra padding block absorbed without a new handshake
            xor_into(A, PAD_ONLY)
            for r in range(24):
                A = keccak_round(A, r); cycles += 1
    cycles += 1                         # digest becomes visible on the edge after the last round
    return b"".join(A[k].to_bytes(8, "little") for k in range(4)), cycles

rng = random.Random(7)
lens = [0, 1, 55, 134, 135, 136, 137, 271, 272, 273, 408] + [rng.randint(0, 420) for _ in range(300)]
bad = 0
for L in lens:
    m = bytes(rng.getrandbits(8) for _ in range(L))
    dg, cyc = run_core(m, rng)
    if dg != hashlib.sha3_256(m).digest():
        bad += 1; print("MISMATCH length", L)
_, lat = run_core(b"", rng)
_, lat136 = run_core(bytes(136), rng)
print(f"FSM mirror  : {len(lens)} messages vs hashlib -> {'PASS' if bad == 0 else 'FAIL'}")
print(f"latency     : {lat} cycles for a 1-block message, {lat136} cycles when the last block is exactly 136 bytes (extra padding block)")
sys.exit(bad != 0)
