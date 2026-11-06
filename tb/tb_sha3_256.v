// -----------------------------------------------------------------------------
// Self-checking testbench for sha3_256
//  * Loads vectors made by model/gen_vectors.py (expected digests come from hashlib)
//  * Random gaps before each input block and random back-pressure on the output
//  * Unused bytes of the last block are filled with random garbage (core must ignore them)
//  * Checks that the digest stays stable while out_ready is low
//  * Measures latency (block accepted -> digest visible)
// Run from the project root:   make sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "vec_params.vh"          // defines NVEC and MSGBYTES

module tb_sha3_256;

    reg          clk = 0;
    reg          rst_n = 0;
    reg          in_valid = 0;
    reg  [1087:0] in_data = 0;
    reg  [7:0]   in_bytes = 0;
    reg          in_last = 0;
    wire         in_ready;
    wire         out_valid;
    reg          out_ready = 0;
    wire [255:0] out_data;

    sha3_256 dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready),
        .in_data(in_data), .in_bytes(in_bytes), .in_last(in_last),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data)
    );

    always #5 clk = ~clk;

    // ---- test vectors ----------------------------------------------------------
    reg [7:0]  msg_mem [0:`MSGBYTES-1];
    reg [15:0] len_mem [0:`NVEC-1];
    reg [31:0] off_mem [0:`NVEC-1];
    reg [7:0]  exp_mem [0:`NVEC*32-1];

    initial begin
        $readmemh("sim/vec_msg.mem", msg_mem);
        $readmemh("sim/vec_len.mem", len_mem);
        $readmemh("sim/vec_off.mem", off_mem);
        $readmemh("sim/vec_exp.mem", exp_mem);
    end

    // ---- bookkeeping -----------------------------------------------------------
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    integer errors = 0;
    integer passed = 0;

    // ---- monitor: digest must be held stable while out_ready is low ------------
    reg          ov_prev = 0, or_prev = 0;
    reg [255:0]  od_prev = 0;
    always @(posedge clk) begin
        if (ov_prev && !or_prev) begin
            if (!out_valid || (out_data !== od_prev)) begin
                errors = errors + 1;
                $display("ERROR @%0t: out_valid/out_data changed while out_ready was low", $time);
            end
        end
        ov_prev <= out_valid;
        or_prev <= out_ready;
        od_prev <= out_data;
    end

    // ---- tasks -----------------------------------------------------------------
    integer accept_cyc = 0;

    task send_block;
        input [1087:0] d;
        input [7:0]    n;
        input          last;
        begin
            repeat ({$random} % 4) @(posedge clk);      // random idle gap (0..3 cycles)
            #1;
            in_valid = 1; in_data = d; in_bytes = n; in_last = last;
            @(posedge clk);
            while (!in_ready) @(posedge clk);           // accepted on the edge where in_ready was 1
            accept_cyc = cyc;
            #1;
            in_valid = 0; in_last = 0;
        end
    endtask

    task wait_digest;
        output [255:0] dg;
        reg got_it;
        begin
            got_it = 0;
            while (!got_it) begin
                #1;
                out_ready = ({$random} % 4) != 0;       // random back-pressure
                @(posedge clk);
                if (out_valid && out_ready) begin
                    got_it = 1;
                    dg = out_data;
                end
            end
            #1;
            out_ready = 0;
        end
    endtask

    // ---- main test -------------------------------------------------------------
    integer k, b, i, j, L, off, nblocks, lastn, lat;
    reg [1087:0] blk;
    reg [255:0]  got;
    reg          ok;

    initial begin
        $dumpfile("sim/sha3_256.vcd");
        $dumpvars(0, tb_sha3_256);

        repeat (3) @(posedge clk);
        #1 rst_n = 1;
        @(posedge clk);

        // --- latency measurement: empty message, out_ready held high ---
        blk = 0;
        send_block(blk, 8'd0, 1'b1);
        out_ready = 1;
        @(posedge clk);
        while (!out_valid) @(posedge clk);
        lat = cyc - accept_cyc;
        #1 out_ready = 0;
        $display("Latency, single-block message: %0d clock cycles (block accepted -> digest valid)", lat);

        // --- all vectors ---
        for (k = 0; k < `NVEC; k = k + 1) begin
            L   = len_mem[k];
            off = off_mem[k];
            nblocks = (L == 0) ? 1 : (L + 135) / 136;
            for (b = 0; b < nblocks; b = b + 1) begin
                lastn = (b == nblocks - 1) ? ((L == 0) ? 0 : L - 136 * (nblocks - 1)) : 136;
                for (i = 0; i < 136; i = i + 1) begin
                    if (i < lastn) blk[8*i +: 8] = msg_mem[off + 136*b + i];
                    else           blk[8*i +: 8] = $random;     // garbage: must be ignored
                end
                send_block(blk, lastn[7:0], (b == nblocks - 1));
            end
            wait_digest(got);
            ok = 1;
            for (j = 0; j < 32; j = j + 1)
                if (got[8*j +: 8] !== exp_mem[k*32 + j]) ok = 0;
            if (ok) passed = passed + 1;
            else begin
                errors = errors + 1;
                $display("FAIL: vector %0d (length %0d bytes)", k, L);
            end
        end

        $display("--------------------------------------------------");
        $display("Vectors passed: %0d / %0d,  other errors: %0d", passed, `NVEC, errors - (`NVEC - passed));
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $display("--------------------------------------------------");
        $finish;
    end

    // watchdog
    initial begin
        #400_000_000;
        $display("TIMEOUT: simulation hung (check handshakes)");
        $finish;
    end

endmodule
