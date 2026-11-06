.PHONY: sim vectors model wave clean
# Usage:  make sim      (generate vectors, compile with Icarus Verilog, run)
#         make wave     (open the waveform in GTKWave)
#         make model    (check the Python model against hashlib)
#         make clean
sim: vectors
	iverilog -g2012 -Wall -I sim -o sim/sha3_tb.vvp rtl/keccak_round.v rtl/sha3_256.v tb/tb_sha3_256.v
	vvp sim/sha3_tb.vvp

vectors:
	python3 model/gen_vectors.py

model:
	python3 model/check_model.py
	python3 model/rtl_mirror.py

wave:
	gtkwave sim/sha3_256.vcd &

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.mem sim/*.vh
