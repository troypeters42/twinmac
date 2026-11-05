`default_nettype none
`timescale 1ns/1ps

module tb_twinmac_core;
  localparam logic [31:0] RANDOM_SEED = 32'h54574D35;
  localparam logic [71:0] AND_WORD = 72'h00_01_00_FF_01_01_00_01_01;
  localparam logic [71:0] OR_WORD = 72'h00_FF_01_FF_01_01_00_01_01;
  localparam logic [71:0] XOR_WORD = 72'h00_FE_01_FF_01_01_00_01_01;
  localparam logic [71:0] NAND_WORD = 72'h01_FF_00_FF_01_01_00_01_01;
  localparam logic [71:0] NOR_WORD = 72'h01_01_FF_FF_01_01_00_01_01;
  localparam logic [71:0] XNOR_WORD = 72'h01_02_FF_FF_01_01_00_01_01;

  logic clk, rst_n, load, sdi, start, done;
  logic signed [7:0] x1, x2;
  logic [6:0] y;
  logic [71:0] loaded_weights, random_word;
  integer signed expected_acc0, expected_acc1, expected_h1, expected_h2, expected_y;
  logic expected_done;
  integer unsigned failures, checks, cases_completed, resets_completed;
  integer unsigned seed, seed_sample, random_index, abort_index, edge_index;
  integer signed random_x1, random_x2, random_y;

  twinmac_core dut (
    .clk(clk), .rst_n(rst_n), .load(load), .sdi(sdi), .start(start),
    .x1(x1), .x2(x2), .y(y), .done(done)
  );

  initial begin
    clk = 1'b0;
    forever #(32'd5) clk = ~clk;
  end

  function automatic integer signed signed_byte(input logic [7:0] raw);
    integer signed value;
    begin
      value = raw;
      if (value >= 32'sd128) value = value - 32'sd256;
      signed_byte = value;
    end
  endfunction

  function automatic integer signed limit_sum(input integer signed value);
    begin
      if (value < 32'sd0) limit_sum = 32'sd0;
      else if (value > 32'sd127) limit_sum = 32'sd127;
      else limit_sum = value;
    end
  endfunction

  function automatic integer signed reference_y(input logic [71:0] word,
                                               input integer signed p, q);
    integer signed hidden1, hidden2;
    begin
      hidden1 = limit_sum(signed_byte(word[23:16]) + signed_byte(word[7:0]) * p
                          + signed_byte(word[15:8]) * q);
      hidden2 = limit_sum(signed_byte(word[47:40]) + signed_byte(word[31:24]) * p
                          + signed_byte(word[39:32]) * q);
      reference_y = limit_sum(signed_byte(word[71:64]) + signed_byte(word[55:48]) * hidden1
                              + signed_byte(word[63:56]) * hidden2);
    end
  endfunction

  function automatic logic [7:0] random_byte();
    random_byte = $urandom();
  endfunction

  task automatic check_state(input string context_name);
    logic [55:0] wanted, actual;
    begin
      wanted = {expected_acc0[16:0], expected_acc1[16:0], expected_h1[6:0],
                expected_h2[6:0], expected_y[6:0], expected_done};
      // Hierarchical reads observe actual registers only, never reference values.
      actual = {dut.acc0, dut.acc1, dut.h1, dut.h2, y, done};
      checks = checks + 32'd1;
      if (actual !== wanted) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Mismatch (%s) at %0t: expected=%014h actual=%014h",
                   context_name, $time, wanted, actual);
        end
      end
    end
  endtask

  task automatic load_weights(input logic [71:0] word);
    integer signed bit_number;
    begin
      for (bit_number = 32'sd71; bit_number >= 32'sd0; bit_number = bit_number - 32'sd1) begin
        @(negedge clk);
        start = 1'b0;
        load = 1'b1;
        sdi = word[bit_number];
        #(32'd1);
        check_state("before weight-loading edge");
        @(posedge clk);
        #(32'd1);
        expected_done = 1'b0;
        check_state("registers hold while loading weights");
      end
      load = 1'b0;
      sdi = 1'b0;
      loaded_weights = word;
    end
  endtask

  task automatic compute_edge(input integer unsigned edge_number,
                              input logic requested_start,
                              input integer signed p, q, wanted_y);
    begin
      @(negedge clk);
      load = 1'b0;
      start = requested_start;
      if (edge_number == 32'd0) begin
        x1 = p[7:0];
        x2 = q[7:0];
      end
      #(32'd1);
      check_state("before compute edge");
      @(posedge clk);
      #(32'd1);
      expected_done = 1'b0;
      case (edge_number)
        32'd0: begin end
        32'd1: begin
          expected_acc0 = signed_byte(loaded_weights[23:16])
                          + signed_byte(loaded_weights[7:0]) * p;
          expected_acc1 = signed_byte(loaded_weights[47:40])
                          + signed_byte(loaded_weights[31:24]) * p;
        end
        32'd2: begin
          expected_acc0 = expected_acc0 + signed_byte(loaded_weights[15:8]) * q;
          expected_acc1 = expected_acc1 + signed_byte(loaded_weights[39:32]) * q;
        end
        32'd3: begin
          expected_h1 = limit_sum(expected_acc0);
          expected_h2 = limit_sum(expected_acc1);
        end
        32'd4: begin
          expected_acc0 = signed_byte(loaded_weights[71:64])
                          + signed_byte(loaded_weights[55:48]) * expected_h1;
        end
        32'd5: begin
          expected_acc0 = expected_acc0 + signed_byte(loaded_weights[63:56]) * expected_h2;
        end
        32'd6: begin
          expected_y = wanted_y;
          expected_done = 1'b1;
        end
        default: begin
          failures = failures + 32'd1;
          $display("Invalid reference edge: %0d", edge_number);
        end
      endcase
      check_state("after compute edge");
    end
  endtask

  task automatic run_case(input integer signed p, q, wanted_y,
                          input logic [5:0] busy_starts);
    integer unsigned run_edge;
    begin
      if (reference_y(loaded_weights, p, q) != wanted_y) begin
        failures = failures + 32'd1;
        $display("Reference disagrees with golden value: expected=%0d", wanted_y);
      end
      compute_edge(32'd0, 1'b1, p, q, wanted_y);
      for (run_edge = 32'd1; run_edge <= 32'd6; run_edge = run_edge + 32'd1) begin
        compute_edge(run_edge, busy_starts[run_edge - 32'd1], p, q, wanted_y);
      end
      cases_completed = cases_completed + 32'd1;
    end
  endtask

  task automatic gate_cases(input logic [71:0] word, input logic [3:0] truth_table);
    integer unsigned input_case;
    begin
      load_weights(word);
      for (input_case = 32'd0; input_case < 32'd4; input_case = input_case + 32'd1) begin
        run_case(input_case / 32'd2, input_case % 32'd2, truth_table[input_case],
                 input_case[5:0]);
      end
    end
  endtask

  task automatic reset_core(input logic restart_after_release);
    begin
      @(negedge clk);
      load = 1'b0;
      start = restart_after_release;
      #(32'd2);
      rst_n = 1'b0;
      expected_acc0 = 32'sd0;
      expected_acc1 = 32'sd0;
      expected_h1 = 32'sd0;
      expected_h2 = 32'sd0;
      expected_y = 32'sd0;
      expected_done = 1'b0;
      #(32'd1);
      check_state("asynchronous reset before next rising edge");
      @(posedge clk);
      #(32'd1);
      check_state("reset held at rising edge");
      @(negedge clk);
      rst_n = 1'b1;
      #(32'd1);
      check_state("reset release before next rising edge");
      @(posedge clk);
      #(32'd1);
      check_state("first edge after reset release only accepts start");
      resets_completed = resets_completed + 32'd1;
    end
  endtask

  task automatic idle_cycle;
    begin
      @(negedge clk);
      start = 1'b0;
      load = 1'b0;
      #(32'd1);
      check_state("before idle edge");
      @(posedge clk);
      #(32'd1);
      expected_done = 1'b0;
      check_state("idle holds result and clears done");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    load = 1'b0;
    sdi = 1'b0;
    start = 1'b0;
    x1 = 8'sd0;
    x2 = 8'sd0;
    loaded_weights = 72'd0;
    expected_acc0 = 32'sd0;
    expected_acc1 = 32'sd0;
    expected_h1 = 32'sd0;
    expected_h2 = 32'sd0;
    expected_y = 32'sd0;
    expected_done = 1'b0;
    failures = 32'd0;
    checks = 32'd0;
    cases_completed = 32'd0;
    resets_completed = 32'd0;
    seed = RANDOM_SEED;
    seed_sample = $urandom(seed);
    $display("Random seed: 0x%08h", RANDOM_SEED);
    reset_core(1'b0);

    gate_cases(AND_WORD, 4'b1000);
    gate_cases(OR_WORD, 4'b1110);
    gate_cases(XOR_WORD, 4'b0110);
    gate_cases(NAND_WORD, 4'b0111);
    gate_cases(NOR_WORD, 4'b0001);
    gate_cases(XNOR_WORD, 4'b1001);
    $display("All 24 gate truth-table cases completed.");

    load_weights(72'h00_00_01_00_00_00_7F_80_80);
    run_case(-32'sd128, -32'sd128, 32'sd127, 6'd0);
    load_weights(72'h00_01_00_7F_80_80_00_00_00);
    run_case(-32'sd128, -32'sd128, 32'sd127, 6'd0);
    load_weights(72'h05_00_01_00_00_00_80_7F_7F);
    run_case(-32'sd128, -32'sd128, 32'sd5, 6'd0);
    load_weights(72'h7F_7F_7F_00_00_00_7F_7F_7F);
    run_case(32'sd127, 32'sd127, 32'sd127, 6'd0);
    load_weights(72'h00_00_01_00_00_00_40_00_00);
    run_case(32'sd0, 32'sd0, 32'sd64, 6'd0);
    load_weights(72'h00_01_00_40_00_00_00_00_00);
    run_case(32'sd0, 32'sd0, 32'sd64, 6'd0);
    load_weights(72'h00_00_01_00_00_00_00_03_02);
    run_case(32'sd5, 32'sd7, 32'sd31, 6'd0);
    load_weights(72'h00_00_01_00_00_00_0A_03_FE);
    run_case(-32'sd4, 32'sd2, 32'sd24, 6'd0);
    $display("Eight directed corners completed, including 17-bit and hidden-value cases.");

    for (random_index = 32'd0; random_index < 32'd10000;
         random_index = random_index + 32'd1) begin
      random_word = {random_byte(), random_byte(), random_byte(), random_byte(),
                     random_byte(), random_byte(), random_byte(), random_byte(), random_byte()};
      random_x1 = signed_byte(random_byte());
      random_x2 = signed_byte(random_byte());
      random_y = reference_y(random_word, random_x1, random_x2);
      load_weights(random_word);
      run_case(random_x1, random_x2, random_y, random_index[5:0]);
    end
    $display("Random cases completed: 10000; all 64 busy-start masks exercised.");

    load_weights(XNOR_WORD);
    for (abort_index = 32'd0; abort_index < 32'd6; abort_index = abort_index + 32'd1) begin
      run_case(32'sd0, 32'sd0, 32'sd1, 6'd0);
      compute_edge(32'd0, 1'b1, 32'sd1, 32'sd1, 32'sd1);
      for (edge_index = 32'd1; edge_index <= abort_index; edge_index = edge_index + 32'd1) begin
        compute_edge(edge_index, 1'b0, 32'sd1, 32'sd1, 32'sd1);
      end
      reset_core(1'b1);
      for (edge_index = 32'd1; edge_index <= 32'd6; edge_index = edge_index + 32'd1) begin
        compute_edge(edge_index, 1'b0, 32'sd1, 32'sd1, 32'sd1);
      end
      cases_completed = cases_completed + 32'd1;
    end
    reset_core(1'b0);
    run_case(32'sd0, 32'sd1, 32'sd0, 6'd0);
    idle_cycle();
    idle_cycle();
    idle_cycle();
    $display("Reset aborts: six phases; all registers cleared; weights retained.");
    $display("Completed results: %0d; reset sequences: %0d.", cases_completed, resets_completed);
    $display("Core-state checks completed: %0d; failures: %0d.", checks, failures);
    if (failures == 32'd0) $display("ALL TESTS PASSED");
    else $display("FAILED: %0d", failures);
    $finish;
  end

  initial begin
    #(32'd10000000);
    $display("Watchdog timeout after 10000000 ns.");
    $display("FAILED: 1");
    $finish;
  end
endmodule
