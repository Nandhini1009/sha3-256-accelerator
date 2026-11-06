// -----------------------------------------------------------------------------
// keccak_round.v : ONE round of Keccak-f[1600] (purely combinational)
//
// State = 1600 bits = 25 lanes of 64 bits. Lane number = x + 5*y.
// Byte i of the state sits at state[8*i +: 8]  (so lane k = state[64*k +: 64]).
//
// The five steps of a round:
//   theta : mix each column with its two neighbouring columns (XOR + rotate 1)
//   rho   : rotate every lane by a fixed amount
//   pi    : move lanes to new positions
//   chi   : the only non-linear step (XOR, AND, NOT within each row)
//   iota  : XOR a round constant into lane 0 (so every round is different)
// -----------------------------------------------------------------------------
module keccak_round (
    input  wire [1599:0] state_in,
    input  wire [4:0]    round_idx,   // 0..23
    output wire [1599:0] state_out
);

    // ---- helper functions ---------------------------------------------------
    function [63:0] rol64;
        input [63:0] v;
        input integer n;
        begin
            if (n == 0) rol64 = v;
            else        rol64 = (v << n) | (v >> (64 - n));
        end
    endfunction

    // rotation offset for lane (x + 5*y)
    function integer rot_off;
        input integer lane;
        begin
            case (lane)
                 0: rot_off =  0;  1: rot_off =  1;  2: rot_off = 62;  3: rot_off = 28;  4: rot_off = 27;
                 5: rot_off = 36;  6: rot_off = 44;  7: rot_off =  6;  8: rot_off = 55;  9: rot_off = 20;
                10: rot_off =  3; 11: rot_off = 10; 12: rot_off = 43; 13: rot_off = 25; 14: rot_off = 39;
                15: rot_off = 41; 16: rot_off = 45; 17: rot_off = 15; 18: rot_off = 21; 19: rot_off =  8;
                20: rot_off = 18; 21: rot_off =  2; 22: rot_off = 61; 23: rot_off = 56; 24: rot_off = 14;
                default: rot_off = 0;
            endcase
        end
    endfunction

    // round constant for iota
    function [63:0] rc;
        input [4:0] r;
        begin
            case (r)
                 0: rc = 64'h0000000000000001;  1: rc = 64'h0000000000008082;
                 2: rc = 64'h800000000000808A;  3: rc = 64'h8000000080008000;
                 4: rc = 64'h000000000000808B;  5: rc = 64'h0000000080000001;
                 6: rc = 64'h8000000080008081;  7: rc = 64'h8000000000008009;
                 8: rc = 64'h000000000000008A;  9: rc = 64'h0000000000000088;
                10: rc = 64'h0000000080008009; 11: rc = 64'h000000008000000A;
                12: rc = 64'h000000008000808B; 13: rc = 64'h800000000000008B;
                14: rc = 64'h8000000000008089; 15: rc = 64'h8000000000008003;
                16: rc = 64'h8000000000008002; 17: rc = 64'h8000000000000080;
                18: rc = 64'h000000000000800A; 19: rc = 64'h800000008000000A;
                20: rc = 64'h8000000080008081; 21: rc = 64'h8000000000008080;
                22: rc = 64'h0000000080000001; 23: rc = 64'h8000000080008008;
                default: rc = 64'h0;
            endcase
        end
    endfunction

    // ---- split the state into 25 lanes --------------------------------------
    wire [63:0] a [0:24];
    genvar i, x, y;
    generate
        for (i = 0; i < 25; i = i + 1) begin : g_split
            assign a[i] = state_in[64*i +: 64];
        end
    endgenerate

    // ---- theta ---------------------------------------------------------------
    wire [63:0] c [0:4];   // column parity
    wire [63:0] d [0:4];
    wire [63:0] t [0:24];
    generate
        for (x = 0; x < 5; x = x + 1) begin : g_theta_c
            assign c[x] = a[x] ^ a[x+5] ^ a[x+10] ^ a[x+15] ^ a[x+20];
        end
        for (x = 0; x < 5; x = x + 1) begin : g_theta_d
            assign d[x] = c[(x+4)%5] ^ rol64(c[(x+1)%5], 1);
        end
        for (y = 0; y < 5; y = y + 1) begin : g_theta_y
            for (x = 0; x < 5; x = x + 1) begin : g_theta_x
                assign t[x+5*y] = a[x+5*y] ^ d[x];
            end
        end
    endgenerate

    // ---- rho + pi ------------------------------------------------------------
    wire [63:0] b [0:24];
    generate
        for (y = 0; y < 5; y = y + 1) begin : g_rp_y
            for (x = 0; x < 5; x = x + 1) begin : g_rp_x
                assign b[y + 5*((2*x + 3*y) % 5)] = rol64(t[x+5*y], rot_off(x+5*y));
            end
        end
    endgenerate

    // ---- chi + iota ----------------------------------------------------------
    wire [63:0] o [0:24];
    generate
        for (y = 0; y < 5; y = y + 1) begin : g_chi_y
            for (x = 0; x < 5; x = x + 1) begin : g_chi_x
                if (x == 0 && y == 0) begin : g_lane0
                    assign o[0] = (b[0] ^ ((~b[1]) & b[2])) ^ rc(round_idx);
                end else begin : g_other
                    assign o[x+5*y] = b[x+5*y] ^ ((~b[(x+1)%5 + 5*y]) & b[(x+2)%5 + 5*y]);
                end
            end
        end
    endgenerate

    // ---- pack lanes back into the 1600-bit state -----------------------------
    generate
        for (i = 0; i < 25; i = i + 1) begin : g_pack
            assign state_out[64*i +: 64] = o[i];
        end
    endgenerate

endmodule
