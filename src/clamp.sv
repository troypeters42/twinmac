`default_nettype none
`timescale 1ns/1ps

module clamp (
  input  wire logic signed [16:0] value,
  output logic [6:0] clamped
);
  always_comb begin
    if (value < 17'sd0) begin
      clamped = 7'd0;
    end else if (value > 17'sd127) begin
      clamped = 7'd127;
    end else begin
      clamped = value[6:0];
    end
  end
endmodule
