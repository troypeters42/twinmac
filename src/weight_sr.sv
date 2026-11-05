`default_nettype none
`timescale 1ns/1ps

module weight_sr (
  input  wire logic clk,
  input  wire logic load,
  input  wire logic sdi,
  output logic [71:0] weights
);
  always_ff @(posedge clk) begin
    if (load) begin
      weights <= {weights[70:0], sdi};
    end
  end
endmodule
