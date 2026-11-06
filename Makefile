.PHONY: sim vectors model wave clean log synth
# Usage:  make sim      (generate vectors, compile with Icarus Verilog, run)
#         make log      (same as sim, and saves the output to docs/sim_log.txt)
#         make synth    (Yosys synthesis, saves the report to docs/synth_report.txt)
#         make wave     (open the waveform in GTKWave)
#         make model    (check the Python model against hashlib)
#         make clean
sim: vectors
	iverilog -g2012 -Wall -I sim -o sim/sha3_tb.vvp rtl/keccak_round.v rtl/sha3_256.v tb/tb_sha3_256.v
	vvp sim/sha3_tb.vvp

log: vectors
	mkdir -p docs
	iverilog -g2012 -Wall -I sim -o sim/sha3_tb.vvp rtl/keccak_round.v rtl/sha3_256.v tb/tb_sha3_256.v
	vvp sim/sha3_tb.vvp | tee docs/sim_log.txt

synth:
	mkdir -p docs
	yosys -q -p "read_verilog rtl/keccak_round.v rtl/sha3_256.v; synth -top sha3_256 -flatten; tee -o docs/synth_report.txt stat"
	cat docs/synth_report.txt

vectors:
	python3 model/gen_vectors.py

model:
	python3 model/check_model.py
	python3 model/rtl_mirror.py

wave:
	gtkwave sim/sha3_256.vcd &

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.mem sim/*.vh
