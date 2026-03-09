`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/14/2025 08:09:22 PM
// Design Name: 
// Module Name: scaled_reg_SA_MAC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module scaled_reg_SA_MAC #(
    parameter int N_ROW           = 8,     // DSP slices per SA_MAC_updated
    parameter int D_MATRIX        = 20,    // length of (rstate_ex) and per-output weight vector
    parameter int N_OUT           = 2,     // total number of output nodes (can be large, e.g., 72)
    parameter int WIDTH_WEIGHT    = 17,    // weights bitwidth (matches w_out)
    parameter int WIDTH_STATE_EX  = 25,    // state bitwidth (matches rstate_ex)
    parameter int WIDTH_OUTPUT    = 25
)(
    input  logic                            clk,
    input  logic                            rst,
    input  logic                            start,   // pulse to begin one full dot-product evaluation
    input  logic [WIDTH_STATE_EX-1:0]       rstate_ex [0:D_MATRIX-1],                 // 20 state entries
    input  logic [WIDTH_WEIGHT-1:0]         w_out     [0:N_OUT-1][0:D_MATRIX-1],      // N_OUT x 20
    output logic [WIDTH_OUTPUT-1:0]         out_vec   [0:N_OUT-1],                    // all outputs
    output logic                            out_valid
);

    // ------------------------------------------------------
    // Derived tiling factor: N_ARRAY = ceil(N_OUT / N_ROW)
    // ------------------------------------------------------
    localparam int N_ARRAY = (N_OUT + N_ROW - 1) / N_ROW;
    
    // === Systolic-related timing parameters ===
    localparam int PIPE_PER_HOP = 1;                       // one extra cycle per row hop
    localparam int TAIL         = (N_ROW-1)*PIPE_PER_HOP   // skew tail through the rows
                                  + 2;                     // extra 2 cycles for DSP settle
    localparam int WIDTH_DSP_X = 17;
    
    // -----------------------------
    // Wires into SA_MAC_updated
    // -----------------------------
    logic                               sclr;
    logic [WIDTH_STATE_EX-1:0]          vector_in;

    // Per-array wiring
    logic [WIDTH_DSP_X-1:0]               matrix_in_arr [0:N_ARRAY-1][0:N_ROW-1];
    logic [WIDTH_OUTPUT-1:0]             result_sa_arr [0:N_ARRAY-1][0:N_ROW-1];

    // ------------------------------------------------------
    // Simple FSM to (1) clear accumulators, (2) feed D_MATRIX elems
    // ------------------------------------------------------
    typedef enum logic [1:0] {IDLE, CLEAR, FEED, DONE} state_t;
    state_t state, nxt;
    logic [$clog2(D_MATRIX+TAIL)-1:0] feed_idx; // NEW: widen counter for tail

    logic feed_valid;  // starts one cycle after CLEAR

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            feed_idx   <= '0;
            feed_valid <= 1'b0;
        end else begin
            state <= nxt;
    
            case (state)
                CLEAR: begin
                    feed_idx   <= '0;
                    feed_valid <= 1'b0;  // wait one extra cycle
                end
                FEED: begin
                    feed_valid <= 1'b1;
                    feed_idx   <= feed_idx + 1'b1;  // increment every clock
                end
                default: begin
                    feed_idx   <= '0;
                    feed_valid <= 1'b0;
                end
            endcase
        end
    end

    // Next-state + outputs
    logic sclr_pulse; // NEW: one-cycle pulse, widened later
    always_comb begin
        nxt        = state;
        sclr_pulse = 1'b0;    // NEW
        out_valid  = 1'b0;

        case (state)
            IDLE:  nxt = start ? CLEAR : IDLE;

            CLEAR: begin
                sclr_pulse = 1'b1;   // NEW: single-cycle seed for stretcher
                nxt        = FEED;
            end

            FEED: begin
                sclr_pulse = 1'b0;
                // advance until we've sent D_MATRIX elements + skew tail
                // CHANGED: use TAIL instead of fixed +1
                if (feed_idx == (D_MATRIX + TAIL))
                    nxt = DONE;
                else
                    nxt = FEED;
            end

            DONE: begin
                sclr_pulse = 1'b0;
                out_valid = 1'b1;  // results ready after full feed (with skew)
                nxt       = IDLE;  // hold DONE for one cycle; auto-return
            end

            default: nxt = IDLE;
        endcase
    end

    // -----------------------------------------
    // Drive common state element to all arrays
    // Guard the index to avoid OOB during tail cycles
    // -----------------------------------------
    logic [$clog2(D_MATRIX)-1:0] idx_sel;
    always_comb begin
        idx_sel   = (feed_idx < D_MATRIX) ? feed_idx : (D_MATRIX-1);
        vector_in = rstate_ex[idx_sel];
    end

    // ------------------------------------------------------
    // Feed valid masking: during systolic skew, only row 0 is valid early
    // After j cycles, row j becomes active
    // ------------------------------------------------------
    logic [N_ROW-1:0] feed_valid_mask;
    always_comb begin
      for (int j = 0; j < N_ROW; j++) begin
        feed_valid_mask[j] = (state == FEED) &&
                             (feed_idx >= j) &&            // don't start early on deeper rows
                             ((feed_idx - j) < D_MATRIX);  // stop exactly after last element
      end
    end

    logic [WIDTH_WEIGHT-1:0]     w_sel   = '0;
    always_comb begin
      for (int a = 0; a < N_ARRAY; a++) begin
        for (int j = 0; j < N_ROW; j++) begin
          int out_idx = a*N_ROW + j;
          if (out_idx < N_OUT) begin
            logic [$clog2(D_MATRIX)-1:0] idx_row;
            // Safe arithmetic index: feed_idx - j in [0, D_MATRIX-1] only when valid
            if (feed_valid_mask[j]) idx_row = feed_idx - j;
            else                    idx_row = '0;
    
                w_sel = feed_valid_mask[j] ? w_out[out_idx][idx_row] : '0;
                matrix_in_arr[a][j] = {{(WIDTH_DSP_X-WIDTH_WEIGHT){w_sel[WIDTH_WEIGHT-1]}}, w_sel};
          end else begin
            matrix_in_arr[a][j] = '0;
          end
        end
      end
    end
    // -----------------------------------------
    // SA instances: one per array tile
    // -----------------------------------------
    genvar g;
    generate
        for (g = 0; g < N_ARRAY; g++) begin : GEN_SA
            SA_MAC_updated #(
                .N_ROW       (N_ROW),
                .BITWIDTH_X  (WIDTH_DSP_X),
                .BITWIDTH_Y  (WIDTH_STATE_EX),
                .BITWIDTH_AC (30),
                .BITWIDTH_OUT(WIDTH_OUTPUT)
            ) u_sa (
                .clk       (clk),
                .rst       (rst),
                .sclr      (sclr_pulse),  // CHANGED: widened clear
                .vector_in (vector_in),  // same vector; rows see it later internally
                .matrix_in (matrix_in_arr[g]),
                .result    (result_sa_arr[g])
            );
        end
    endgenerate

    // -----------------------------------------
    // Collect results at DONE
    // -----------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int k = 0; k < N_OUT; k++) out_vec[k] <= '0;
        end else if (state == DONE) begin
            for (int a = 0; a < N_ARRAY; a++) begin
                for (int j = 0; j < N_ROW; j++) begin
                    int out_idx = a*N_ROW + j;
                    if (out_idx < N_OUT)
                        out_vec[out_idx] <= result_sa_arr[a][j];
                end
            end
        end
    end

endmodule
