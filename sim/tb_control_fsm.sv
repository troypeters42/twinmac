`default_nettype none
`timescale 1ns/1ps

module tb_control_fsm;
  logic clk;
  logic rst_n;
  logic start;
  logic mac0_en;
  logic mac1_en;
  logic mac_first;
  logic [1:0] operand_sel;
  logic hidden_en;
  logic output_en;
  logic done;

  integer unsigned expected_step;
  logic expected_done;
  integer unsigned failures;
  integer unsigned checks;
  integer unsigned runs_completed;
  integer unsigned resets_completed;
  integer unsigned abort_cases;
  integer unsigned mask_index;
  integer unsigned abort_step;
  integer unsigned step_index;

  control_fsm dut (
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

  initial begin
    clk = 1'b0;
    forever #(32'd5) clk = ~clk;
  end

  function automatic logic [6:0] controls_for_step(input integer unsigned step_number);
    begin
      // Literal rows from the specification, independent of DUT state encoding.
      // Order: mac0_en, mac1_en, mac_first, operand_sel, hidden_en, output_en.
      case (step_number)
        32'd0: controls_for_step = 7'b000_00_0_0;
        32'd1: controls_for_step = 7'b111_00_0_0;
        32'd2: controls_for_step = 7'b110_01_0_0;
        32'd3: controls_for_step = 7'b000_00_1_0;
        32'd4: controls_for_step = 7'b101_10_0_0;
        32'd5: controls_for_step = 7'b100_11_0_0;
        32'd6: controls_for_step = 7'b000_00_0_1;
        default: controls_for_step = 7'd0;
      endcase
    end
  endfunction

  task automatic check_outputs(input integer unsigned wanted_step, input logic wanted_done,
                               input string context_name);
    logic [7:0] wanted;
    logic [7:0] actual;
    begin
      wanted = {controls_for_step(wanted_step), wanted_done};
      actual = {mac0_en, mac1_en, mac_first, operand_sel, hidden_en, output_en, done};
      checks = checks + 32'd1;
      if ((wanted_step > 32'd6) || (actual !== wanted)) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Mismatch (%s): step=%0d expected=%08b actual=%08b at %0t",
                   context_name, wanted_step, wanted, actual, $time);
        end
      end
    end
  endtask

  task automatic cycle(input logic requested_start, input integer unsigned next_step,
                       input logic next_done);
    begin
      @(negedge clk);
      start = requested_start;
      #(32'd1);
      check_outputs(expected_step, expected_done, "before rising edge");
      @(posedge clk);
      #(32'd1);
      expected_step = next_step;
      expected_done = next_done;
      check_outputs(expected_step, expected_done, "after rising edge");
    end
  endtask

  task automatic run_once(input logic [5:0] busy_starts);
    integer unsigned busy_index;
    begin
      cycle(1'b1, 32'd1, 1'b0);
      for (busy_index = 32'd0; busy_index < 32'd5; busy_index = busy_index + 32'd1) begin
        cycle(busy_starts[busy_index], busy_index + 32'd2, 1'b0);
      end
      cycle(busy_starts[32'd5], 32'd0, 1'b1);
      runs_completed = runs_completed + 32'd1;
    end
  endtask

  task automatic apply_reset(input logic start_during_reset);
    begin
      @(negedge clk);
      start = start_during_reset;
      #(32'd1);
      check_outputs(expected_step, expected_done, "start changes before reset");
      #(32'd1);
      rst_n = 1'b0;
      expected_step = 32'd0;
      expected_done = 1'b0;
      #(32'd1);
      check_outputs(32'd0, 1'b0, "asynchronous reset before next rising edge");
      @(posedge clk);
      #(32'd1);
      check_outputs(32'd0, 1'b0, "reset held through first rising edge");
      @(posedge clk);
      #(32'd1);
      check_outputs(32'd0, 1'b0, "reset held through second rising edge");
      @(negedge clk);
      rst_n = 1'b1;
      #(32'd1);
      check_outputs(32'd0, 1'b0, "reset release with start unchanged");
      @(posedge clk);
      #(32'd1);
      if (start_during_reset) begin
        expected_step = 32'd1;
      end else begin
        expected_step = 32'd0;
      end
      check_outputs(expected_step, 1'b0, "first rising edge after reset release");
      resets_completed = resets_completed + 32'd1;
    end
  endtask

  task automatic pulse_start_without_edge;
    begin
      @(negedge clk);
      start = 1'b0;
      #(32'd1);
      check_outputs(32'd0, 1'b0, "idle before short start pulse");
      start = 1'b1;
      #(32'd1);
      check_outputs(32'd0, 1'b0, "start rises between clock edges");
      start = 1'b0;
      #(32'd1);
      check_outputs(32'd0, 1'b0, "start falls between clock edges");
      @(posedge clk);
      #(32'd1);
      check_outputs(32'd0, 1'b0, "unsampled start pulse does not begin a run");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    expected_step = 32'd0;
    expected_done = 1'b0;
    failures = 32'd0;
    checks = 32'd0;
    runs_completed = 32'd0;
    resets_completed = 32'd0;
    abort_cases = 32'd0;

    apply_reset(1'b0);
    cycle(1'b0, 32'd0, 1'b0);
    cycle(1'b0, 32'd0, 1'b0);
    pulse_start_without_edge();

    // Mask bit 0 drives start at E1, and bit 5 drives start at E6.
    // Consecutive calls start the next run at E7 while the old done is high.
    for (mask_index = 32'd0; mask_index < 32'd64; mask_index = mask_index + 32'd1) begin
      run_once(mask_index[5:0]);
    end
    cycle(1'b0, 32'd0, 1'b0);
    cycle(1'b0, 32'd0, 1'b0);
    $display("All 64 busy-start masks checked, including immediate E7 restarts.");

    for (abort_step = 32'd1; abort_step <= 32'd6; abort_step = abort_step + 32'd1) begin
      cycle(1'b1, 32'd1, 1'b0);
      for (step_index = 32'd2; step_index <= abort_step; step_index = step_index + 32'd1) begin
        cycle(1'b0, step_index, 1'b0);
      end
      apply_reset(1'b1);
      for (step_index = 32'd2; step_index <= 32'd6; step_index = step_index + 32'd1) begin
        cycle(1'b0, step_index, 1'b0);
      end
      cycle(1'b0, 32'd0, 1'b1);
      abort_cases = abort_cases + 32'd1;
      if (abort_step != 32'd6) begin
        cycle(1'b0, 32'd0, 1'b0);
      end
    end

    // Reset also clears an asserted done; held start waits for a clock edge.
    apply_reset(1'b1);
    for (step_index = 32'd2; step_index <= 32'd6; step_index = step_index + 32'd1) begin
      cycle(1'b0, step_index, 1'b0);
    end
    cycle(1'b0, 32'd0, 1'b1);
    cycle(1'b0, 32'd0, 1'b0);
    cycle(1'b0, 32'd0, 1'b0);

    $display("Reset aborts checked in all six compute states, plus reset during done.");
    $display("Reset release with start high waited for the next rising edge.");
    $display("Runs: %0d; reset-abort phases: %0d; reset sequences: %0d.",
             runs_completed, abort_cases, resets_completed);
    $display("Control-vector checks completed: %0d; failures: %0d.", checks, failures);
    if (failures == 32'd0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("FAILED: %0d", failures);
    end
    $finish;
  end

  initial begin
    #(32'd20000);
    $display("Watchdog timeout after 20000 ns.");
    $display("FAILED: 1");
    $finish;
  end
endmodule
