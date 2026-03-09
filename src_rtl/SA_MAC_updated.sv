`timescale 1ns / 1ps
// the DSP IP should be reconfigured if the bitwidths are changed.
// testbench needs modification, BITWIDTH_OUT is changed from 25 to 48

module SA_MAC_updated #(
    parameter N_ROW = 16,   // depth of the 1D array
    parameter BITWIDTH_X = 17, // for elements in matrix, modify PE_A if changed
    parameter BITWIDTH_Y = 25, // for elements in vector, changed from 20-25
    parameter BITWIDTH_AC = 30,
    parameter BITWIDTH_OUT = 48  // truncate to smaller bitwidth later
)
(
    input clk, rst, sclr,
    input [BITWIDTH_Y-1:0] vector_in, //sent to A port of the first DSP
    input [BITWIDTH_X-1:0] matrix_in [0:N_ROW-1], // sent to B ports
    output logic [BITWIDTH_OUT-1:0] result [0:N_ROW-1]
    );
    
//    logic  [BITWIDTH_X-1:0]   b_in [0:N_ROW-1]; // for matrix
//    logic [BITWIDTH_AC-1:0]  a_in  [0:N_ROW-2];
    logic [BITWIDTH_AC-1:0]  acout [0:N_ROW-1];
//    logic [BITWIDTH_OUT-1:0]   p   [0:N_ROW-1];
    logic [47:0] p_orig [0:N_ROW-1];
    
    // Initial DSP unit    
    PE_A pe_a_inst (
    .CLK(clk),      // input wire CLK
    .SCLR(sclr),    // input wire SCLR
    .A(vector_in),         // input wire [19 : 0] A --> [24:0]
    .B(matrix_in[0]),          // input wire [16 : 0] B
    .ACOUT(acout[0]),  // output wire [29 : 0] ACOUT
    .P(p_orig[0])          // output wire [47 : 0] P
    );
//    assign result[0] = p_orig[0][24:0];
    assign result[0] = p_orig[0];
        
    genvar h;
    generate
    for (h = 1; h < N_ROW ; h = h + 1) begin 
      PE_B pe_b_inst (
         .CLK(clk),      // input wire CLK
         .SCLR(sclr),    // input wire SCLR
         .ACIN(acout[h-1]),    // input wire [29 : 0] ACIN
         .B(matrix_in[h]),          // input wire [16 : 0] B
         .ACOUT(acout[h]),  // output wire [29 : 0] ACOUT
         .P(p_orig[h])          // output wire [47 : 0] P
        );
      //assign result[h] = p_orig[h][24:0];
        assign result[h] = p_orig[h];
     end
    endgenerate

//    logic [24:0] p_low [0:N_ROW-1];
//    for (genvar i=0; i<N_ROW; ++i) begin
//      assign p_low[i] = p_orig[i][24:0];
//      // This should always be true if the external connection preserves bit order:
//      // Synthesis will drop this; it's for sim only.
//      assert property (@(posedge clk) result[i] === p_low[i])
//        else $error("Bit order/width mismatch on result[%0d]", i);
//    end
endmodule
