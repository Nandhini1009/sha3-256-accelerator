import hashlib, random, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from keccak_ref import sha3_256, RC
random.seed(1)
assert RC[0] == 1 and RC[1] == 0x8082 and RC[23] == 0x8000000080008008
bad = 0
for L in list(range(0, 300)) + [rand for rand in (random.randint(300, 1000) for _ in range(50))]:
    m = bytes(random.getrandbits(8) for _ in range(L))
    if sha3_256(m) != hashlib.sha3_256(m).digest():
        bad += 1; print("MISMATCH len", L)
print("empty:", sha3_256(b"").hex())
print("abc  :", sha3_256(b"abc").hex())
print("model check:", "PASS" if bad == 0 else f"FAIL ({bad})")
sys.exit(bad != 0)
