// -----------------------------------------------------------------------------
// sha3_256.v : SHA3-256 hash core
//
//  * Rate = 1088 bits (136 bytes). The message is fed in blocks of 136 bytes.
//  * One Keccak round per clock -> 24 clocks per block.
//  * Padding (SHA-3 rule 0x06 ... 0x80) is done INSIDE the core.
//
// Interface (valid/ready on both sides)
//   in_valid/in_ready : send one block
//   in_data  [1087:0] : byte i of the block is in_data[8*i +: 8]  (byte 0 = first message byte)
//   in_bytes [7:0]    : number of valid message bytes in this block
//                        - for blocks that are NOT the last one it must be 136
//                        - for the last block it can be 0..136
//   in_last           : 1 on the last block of the message
//   out_valid/out_ready : digest handshake
//   out_data [255:0]  : byte j of the digest is out_data[8*j +: 8]  (byte 0 = first digest byte)
//
// Special case: if the last block is completely full (in_bytes == 136) the
// padding needs a whole extra block, which the core adds by itself.
// -----------------------------------------------------------------------------
module sha3_256 (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          in_valid,
    output wire          in_ready,
    input  wire [1087:0] in_data,
    input  wire [7:0]    in_bytes,
    input  wire          in_last,

    output wire          out_valid,
    input  wire          out_ready,
    output wire [255:0]  out_data
);

    localparam [1:0] S_IDLE = 2'd0,   // waiting for a block
                     S_RUN  = 2'd1,   // doing the 24 rounds
                     S_DONE = 2'd2;   // digest ready, waiting for out_ready

    reg [1:0]    st;
    reg [1599:0] state;
    reg [4:0]    round;
    reg          last_r;      // the block being processed is the last one
    reg          extra_r;     // a separate all-padding block is still to be absorbed

    // ---- padding of the incoming block --------------------------------------
    // Only the last block (with fewer than 136 bytes) is padded here.
    function [1087:0] pad_block;
        input [1087:0] d;
        input [7:0]    n;
        input          last;
        integer        i;
        reg [7:0]      b;
        begin
            for (i = 0; i < 136; i = i + 1) begin
                b = d[8*i +: 8];
                if (last && n < 8'd136) begin
                    if (i < n)       b = d[8*i +: 8];     // real message byte
                    else if (i == n) b = 8'h06;           // SHA-3 domain bits + first '1'
                    else             b = 8'h00;
                    if (i == 135)    b = b ^ 8'h80;       // final '1' of the padding
                end
                pad_block[8*i +: 8] = b;
            end
        end
    endfunction

    // Extra block used when the last message block was exactly 136 bytes
    localparam [1087:0] PAD_ONLY = {8'h80, 1072'b0, 8'h06};

    wire [1087:0] blk = pad_block(in_data, in_bytes, in_last);

    // ---- one Keccak round ---------------------------------------------------
    wire [1599:0] round_out;
    keccak_round u_round (
        .state_in  (state),
        .round_idx (round),
        .state_out (round_out)
    );

    assign in_ready  = (st == S_IDLE);
    assign out_valid = (st == S_DONE);
    assign out_data  = state[255:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            state   <= 1600'b0;
            round   <= 5'd0;
            last_r  <= 1'b0;
            extra_r <= 1'b0;
        end else begin
            case (st)
                S_IDLE: begin
                    if (in_valid) begin
                        // absorb: XOR the block into the first 1088 bits of the state
                        state   <= state ^ {512'b0, blk};
                        last_r  <= in_last;
                        extra_r <= in_last && (in_bytes == 8'd136);
                        round   <= 5'd0;
                        st      <= S_RUN;
                    end
                end

                S_RUN: begin
                    round <= round + 5'd1;
                    if (round == 5'd23) begin
                        if (extra_r) begin
                            // absorb the extra padding block and permute again
                            state   <= round_out ^ {512'b0, PAD_ONLY};
                            extra_r <= 1'b0;
                            round   <= 5'd0;
                        end else begin
                            state <= round_out;
                            st    <= last_r ? S_DONE : S_IDLE;
                        end
                    end else begin
                        state <= round_out;
                    end
                end

                S_DONE: begin
                    if (out_ready) begin
                        state  <= 1600'b0;     // fresh state for the next message
                        last_r <= 1'b0;
                        st     <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
