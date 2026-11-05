`default_nettype none
`timescale 1ns/1ps

module mac_unit (
  input  wire logic clk,
  input  wire logic rst_n,
  input  wire logic en,
  input  wire logic first,
  input  wire logic signed [7:0] bias,
  input  wire logic signed [7:0] operand_a,
  input  wire logic signed [7:0] operand_b,
  output logic signed [16:0] acc
);
  logic signed [15:0] product;
  logic signed [16:0] product_extended;
  logic signed [16:0] bias_extended;
  logic signed [16:0] next_acc;

  always_comb begin
    product = operand_a * operand_b;
    product_extended = {product[15], product};
    bias_extended = {{4'd9{bias[7]}}, bias};
    if (first) begin
      next_acc = bias_extended + product_extended;
    end else begin
      next_acc = acc + product_extended;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc <= 17'sd0;
    end else if (en) begin
      acc <= next_acc;
    end
  end
endmodule
