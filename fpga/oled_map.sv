`default_nettype none
`timescale 1ns/1ps

module oled_map (
  input wire logic clk,
  input wire logic write_en,
  input wire logic [4:0] write_x, write_y,
  input wire logic write_lit,
  input wire logic [6:0] read_addr,
  output wire logic [7:0] read_data
);
  logic [7:0] pixels [0:127];
  wire [4:0] write_row;
  wire [6:0] write_addr;
  assign write_row = ~write_y;
  assign write_addr = {write_row[4:3], write_x};
  assign read_data = pixels[read_addr];
  // Every bit is replaced before publication; no memory reset is needed.
  always_ff @(posedge clk) begin
    if (write_en) pixels[write_addr][write_row[2:0]] <= write_lit;
  end
endmodule
