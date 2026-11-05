`default_nettype none
`timescale 1ns/1ps

module oled_ctrl #(
  parameter integer unsigned MS_CYCLES = 32'd100000,
  parameter integer unsigned VBAT_WAIT_CYCLES = 32'd10000000,
  parameter integer unsigned DISPLAY_WAIT_CYCLES = 32'd5000000,
  parameter integer unsigned SHUTDOWN_CYCLES = 32'd350000000
) (
  input wire logic clk,
  input wire logic rst_n,
  input wire logic toggle,
  input wire logic frame_enable,
  input wire logic [7:0] frame_data,
  output wire logic [8:0] frame_addr,
  output wire logic frame_start,
  output wire logic frame_busy,
  output logic oled_dc, oled_res, oled_sclk, oled_sdin, oled_vbat, oled_vdd
);
  localparam integer unsigned SPI_HALF_CYCLES = 32'd10;
  localparam integer unsigned MAX_A = MS_CYCLES > VBAT_WAIT_CYCLES ?
                                      MS_CYCLES : VBAT_WAIT_CYCLES;
  localparam integer unsigned MAX_B = DISPLAY_WAIT_CYCLES > SHUTDOWN_CYCLES ?
                                      DISPLAY_WAIT_CYCLES : SHUTDOWN_CYCLES;
  localparam integer unsigned MAX_DELAY = MAX_A > MAX_B ? MAX_A : MAX_B;
  localparam integer unsigned TIMER_WIDTH = $clog2(MAX_DELAY + 32'd1);
  typedef enum logic [4:0] {
    OFF = 5'd0, VDD_WAIT = 5'd1, RES_HIGH_WAIT = 5'd2,
    AE_START = 5'd3, AE_WAIT = 5'd4, RES_LOW_WAIT = 5'd5,
    RES_RELEASE_WAIT = 5'd6, INIT_START = 5'd7, INIT_WAIT = 5'd8,
    VBAT_WAIT = 5'd9, FRAME_BEGIN = 5'd10, BYTE_START = 5'd11,
    BYTE_WAIT = 5'd12, FRAME_END = 5'd13, AF_START = 5'd14,
    AF_WAIT = 5'd15, DISPLAY_WAIT = 5'd16, READY = 5'd17,
    STOP_START = 5'd18, STOP_WAIT = 5'd19, DISCHARGE = 5'd20,
    RESET_LOW = 5'd21
  } state_e;
  state_e state, next_state;
  logic [TIMER_WIDTH-1:0] timer;
  logic desired_on, blank_frame;
  logic [3:0] init_index;
  logic [9:0] frame_index;
  logic spi_start, spi_dc, spi_busy, spi_done;
  logic [7:0] spi_data, spi_shift;
  logic [3:0] spi_count;
  logic [2:0] spi_bit;

  function automatic logic [7:0] init_command(input logic [3:0] index);
    case (index)
      4'd0: init_command = 8'hA8;
      4'd1: init_command = 8'h1F;
      4'd2: init_command = 8'h8D;
      4'd3: init_command = 8'h14;
      4'd4: init_command = 8'hD9;
      4'd5: init_command = 8'hF1;
      4'd6: init_command = 8'h81;
      4'd7: init_command = 8'h0F;
      4'd8: init_command = 8'hA0;
      4'd9: init_command = 8'hC0;
      4'd10: init_command = 8'hDA;
      4'd11: init_command = 8'h02;
      4'd12: init_command = 8'h20;
      4'd13: init_command = 8'h00;
      default: init_command = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] frame_header(input logic [2:0] index);
    case (index)
      3'd0: frame_header = 8'h21;
      3'd1: frame_header = 8'h00;
      3'd2: frame_header = 8'h7F;
      3'd3: frame_header = 8'h22;
      3'd4: frame_header = 8'h00;
      3'd5: frame_header = 8'h03;
      default: frame_header = 8'h00;
    endcase
  endfunction

  assign frame_addr = frame_index[8:0] - 9'd6;
  assign frame_start = (state == READY) && desired_on && frame_enable;
  assign frame_busy = !blank_frame && ((state == FRAME_BEGIN) ||
                      (state == BYTE_START) || (state == BYTE_WAIT) || (state == FRAME_END));

  always_comb begin
    next_state = state;
    spi_start = 1'b0;
    spi_dc = 1'b0;
    spi_data = 8'd0;
    unique case (state)
      OFF: if (desired_on) next_state = VDD_WAIT;
      VDD_WAIT: if (timer == MS_CYCLES - 32'd1) next_state = RES_HIGH_WAIT;
      RES_HIGH_WAIT: if (timer == MS_CYCLES - 32'd1) next_state = AE_START;
      AE_START: begin spi_start = 1'b1; spi_data = 8'hAE; next_state = AE_WAIT; end
      AE_WAIT: if (spi_done) next_state = RES_LOW_WAIT;
      RES_LOW_WAIT: if (timer == MS_CYCLES - 32'd1) next_state = RES_RELEASE_WAIT;
      RES_RELEASE_WAIT: if (timer == MS_CYCLES - 32'd1) next_state = INIT_START;
      INIT_START: begin
        spi_start = 1'b1;
        spi_data = init_command(init_index);
        next_state = INIT_WAIT;
      end
      INIT_WAIT: if (spi_done) begin
        if (init_index == 4'd13) next_state = VBAT_WAIT;
        else next_state = INIT_START;
      end
      VBAT_WAIT: if (timer == VBAT_WAIT_CYCLES - 32'd1) next_state = FRAME_BEGIN;
      FRAME_BEGIN: next_state = BYTE_START;
      BYTE_START: begin
        spi_start = 1'b1;
        if (frame_index < 10'd6) spi_data = frame_header(frame_index[2:0]);
        else begin
          spi_dc = 1'b1;
          spi_data = blank_frame ? 8'd0 : frame_data;
        end
        next_state = BYTE_WAIT;
      end
      BYTE_WAIT: if (spi_done) begin
        if (frame_index == 10'd517) next_state = FRAME_END;
        else next_state = BYTE_START;
      end
      FRAME_END: begin
        if (blank_frame) next_state = AF_START;
        else next_state = READY;
      end
      AF_START: begin spi_start = 1'b1; spi_data = 8'hAF; next_state = AF_WAIT; end
      AF_WAIT: if (spi_done) next_state = DISPLAY_WAIT;
      DISPLAY_WAIT: if (timer == DISPLAY_WAIT_CYCLES - 32'd1) next_state = READY;
      READY: begin
        if (!desired_on) next_state = STOP_START;
        else if (frame_enable) next_state = FRAME_BEGIN;
      end
      STOP_START: begin spi_start = 1'b1; spi_data = 8'hAE; next_state = STOP_WAIT; end
      STOP_WAIT: if (spi_done) next_state = DISCHARGE;
      DISCHARGE: if (timer == SHUTDOWN_CYCLES - 32'd1) next_state = RESET_LOW;
      RESET_LOW: next_state = OFF;
      default: next_state = OFF;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= OFF;
      timer <= {TIMER_WIDTH{1'b0}};
      desired_on <= 1'b1;
      blank_frame <= 1'b1;
      init_index <= 4'd0;
      frame_index <= 10'd0;
      oled_vdd <= 1'b1;
      oled_vbat <= 1'b1;
      oled_res <= 1'b0;
    end else begin
      state <= next_state;
      if (toggle) desired_on <= !desired_on;
      if (next_state != state) timer <= {TIMER_WIDTH{1'b0}};
      else if ((state == VDD_WAIT) || (state == RES_HIGH_WAIT) ||
               (state == RES_LOW_WAIT) || (state == RES_RELEASE_WAIT) ||
               (state == VBAT_WAIT) || (state == DISPLAY_WAIT) || (state == DISCHARGE))
        timer <= timer + 1'b1;
      if (state == OFF) begin
        blank_frame <= 1'b1;
        init_index <= 4'd0;
      end
      if (state == INIT_WAIT && spi_done && init_index < 4'd13)
        init_index <= init_index + 4'd1;
      if (state == FRAME_BEGIN) frame_index <= 10'd0;
      else if (state == BYTE_WAIT && spi_done && frame_index < 10'd517)
        frame_index <= frame_index + 10'd1;
      if (state == READY && desired_on && frame_enable) blank_frame <= 1'b0;
      if (next_state == VDD_WAIT) oled_vdd <= 1'b0;
      if (next_state == RES_HIGH_WAIT || next_state == RES_RELEASE_WAIT) oled_res <= 1'b1;
      if (next_state == RES_LOW_WAIT || next_state == RESET_LOW) oled_res <= 1'b0;
      if (next_state == VBAT_WAIT) oled_vbat <= 1'b0;
      if (next_state == DISCHARGE) oled_vbat <= 1'b1;
      if (next_state == OFF) oled_vdd <= 1'b1;
    end
  end

  // The SPI pin is an output only. All state uses clk with a ten-cycle enable.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      spi_busy <= 1'b0;
      spi_done <= 1'b0;
      spi_count <= 4'd0;
      spi_bit <= 3'd7;
      spi_shift <= 8'd0;
      oled_sclk <= 1'b1;
      oled_sdin <= 1'b0;
      oled_dc <= 1'b0;
    end else begin
      spi_done <= 1'b0;
      if (spi_start && !spi_busy) begin
        spi_busy <= 1'b1;
        spi_count <= 4'd0;
        spi_bit <= 3'd7;
        spi_shift <= spi_data;
        oled_dc <= spi_dc;
      end else if (spi_busy) begin
        if (spi_count == 4'd9) begin
          spi_count <= 4'd0;
          oled_sclk <= !oled_sclk;
          if (oled_sclk) oled_sdin <= spi_shift[7];
          else if (spi_bit == 3'd0) begin
            spi_busy <= 1'b0;
            spi_done <= 1'b1;
          end else begin
            spi_bit <= spi_bit - 3'd1;
            spi_shift <= {spi_shift[6:0], 1'b0};
          end
        end else spi_count <= spi_count + 4'd1;
      end
    end
  end
endmodule
