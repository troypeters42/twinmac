`default_nettype none
`timescale 1ns/1ps

module twinmac_core (
  input  wire logic clk,
  input  wire logic rst_n,
  input  wire logic load,
  input  wire logic sdi,
  input  wire logic start,
  input  wire logic signed [7:0] x1,
  input  wire logic signed [7:0] x2,
  output logic [6:0] y,
  output logic done
);
  logic [71:0] weights;
  logic signed [7:0] b, c, a, b2, w22, w21, b1, w12, w11;
  logic mac0_en, mac1_en, mac_first, hidden_en, output_en;
  logic [1:0] operand_sel;
  logic signed [7:0] mac0_a, mac0_b, mac0_bias, mac1_a, mac1_b;
  logic signed [16:0] acc0, acc1;
  logic [6:0] clamped0, clamped1, h1, h2;

  assign b = $signed(weights[71:64]);
  assign c = $signed(weights[63:56]);
  assign a = $signed(weights[55:48]);
  assign b2 = $signed(weights[47:40]);
  assign w22 = $signed(weights[39:32]);
  assign w21 = $signed(weights[31:24]);
  assign b1 = $signed(weights[23:16]);
  assign w12 = $signed(weights[15:8]);
  assign w11 = $signed(weights[7:0]);

  weight_sr weight_store (
    .clk(clk),
    .load(load),
    .sdi(sdi),
    .weights(weights)
  );

  control_fsm controller (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mac0_en(mac0_en),
    .mac1_en(mac1_en),
    .mac_first(mac_first),
    .operand_sel(operand_sel),
    .hidden_en(hidden_en),
    .output_en(output_en),
    .done(done)
  );

  always_comb begin
    mac0_a = 8'sd0;
    mac0_b = 8'sd0;
    mac0_bias = b1;
    mac1_a = 8'sd0;
    mac1_b = 8'sd0;
    unique case (operand_sel)
      2'd0: begin
        mac0_a = x1;
        mac0_b = w11;
        mac1_a = x1;
        mac1_b = w21;
      end
      2'd1: begin
        mac0_a = x2;
        mac0_b = w12;
        mac1_a = x2;
        mac1_b = w22;
      end
      2'd2: begin
        mac0_a = $signed({1'b0, h1});
        mac0_b = a;
        mac0_bias = b;
      end
      2'd3: begin
        mac0_a = $signed({1'b0, h2});
        mac0_b = c;
        mac0_bias = b;
      end
      default: begin
        mac0_bias = b1;
      end
    endcase
  end

  mac_unit mac0 (
    .clk(clk),
    .rst_n(rst_n),
    .en(mac0_en),
    .first(mac_first),
    .bias(mac0_bias),
    .operand_a(mac0_a),
    .operand_b(mac0_b),
    .acc(acc0)
  );

  mac_unit mac1 (
    .clk(clk),
    .rst_n(rst_n),
    .en(mac1_en),
    .first(mac_first),
    .bias(b2),
    .operand_a(mac1_a),
    .operand_b(mac1_b),
    .acc(acc1)
  );

  clamp clamp0 (
    .value(acc0),
    .clamped(clamped0)
  );

  clamp clamp1 (
    .value(acc1),
    .clamped(clamped1)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      h1 <= 7'd0;
      h2 <= 7'd0;
      y <= 7'd0;
    end else begin
      if (hidden_en) begin
        h1 <= clamped0;
        h2 <= clamped1;
      end
      if (output_en) begin
        y <= clamped0;
      end
    end
  end
endmodule
