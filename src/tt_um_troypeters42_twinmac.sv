`default_nettype none
`timescale 1ns/1ps

module tt_um_troypeters42_twinmac (
  input  wire logic [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire logic [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire logic ena,
  input  wire logic clk,
  input  wire logic rst_n
);
  (* ASYNC_REG = "TRUE" *) logic [1:0] reset_pipe;
  (* ASYNC_REG = "TRUE" *) logic [3:0] control_meta, control_sync;
  (* ASYNC_REG = "TRUE" *) logic sdi_meta, sdi_sync;
  logic [3:0] control_previous;
  logic [3:0] control_pulse;
  wire core_rst_n;
  logic signed [7:0] x1_reg, x2_reg;
  logic [6:0] core_y;
  logic core_done, done_flag;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reset_pipe <= 2'b00;
    end else begin
      reset_pipe <= {reset_pipe[0], 1'b1};
    end
  end
  assign core_rst_n = reset_pipe[1];

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      control_meta <= 4'd0;
      control_sync <= 4'd0;
      control_previous <= 4'd0;
      sdi_meta <= 1'b0;
      sdi_sync <= 1'b0;
    end else begin
      control_meta <= uio_in[4:1];
      control_sync <= control_meta;
      control_previous <= control_sync;
      sdi_meta <= uio_in[0];
      sdi_sync <= sdi_meta;
    end
  end
  assign control_pulse = control_sync & ~control_previous;

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      x1_reg <= 8'sd0;
      x2_reg <= 8'sd0;
      done_flag <= 1'b0;
    end else begin
      if (control_pulse[2]) x1_reg <= $signed(ui_in);
      if (control_pulse[3]) x2_reg <= $signed(ui_in);
      if (control_pulse[1]) begin
        done_flag <= 1'b0;
      end else if (core_done) begin
        done_flag <= 1'b1;
      end
    end
  end

  twinmac_core core (
    .clk(clk),
    .rst_n(core_rst_n),
    .load(control_pulse[0]),
    .sdi(sdi_sync),
    .start(control_pulse[1]),
    .x1(x1_reg),
    .x2(x2_reg),
    .y(core_y),
    .done(core_done)
  );

  assign uo_out = {done_flag, core_y};
  assign uio_out = 8'd0;
  assign uio_oe = 8'd0;
  wire _unused = &{ena, uio_in[7:5], 1'b0};
endmodule
