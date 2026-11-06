"""Generate test vectors for the testbench using Python's hashlib as the golden model.
Writes files into sim/ that the Verilog testbench loads with $readmemh."""
import hashlib, random, os, sys

random.seed(2026)
out = os.path.join(os.path.dirname(__file__), "..", "sim")
os.makedirs(out, exist_ok=True)

vectors = [b"", b"abc"]                                     # NIST-style known messages
for L in [1, 2, 3, 55, 56, 64, 100, 134, 135, 136, 137,     # around the 136-byte block edge
          200, 271, 272, 273, 300, 407, 408, 409, 1000]:
    vectors.append(bytes(random.getrandbits(8) for _ in range(L)))
vectors.append(bytes([0x00] * 136))                         # corner cases: all zeros / all ones
vectors.append(bytes([0xFF] * 136))
vectors.append(bytes([0xFF] * 135))
for _ in range(600):                                        # random lengths and contents
    L = random.randint(0, 420)
    vectors.append(bytes(random.getrandbits(8) for _ in range(L)))

with open(f"{out}/vec_len.mem", "w") as fl, open(f"{out}/vec_off.mem", "w") as fo, \
     open(f"{out}/vec_msg.mem", "w") as fm, open(f"{out}/vec_exp.mem", "w") as fe:
    off = 0
    for m in vectors:
        fl.write(f"{len(m):04x}\n")
        fo.write(f"{off:08x}\n")
        for b in m:
            fm.write(f"{b:02x}\n")
        off += len(m)
        for b in hashlib.sha3_256(m).digest():
            fe.write(f"{b:02x}\n")
    if off == 0:
        fm.write("00\n")
total = max(1, sum(len(m) for m in vectors))
with open(f"{out}/vec_params.vh", "w") as fp:
    fp.write(f"`define NVEC {len(vectors)}\n`define MSGBYTES {total}\n")
print(f"generated {len(vectors)} vectors, {total} message bytes")
