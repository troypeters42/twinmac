`default_nettype none
`timescale 1ns/1ps

module tb_oled_ctrl;
  logic clk = 1'b0, rst_n = 1'b0, toggle = 1'b0;
  wire dc, res, sclk, sdin, vbat, vdd, frame_start, frame_busy;
  wire [8:0] frame_addr;
  integer unsigned checks = 32'd0, failures = 32'd0, index;
  integer unsigned saved_frames;
  wire unused0, unused1, unused2, unused3, unused4, unused5, unused6, unused7;
  wire [8:0] unused_addr;
  always #(32'd5) clk = ~clk;

  oled_ctrl #(.MS_CYCLES(32'd40), .VBAT_WAIT_CYCLES(32'd80),
              .DISPLAY_WAIT_CYCLES(32'd60), .SHUTDOWN_CYCLES(32'd100)) dut (
    .clk(clk), .rst_n(rst_n), .toggle(toggle), .frame_enable(1'b1),
    .frame_data(frame_addr[7:0]), .frame_addr(frame_addr),
    .frame_start(frame_start), .frame_busy(frame_busy),
    .oled_dc(dc), .oled_res(res), .oled_sclk(sclk), .oled_sdin(sdin),
    .oled_vbat(vbat), .oled_vdd(vdd)
  );
  oled_ctrl defaults (
    .clk(1'b0), .rst_n(1'b0), .toggle(1'b0), .frame_enable(1'b0), .frame_data(8'd0),
    .frame_addr(unused_addr), .frame_start(unused6), .frame_busy(unused7),
    .oled_dc(unused0), .oled_res(unused1), .oled_sclk(unused2), .oled_sdin(unused3),
    .oled_vbat(unused4), .oled_vdd(unused5)
  );
  oled_spi_monitor #(.ON_CYCLES(32'd60)) monitor (.clk(clk), .dc(dc), .res(res), .sclk(sclk),
                            .sdin(sdin), .vbat(vbat), .vdd(vdd));

  task automatic check(input logic condition, input string context_name);
    begin
      checks = checks + 32'd1;
      if (condition !== 1'b1) begin
        failures = failures + 32'd1;
        $display("Mismatch (%s)", context_name);
        $display("FAILED: %0d", failures);
        $finish;
      end
    end
  endtask

  task automatic pulse_toggle;
    begin
      @(negedge clk); toggle = 1'b1;
      @(negedge clk); toggle = 1'b0;
    end
  endtask

  initial begin
    #(32'd1);
    check(defaults.SPI_HALF_CYCLES == 32'd10, "literal 5 MHz SPI divider");
    check(defaults.MS_CYCLES == 32'd100000, "literal default 1 ms at 100 MHz");
    check(defaults.VBAT_WAIT_CYCLES == 32'd10000000, "literal default 100 ms");
    check(defaults.DISPLAY_WAIT_CYCLES == 32'd5000000, "literal default 50 ms");
    check(defaults.SHUTDOWN_CYCLES == 32'd350000000, "literal default 3.5 s");
    repeat (32'd5) @(negedge clk);
    rst_n = 1'b1;
    wait (monitor.user_frames == 32'd1);
    @(negedge clk);
    for (index = 32'd0; index < 32'd512; index = index + 32'd1)
      check(monitor.frame_bytes[index] === index[7:0], "all 512 synthetic frame bytes");
    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd100);
    saved_frames = monitor.user_frames;
    pulse_toggle();
    wait (monitor.shutdowns == 32'd1);
    check(monitor.user_frames > saved_frames, "shutdown finishes current frame");
    check(vdd && vbat && !res && sclk, "safe final shutdown levels");
    pulse_toggle();
    wait (monitor.powerups == 32'd2 && monitor.user_frames > saved_frames + 32'd1);
    @(negedge clk);
    for (index = 32'd0; index < 32'd512; index = index + 32'd1)
      check(monitor.frame_bytes[index] === index[7:0], "restart frame contents");
    $display("Power-ups: %0d; safe shutdowns: %0d; user frames: %0d.",
             monitor.powerups, monitor.shutdowns, monitor.user_frames);
    $display("OLED controller checks: %0d; SPI/power checks: %0d; failures: %0d.",
             checks, monitor.checks, failures);
    $display("ALL TESTS PASSED");
    $finish;
  end
  initial begin
    #(32'd20000000);
    $display("FAILED: 1 (OLED controller watchdog)");
    $finish;
  end
endmodule
