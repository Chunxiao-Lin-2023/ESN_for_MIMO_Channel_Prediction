`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Chunxiao, Meiyu
// 
// Create Date: 2025/04/07 00:41:31
// Design Name: 
// Module Name: New_dual_RN
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


module New_dual_RN#(

    parameter WIDTH_STATE_EX    = 25,     // bit width of updated resevoir STATE and input DATA, already EXTENDED
    parameter WIDTH_WEIGTH   = 16,       // bit width of reservoir and input WEIGHTS, NOT EXTENDED
    
    parameter D_MATRIX       = 20           // NUM_NEUR + NUM_IN
    
    )(
    input   clk,
    input   rst,
    input   run,

    input   wire    [WIDTH_STATE_EX-1:0]       state_ex [0:D_MATRIX-1],  // Q1.19
    input   wire    [WIDTH_WEIGTH-1:0]         w_ex_a   [0:D_MATRIX-1],  // Q1.15
    input   wire    [WIDTH_WEIGTH-1:0]         w_ex_b   [0:D_MATRIX-1],
    
    output  logic     [WIDTH_STATE_EX-1:0]       echostate_a,              // Q1.19 output
    output  logic     [WIDTH_STATE_EX-1:0]       echostate_b,
    
    // ports for debugging
//    output  logic [51:0]  sop_A, sop_B,
//    output  logic         ready_A, ready_B,
    
    output  logic     echoready
);
// ---------- Extended vectors input to DSP_CSA ----------
//    wire    [24:0]   resevoir   [0:D_MATRIX-1];          // Extended states vectors, 20b->25b
    wire    [17:0]   weights_A  [0:D_MATRIX-1];           // Extended weight, 16b->18b 
    wire    [17:0]   weights_B  [0:D_MATRIX-1];           // Extended weight, 16b->18b
    
// ---------- Outputs from DSP_CSA ----------    
    wire    [51:0]  sop_A, sop_B, sop_A_abs, sop_B_abs;             // MAC output:  48b(DSP) + 2b (carry bit from 2nd stage ACCM) + 1b (carry bit from 3rd stage ACCM)
    wire            ready_A, ready_B;
    
// ---------- Sign Extension ----------
    genvar i;
    generate
        for (i = 0; i < D_MATRIX; i++) begin
//            assign resevoir[i]   = {{5{state_ex[i][19]}}, state_ex[i]};       // Q5.19, sign extended
            assign weights_A[i]  = {{2{w_ex_a[i][15]}}, w_ex_a[i]};           // Q2.15, sign extended
            assign weights_B[i]  = {{2{w_ex_b[i][15]}}, w_ex_b[i]};           // Q2.15, sign extended
        end
    endgenerate
    
// ---------- Instantiate New_DSP_CSA for A and B ----------
    New_MAC #(
        .WIDTH_STATE(WIDTH_STATE_EX), 
        .WIDTH_WEIGTHS(WIDTH_WEIGTH+2), 
        .STATE_SIZE(D_MATRIX)
    ) DC_A (
        .clk(clk),
        .rst(rst),
        .run(run),
        .resevoir(state_ex),
        .weights(weights_A),
        .y_out(sop_A),
        .ready(ready_A)
    );
    
    New_MAC #(
        .WIDTH_STATE(WIDTH_STATE_EX), 
        .WIDTH_WEIGTHS(WIDTH_WEIGTH+2), 
        .STATE_SIZE(D_MATRIX)
    )DC_B (
        .clk(clk),
        .rst(rst),
        .run(run),
        .resevoir(state_ex),
        .weights(weights_B),
        .y_out(sop_B),
        .ready(ready_B)
    );  


    assign sop_A_abs = (sop_A[51]) ? -sop_A : sop_A;
    assign sop_B_abs = (sop_B[51]) ? -sop_B : sop_B;

    
//--------- LUT Inputs ------------
    wire    [7:0]   tanh_lut_A, tanh_lut_B;
    wire    [15:0]   slope_A, slope_B;
    wire    [18:0]  intercept_A, intercept_B;
    reg             rom_en;
    

//    assign tanh_lut_A = (ready_A) ? sop_A_abs[36:29]: tanh_lut_A;
//    assign tanh_lut_B = (ready_B) ? sop_B_abs[36:29]: tanh_lut_B;
    
    assign tanh_lut_A = sop_A_abs[36:29];  // this correction is okay.
    assign tanh_lut_B = sop_B_abs[36:29];   
    
    intercept_lut intercept (
        .clka(clk),             // input wire clka
        .ena(rom_en),           // input wire ena
        .addra(tanh_lut_A),     // input wire [7 : 0] addra
        .douta(intercept_A),    // output wire [18 : 0] douta
        .clkb(clk),             // input wire clkb
        .enb(rom_en),           // input wire enb
        .addrb(tanh_lut_B),     // input wire [7 : 0] addrb
        .doutb(intercept_B)     // output wire [18 : 0] doutb
    );
    
    slope_lut slope (
        .clka(clk),             // input wire clka
        .ena(rom_en),           // input wire ena
        .addra(tanh_lut_A),     // input wire [7 : 0] addra
        .douta(slope_A),        // output wire [15 : 0] douta
        .clkb(clk),             // input wire clkb
        .enb(rom_en),           // input wire enb
        .addrb(tanh_lut_B),     // input wire [7 : 0] addrb
        .doutb(slope_B)         // output wire [15 : 0] doutb
    );
    
// ------------Tanh function inputs------------
    wire    [24:0]  slope_A_ex, slope_B_ex;
    wire    [47:0]  intercept_A_ex, intercept_B_ex;
    wire    [17:0]  residual_A, residual_B;
    
    logic             ce1,ce2;
    
    wire    [47:0]  tanh_out_A, tanh_out_B;
    
//----------- Inputs sign extension -> DSP---------
    assign  slope_A_ex = {9'b0, slope_A};                      // 25b = 9+16, Q10
    assign  slope_B_ex = {9'b0, slope_B};
//    assign  residual_A = (ready_A) ? {10'b0, sop_A_abs[28:21]} : residual_A;     // 18b = 10+8, Q13????????
//    assign  residual_B = (ready_B) ? {10'b0, sop_B_abs[28:21]} : residual_B;          
    assign  residual_A = {10'b0, sop_A_abs[28:21]};                 // 18b = 10+8, Q13????????
    assign  residual_B = {10'b0, sop_B_abs[28:21]};   
    assign  intercept_A_ex = {25'b0, intercept_A, 4'b0};        //48b = 25+19+4, Q19 -> Q10+13
    assign  intercept_B_ex = {25'b0, intercept_B, 4'b0};

    
    // ---------- DSP Approximation: C + A*B = intercept_A_ex + slope_A_ex * residual_A ----------
    dsp_tanh dsp_a (
        .CLK(clk),
        .CE(ce1),
        .A(slope_A_ex),
        .B(residual_A),
        .C(intercept_A_ex),
        .P(tanh_out_A)
    );
    
    dsp_tanh dsp_b (
        .CLK(clk),
        .CE(ce2),
        .A(slope_B_ex),
        .B(residual_B),
        .C(intercept_B_ex),
        .P(tanh_out_B)
    );

// === FSM Control ===
// --------- FSM state ---------
    localparam  INIT = 3'd0, SOP_RUN = 3'd1, LUT = 3'd2, 
                TANH_RUN = 3'd3, TANH_WAIT = 3'd4, DONE = 3'd5;
    reg [2:0] state, next_state; 
    reg [3:0] fsmcnt, fsmcntnext; 
    logic sop_A_sign, sop_B_sign; 
     
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= INIT;
            fsmcnt   <= 8'd0;
        end else begin 
            state <= next_state;
            fsmcnt <= fsmcntnext;
        end
    end


//reg ce1_reg, ce2_reg;


//// === CE and Counter Handling ===
//always_ff @(posedge clk or posedge rst) begin   // ???check if the ce_reg is 0
//    if (rst) begin
//        ce_counter <= 0;
//        ce1_reg <= 0;
//        ce2_reg <= 0;
//    end else begin
//        if (ce_counter > 0) begin               // CE stays high while counter is non-zero
//            ce_counter <= ce_counter - 1;
//        end else begin
//            ce1_reg <= 0;
//            ce2_reg <= 0;
//        end
//        if (state == TANH_RUN) begin            // When entering TANH_RUN, start CE and load counter
//            ce1_reg <= tanh_lut_A[7] ? 1'b0 : 1'b1;
//            ce2_reg <= tanh_lut_B[7] ? 1'b0 : 1'b1;
//            ce_counter <= 2'd3;                 // Hold CE high for 3 cycles  
//        end
//    end
//end

//    assign ce1 = ce1_reg;
//    assign ce2 = ce2_reg;
    
    
// === State Handling ===
logic [1:0] ce_cnt, ce_cnt_next;
always_ff@(posedge clk) begin
    if(rst)
        ce_cnt <= 'd0;
    else
        ce_cnt <= ce_cnt_next;
    end

always @(*)begin
    next_state = state;
    ce_cnt_next = ce_cnt;
    rom_en = 1'b0;   
    case(state)
        INIT:begin 
            fsmcntnext = 4'd0;
            next_state = run ? SOP_RUN : INIT; 
        end
        SOP_RUN: begin 
                next_state  = (ready_A && ready_B) ? LUT : SOP_RUN;  end
        LUT: begin
            rom_en = 1'b1;
            next_state  = TANH_RUN;      end
        TANH_RUN: begin 
            next_state = TANH_WAIT;       end
        TANH_WAIT: begin 
            next_state = (ce_cnt == 2'd3) ? DONE : TANH_WAIT;  
            ce_cnt_next = (ce_cnt == 2'd3) ? 2'd0 : (ce_cnt + 2'd1); end
        DONE:begin 
            next_state = INIT; end
        default: ;
    endcase
    
end
         
assign ce1 = (state == TANH_WAIT);
assign ce2 = (state == TANH_WAIT);


assign echoready = (state == DONE);

logic [19:0]  raw_a, raw_b;
assign raw_a = tanh_lut_A[7] ? intercept_A : tanh_out_A[23:4];
assign raw_b = tanh_lut_B[7] ? intercept_B : tanh_out_B[23:4];

//// ---------- Output and Handshake ----------
//always_ff @(posedge clk or posedge rst) begin
//    if (rst) begin
////        echoready   <= 0;
//        raw_a <= 0;
//        raw_b <= 0;
//    end else begin
//        if (echoready) begin
//            raw_a <= tanh_lut_A[7] ? intercept_A : tanh_out_A[23:4];     // **extract bit [23:4] from tanh function result**
//            raw_b <= tanh_lut_B[7] ? intercept_B : tanh_out_B[23:4];
//        end
//    end
//end

assign sop_A_sign = sop_A[51];
assign sop_B_sign = sop_B[51];
assign echostate_a = sop_A_sign ? -raw_a : raw_a;             // Apply sign based on sop MSB
assign echostate_b = sop_B_sign ? -raw_b : raw_b;

endmodule
