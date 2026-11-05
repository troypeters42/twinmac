`default_nettype none
`timescale 1ns/1ps

// Independent pin-only monitor: no DUT state or byte interface is used.
module oled_spi_monitor #(
  parameter integer unsigned MS_CYCLES = 32'd40,
  parameter integer unsigned BAT_CYCLES = 32'd80,
  parameter integer unsigned ON_CYCLES = 32'd40,
  parameter integer unsigned OFF_CYCLES = 32'd100
) (
  input wire logic clk,
  input wire logic dc, res, sclk, sdin, vbat, vdd
);
  integer unsigned checks = 32'd0;
  integer unsigned failures = 32'd0;
  integer unsigned frames = 32'd0;
  integer unsigned user_frames = 32'd0;
  integer unsigned powerups = 32'd0;
  integer unsigned shutdowns = 32'd0;
  integer unsigned cycle = 32'd0;
  integer unsigned phase = 32'd0;
  integer unsigned stamp = 32'd0;
  integer unsigned af_stamp = 32'd0;
  integer unsigned init_index = 32'd0;
  integer unsigned header_index = 32'd0;
  integer unsigned data_index = 32'd0;
  integer unsigned bits_seen = 32'd0;
  integer unsigned edge_stamp = 32'd0;
  logic previous_vdd = 1'b1, previous_vbat = 1'b1, previous_res = 1'b0;
  logic previous_sclk = 1'b1, previous_sdin = 1'b0;
  logic byte_active = 1'b0, frame_active = 1'b0, blank_frame = 1'b0;
  logic byte_dc = 1'b0;
  logic [7:0] shift = 8'd0;
  logic [7:0] frame_bytes [0:511];

  task automatic check(input logic condition, input string context_name);
    begin
      checks = checks + 32'd1;
      if (condition !== 1'b1) begin
        failures = failures + 32'd1;
        $display("OLED mismatch (%s), cycle=%0d phase=%0d", context_name, cycle, phase);
        $display("FAILED: %0d", failures);
        $finish;
      end
    end
  endtask

  function automatic logic [7:0] init_byte(input integer unsigned index);
    case (index)
      32'd0: init_byte = 8'hA8;
      32'd1: init_byte = 8'h1F;
      32'd2: init_byte = 8'h8D;
      32'd3: init_byte = 8'h14;
      32'd4: init_byte = 8'hD9;
      32'd5: init_byte = 8'hF1;
      32'd6: init_byte = 8'h81;
      32'd7: init_byte = 8'h0F;
      32'd8: init_byte = 8'hA0;
      32'd9: init_byte = 8'hC0;
      32'd10: init_byte = 8'hDA;
      32'd11: init_byte = 8'h02;
      32'd12: init_byte = 8'h20;
      32'd13: init_byte = 8'h00;
      default: init_byte = 8'hFF;
    endcase
  endfunction

  function automatic logic [7:0] header_byte(input integer unsigned index);
    case (index)
      32'd0: header_byte = 8'h21;
      32'd1: header_byte = 8'h00;
      32'd2: header_byte = 8'h7F;
      32'd3: header_byte = 8'h22;
      32'd4: header_byte = 8'h00;
      32'd5: header_byte = 8'h03;
      default: header_byte = 8'hFF;
    endcase
  endfunction

  task automatic consume_byte(input logic [7:0] value, input logic is_data);
    begin
      case (phase)
        32'd2: begin
          check(cycle - stamp >= MS_CYCLES, "reset high for 1 ms before AE");
          check(!is_data && value == 8'hAE, "AE before reset pulse");
          phase = 32'd3;
        end
        32'd5: begin
          check(cycle - stamp >= MS_CYCLES, "reset release waits 1 ms");
          check(!is_data && value == init_byte(init_index),
                $sformatf("init byte %0d expected %02h got %02h", init_index,
                          init_byte(init_index), value));
          init_index = init_index + 32'd1;
          if (init_index == 32'd14) phase = 32'd6;
        end
        32'd7, 32'd9: begin
          if (phase == 32'd9) begin
            check(cycle - af_stamp >= ON_CYCLES, "50 ms after AF");
          end
          if (phase == 32'd9 && !is_data && value == 8'hAE) begin
            phase = 32'd10;
          end else begin
            check(!is_data && value == 8'h21, "frame starts with command 21");
            blank_frame = (phase == 32'd7);
            if (blank_frame) check(cycle - stamp >= BAT_CYCLES,
                                   "VBAT waits 100 ms before blank frame");
            header_index = 32'd1;
            frame_active = 1'b1;
            phase = 32'd20;
          end
        end
        32'd20: begin
          check(!is_data && value == header_byte(header_index), "six frame-header bytes");
          header_index = header_index + 32'd1;
          if (header_index == 32'd6) begin
            data_index = 32'd0;
            phase = 32'd21;
          end
        end
        32'd21: begin
          check(is_data, "all 512 frame bytes have D/C high");
          if (blank_frame) check(value == 8'd0, "initial frame is blank");
          frame_bytes[data_index] = value;
          data_index = data_index + 32'd1;
          if (data_index == 32'd512) begin
            frames = frames + 32'd1;
            frame_active = 1'b0;
            if (blank_frame) phase = 32'd8;
            else begin
              user_frames = user_frames + 32'd1;
              phase = 32'd9;
            end
          end
        end
        32'd8: begin
          check(!is_data && value == 8'hAF, "AF follows complete blank frame");
          af_stamp = cycle;
          phase = 32'd9;
        end
        default: check(1'b0, $sformatf("unexpected SPI byte %02h", value));
      endcase
    end
  endtask

  always @(posedge clk) begin
    #(32'd1);
    cycle = cycle + 32'd1;
    check((^{dc, res, sclk, sdin, vbat, vdd}) !== 1'bx, "known OLED pins");
    if (!vdd && previous_vdd) begin
      check(phase == 32'd0 && vbat && !res, "VDD on first, VBAT off, reset low");
      phase = 32'd1;
      stamp = cycle;
      powerups = powerups + 32'd1;
    end
    if (res && !previous_res) begin
      if (phase == 32'd1) begin
        check(cycle - stamp >= MS_CYCLES, "1 ms after VDD on");
        phase = 32'd2;
      end else begin
        check(phase == 32'd4 && cycle - stamp >= MS_CYCLES, "1 ms reset-low pulse");
        phase = 32'd5;
        init_index = 32'd0;
      end
      stamp = cycle;
    end
    if (!res && previous_res) begin
      if (phase == 32'd3) phase = 32'd4;
      else begin
        check(phase == 32'd11 && cycle - stamp >= OFF_CYCLES,
              "3.5 s VBAT-off wait before reset low");
        phase = 32'd12;
      end
      stamp = cycle;
    end
    if (!vbat && previous_vbat) begin
      check(phase == 32'd6 && !vdd && res, "VBAT on only after all init commands");
      phase = 32'd7;
      stamp = cycle;
    end
    if (vbat && !previous_vbat) begin
      check(phase == 32'd10 && !vdd && res, "shutdown AE then VBAT off");
      phase = 32'd11;
      stamp = cycle;
    end
    if (vdd && !previous_vdd) begin
      check(phase == 32'd12 && vbat && !res && cycle > stamp,
            "VDD off after VBAT wait and reset low");
      shutdowns = shutdowns + 32'd1;
      phase = 32'd0;
    end
    if (sdin !== previous_sdin) begin
      check(previous_sclk && !sclk, "SDIN changes only on falling SPI edge");
    end
    if (byte_active) check(dc === byte_dc, "D/C stable through eighth rising edge");
    if (previous_sclk && !sclk) begin
      if (byte_active) check(cycle - edge_stamp == 32'd10, "SPI high half is 100 ns");
      else begin
        check(cycle - edge_stamp >= 32'd10, "SPI idle high between bytes");
        if (phase == 32'd2 || (phase == 32'd5 && init_index == 32'd0))
          check(cycle - stamp >= MS_CYCLES, "1 ms before first command edge");
        if (phase == 32'd7)
          check(cycle - stamp >= BAT_CYCLES, "100 ms before first frame edge");
        if (phase == 32'd9)
          check(cycle - af_stamp >= ON_CYCLES, "50 ms before normal SPI edge");
        byte_active = 1'b1;
        byte_dc = dc;
      end
      edge_stamp = cycle;
    end
    if (!previous_sclk && sclk) begin
      check(byte_active && cycle - edge_stamp == 32'd10, "SPI low half is 100 ns");
      shift = {shift[6:0], sdin};
      edge_stamp = cycle;
      if (bits_seen == 32'd7) begin
        bits_seen = 32'd0;
        byte_active = 1'b0;
        consume_byte(shift, dc);
      end else bits_seen = bits_seen + 32'd1;
    end
    previous_vdd = vdd;
    previous_vbat = vbat;
    previous_res = res;
    previous_sclk = sclk;
    previous_sdin = sdin;
  end
endmodule
