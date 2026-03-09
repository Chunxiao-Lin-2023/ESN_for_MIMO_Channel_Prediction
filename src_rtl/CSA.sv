`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Chunaxiao, Meiyu 
// 
// Create Date: 2025/04/03 17:35:28
// Design Name: 
// Module Name: CSA
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

// Carry-Save Adder with CLA stage for final addition
module CSA#(
    parameter WIDTH = 48
)(
    input  logic [WIDTH-1:0] ain, bin, cin,
    output logic [WIDTH+1:0] result
);

  logic [WIDTH-1:0] sum, carry;
  logic [WIDTH+1:0] sum_ext, carry_ext;

  // First stage: Full adders to compute partial sum and carry
  genvar i;
  generate
    for (i = 0; i < WIDTH; i++) begin : fa_stage
      full_adder fa (
        .a(ain[i]),
        .b(bin[i]),
        .cin(cin[i]),
        .sum(sum[i]),
        .cout(carry[i])
      );
    end
  endgenerate

  // Sign-extend sum and align carry
  assign sum_ext   = {{2{sum[WIDTH-1]}}, sum};
  assign carry_ext = {carry[WIDTH-1], carry, 1'b0};

  // Final stage: Carry Lookahead Adder
  cla #(.WIDTH(WIDTH+2)) cla_inst (
    .a(sum_ext),
    .b(carry_ext),
    .sum(result),
    .cout()
  );

endmodule


//////////////////////////////////////////////////
// Carry Lookahead Adder (CLA)
//////////////////////////////////////////////////
module cla #(
    parameter WIDTH = 4
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic [WIDTH-1:0] sum,
    output logic cout
);
    logic [WIDTH-1:0] p, g;
    logic [WIDTH:0] c;

    assign p = a ^ b;
    assign g = a & b;

    assign c[0] = 1'b0;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin
            assign c[i+1] = g[i] | (p[i] & c[i]);
        end
    endgenerate

    assign sum = p ^ c[WIDTH-1:0];
    assign cout = c[WIDTH];
endmodule

//////////////////////////////////////////////////
// 1-bit Full Adder
//////////////////////////////////////////////////
module full_adder (
  input  logic a, b, cin,
  output logic sum, cout
);
  logic x, y, z;

  half_adder ha1 (.a(a), .b(b),   .sum(x), .cout(y));
  half_adder ha2 (.a(x), .b(cin), .sum(sum), .cout(z));

  assign cout = y | z;
endmodule


//////////////////////////////////////////////////
// 1-bit Half Adder
//////////////////////////////////////////////////
module half_adder (
  input  logic a, b,
  output logic sum, cout
);
  assign sum  = a ^ b;
  assign cout = a & b;
endmodule

