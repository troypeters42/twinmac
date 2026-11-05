`default_nettype none
`timescale 1ns/1ps

module tb_twinmac;
  logic clk, rst_n, ena;
  logic [7:0] ui_in, uio_in;
  wire [7:0] uo_out, uio_out, uio_oe;
  logic [6:0] expected_y;
  logic expected_flag;
  integer unsigned checks, failures, cases_completed;

  tt_um_troypeters42_twinmac dut (
    .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
    .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n)
  );

  initial begin
    clk = 1'b0;
    forever #(32'd10) clk = ~clk;
  end

  task automatic tick(input integer unsigned cycles);
    integer unsigned cycle_index;
    begin
      for (cycle_index = 32'd0; cycle_index < cycles; cycle_index = cycle_index + 32'd1) begin
        @(posedge clk);
        #(32'd1);
        checks = checks + 32'd1;
        if ((uio_oe !== 8'd0) || (uio_out !== 8'd0)) begin
          failures = failures + 32'd1;
          if (failures <= 32'd16) $display("UIO drivers are not zero at %0t", $time);
        end
      end
    end
  endtask

  task automatic check_output(input logic [6:0] wanted_y, input logic wanted_flag,
                              input string context_name);
    begin
      checks = checks + 32'd1;
      if (uo_out !== {wanted_flag, wanted_y}) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Mismatch (%s): expected=%02h actual=%02h at %0t",
                   context_name, {wanted_flag, wanted_y}, uo_out, $time);
        end
      end
    end
  endtask

  task automatic pulse_pin(input integer unsigned pin_number);
    begin
      @(negedge clk);
      uio_in[pin_number] = 1'b1;
      tick(32'd5);
      @(negedge clk);
      uio_in[pin_number] = 1'b0;
      tick(32'd5);
    end
  endtask

  task automatic load_weights(input logic [71:0] word);
    integer signed bit_number;
    begin
      for (bit_number = 32'sd71; bit_number >= 32'sd0; bit_number = bit_number - 32'sd1) begin
        @(negedge clk);
        uio_in[0] = word[bit_number];
        tick(32'd5);
        pulse_pin(32'd1);
        check_output(expected_y, expected_flag, "weight loading holds output and flag");
      end
    end
  endtask

  task automatic latch_byte(input integer unsigned pin_number, input integer signed value);
    begin
      @(negedge clk);
      ui_in = value[7:0];
      tick(32'd5);
      pulse_pin(pin_number);
      check_output(expected_y, expected_flag, "input latching holds output and flag");
    end
  endtask

  task automatic start_and_wait(input logic [6:0] wanted_y);
    integer unsigned wait_cycles;
    begin
      @(negedge clk);
      uio_in[2] = 1'b1;
      tick(32'd5);
      check_output(expected_y, 1'b0, "start clears flag before result completes");
      @(negedge clk);
      uio_in[2] = 1'b0;
      tick(32'd5);
      for (wait_cycles = 32'd0; wait_cycles < 32'd20 && uo_out[7] !== 1'b1;
           wait_cycles = wait_cycles + 32'd1) begin
        tick(32'd1);
      end
      check_output(wanted_y, 1'b1, "completed chip-pin result");
      expected_y = wanted_y;
      expected_flag = 1'b1;
      tick(32'd5);
      check_output(expected_y, 1'b1, "done flag remains set");
      cases_completed = cases_completed + 32'd1;
    end
  endtask

  task automatic run_case(input integer signed p, q, input logic [6:0] wanted_y);
    begin
      latch_byte(32'd3, p);
      latch_byte(32'd4, q);
      @(negedge clk);
      ui_in = 8'hA6;
      tick(32'd5);
      start_and_wait(wanted_y);
    end
  endtask

  task automatic gate_cases(input logic [71:0] word, input logic [3:0] truth_table);
    integer unsigned input_case;
    begin
      load_weights(word);
      for (input_case = 32'd0; input_case < 32'd4; input_case = input_case + 32'd1) begin
        ena = input_case[0];
        run_case(input_case / 32'd2, input_case % 32'd2, {6'd0, truth_table[input_case]});
      end
    end
  endtask

  task automatic reset_chip;
    begin
      @(negedge clk);
      #(32'd2);
      rst_n = 1'b0;
      uio_in = 8'd0;
      expected_y = 7'd0;
      expected_flag = 1'b0;
      #(32'd1);
      check_output(7'd0, 1'b0, "asynchronous chip reset");
      tick(32'd5);
      @(negedge clk);
      rst_n = 1'b1;
      tick(32'd5);
      check_output(7'd0, 1'b0, "reset release leaves output clear");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    ena = 1'b1;
    ui_in = 8'd0;
    uio_in = 8'd0;
    expected_y = 7'd0;
    expected_flag = 1'b0;
    checks = 32'd0;
    failures = 32'd0;
    cases_completed = 32'd0;
    reset_chip();

    gate_cases(72'h00_01_00_FF_01_01_00_01_01, 4'b1000);
    gate_cases(72'h00_FF_01_FF_01_01_00_01_01, 4'b1110);
    gate_cases(72'h00_FE_01_FF_01_01_00_01_01, 4'b0110);
    gate_cases(72'h01_FF_00_FF_01_01_00_01_01, 4'b0111);
    gate_cases(72'h01_01_FF_FF_01_01_00_01_01, 4'b0001);
    gate_cases(72'h01_02_FF_FF_01_01_00_01_01, 4'b1001);
    $display("All 24 gate cases completed through Tiny Tapeout pins.");

    load_weights(72'h00_00_01_00_00_00_7F_80_80);
    run_case(-32'sd128, -32'sd128, 7'd127);
    load_weights(72'h00_01_00_7F_80_80_00_00_00);
    run_case(-32'sd128, -32'sd128, 7'd127);
    load_weights(72'h05_00_01_00_00_00_80_7F_7F);
    run_case(-32'sd128, -32'sd128, 7'd5);
    load_weights(72'h7F_7F_7F_00_00_00_7F_7F_7F);
    run_case(32'sd127, 32'sd127, 7'd127);
    load_weights(72'h00_00_01_00_00_00_40_00_00);
    run_case(32'sd0, 32'sd0, 7'd64);
    load_weights(72'h00_01_00_40_00_00_00_00_00);
    run_case(32'sd0, 32'sd0, 7'd64);
    load_weights(72'h00_00_01_00_00_00_00_03_02);
    run_case(32'sd5, 32'sd7, 7'd31);
    load_weights(72'h00_00_01_00_00_00_0A_03_FE);
    run_case(-32'sd4, 32'sd2, 7'd24);
    $display("Eight directed chip-pin corners completed.");

    reset_chip();
    start_and_wait(7'd10);
    @(negedge clk);
    uio_in[2] = 1'b1;
    tick(32'd5);
    check_output(7'd10, 1'b0, "busy run before reset abort");
    reset_chip();
    tick(32'd15);
    check_output(7'd0, 1'b0, "reset abort does not produce stale done");
    start_and_wait(7'd10);
    $display("Reset, retained weights, zeroed inputs, and aborted run checked.");
    $display("Completed chip-pin results: %0d.", cases_completed);
    $display("Chip-pin checks completed: %0d; failures: %0d.", checks, failures);
    if (failures == 32'd0) $display("ALL TESTS PASSED");
    else $display("FAILED: %0d", failures);
    $finish;
  end

  initial begin
    #(32'd1000000);
    $display("Watchdog timeout after 1000000 ns.");
    $display("FAILED: 1");
    $finish;
  end
endmodule
