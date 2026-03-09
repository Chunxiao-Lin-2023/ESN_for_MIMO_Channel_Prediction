`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Chunxiao, Meiyu
// 
// Create Date: 2025/04/03 16:28:19
// Design Name: 
// Module Name: New_MAC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: This ESN neuron design utilizes 9 DSP blocks configured with typeA IP 
//              (operation: P = P + A * B) and integrates 4 groups of Carry-Save Adders (CSA).
//              Three DSP blocks form one group and feed into a single CSA module.
//              The outputs of 3 CSA modules are then combined using a final CSA stage.
//              The resulting output represents the updated neuron state, which is forwarded 
//              to the output_neuron_dsp module.
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module New_MAC 
#( 
    parameter WIDTH_STATE = 25,     // bit width of updated resevoir STATE and input DATA, after sign extended
    parameter WIDTH_WEIGTHS = 18,   // bit width of reservoir and input WEIGHTS
    parameter STATE_SIZE = 20  
)(
    input   clk,
    input   rst,
    input   run,
    input    logic [WIDTH_STATE-1:0]    resevoir [0:STATE_SIZE-1],
    input    logic [WIDTH_WEIGTHS-1:0]  weights [0:STATE_SIZE-1],
    output   logic [51:0]  y_out,          // DSP give 48 bits result + 2 carry bit from 2nd stage ACCM + 1 carry bit from 3rd stage ACCM         
    output   logic ready 
 );
 
    localparam NUM_DSP = 9;
    localparam N_CYCLE = (STATE_SIZE + NUM_DSP - 1) / NUM_DSP; ///what is this?
    
// part 1: DSP array for partial MAC operations 
//         prepare 9 inputs to 9 DSP blocks respect ivly
    logic [NUM_DSP-1:0] sclr;
    logic [WIDTH_STATE-1:0] A [0:NUM_DSP-1];
    logic [WIDTH_WEIGTHS-1:0] B [0:NUM_DSP-1];
    logic [47:0] P [0:NUM_DSP-1];
    
    genvar i;
    generate    
      for (i=0; i<NUM_DSP; i=i+1) begin: nine_DSP_array
           DSP_MAC dsp(
          .CLK(clk),         // input wire CLK
          .SCLR(sclr[i]),    // input wire SCLR
          .A(A[i]),          // input wire [24 : 0] A
          .B(B[i]),          // input wire [17 : 0] B
          .PCOUT(),          // output wire [47 : 0] PCOUT
          .P(P[i])           // output wire [47 : 0] P
          ); end
     endgenerate         
     
// part 2: 3 carry-save adders for 2-stage accumulation
    logic [49:0] C1 [0:2];
    CSA #(.WIDTH(48)) csa_0( .ain(P[0]), .bin(P[1]), .cin(P[2]), .result(C1[0]) );
    CSA #(.WIDTH(48)) csa_1( .ain(P[3]), .bin(P[4]), .cin(P[5]), .result(C1[1]) );
    CSA #(.WIDTH(48)) csa_2( .ain(P[6]), .bin(P[7]), .cin(P[8]), .result(C1[2]) );
    
 // part 3: 1 carry-save adders for 3-stage accumulation   
    logic [51:0] C2;
    CSA #(.WIDTH(50)) csa_3( .ain(C1[0]), .bin(C1[1]), .cin(C1[2]), .result(C2) );
    
    
// FSM
    logic [1:0] state, state_next;
    logic [3:0] fsmcnt, fsmcnt_next;
    
    
    localparam INIT=2'b00, MACC=2'b01, ACCUM=2'b10, DONE=2'b11;
     always_ff@(posedge clk) begin
        if (rst) begin
            state <= INIT;
            fsmcnt <= 'd0;
            end
        else begin
            state <= state_next;
            fsmcnt <= fsmcnt_next;
            end
        end
    
    always_comb begin
        state_next = state;
        fsmcnt_next = fsmcnt;
        case(state)
            INIT: begin
                    state_next = run ? MACC : INIT;
                    fsmcnt_next = run ? 'd0 : fsmcnt;
                    end
            MACC: begin
                    state_next = (fsmcnt == N_CYCLE+2) ? ACCUM : MACC;
                    fsmcnt_next = (fsmcnt == N_CYCLE+2) ? 'd0 : (fsmcnt + 'd1);
                    end
            ACCUM: state_next = DONE;
            DONE: state_next = INIT;
        endcase
        end
        
        
genvar j;
generate 
  for (j = 0; j < NUM_DSP; j = j + 1) begin
    always_comb begin
      A[j] = '0;
      B[j] = '0;
      if ((state == MACC) && (fsmcnt < N_CYCLE)) begin
        int index = j + fsmcnt * NUM_DSP;
        if (index < STATE_SIZE) begin
          A[j] = resevoir[index];
          B[j] = weights[index];
        end
      end
    end
  end
endgenerate


logic [51:0] y_out_reg;
always_ff@(posedge clk) begin
    if (rst) begin
        y_out_reg <= 'd0;
        ready <= 'd0;
        end
    else begin
        y_out_reg <= (state == DONE) ? C2 : y_out_reg;
        ready <= (state == DONE) ? 1'b1 : 1'b0;
        end
    end            
        
assign sclr = (state == INIT) ? {NUM_DSP{1'b1}} : {NUM_DSP{1'b0}};    
assign y_out = y_out_reg;

 
endmodule
