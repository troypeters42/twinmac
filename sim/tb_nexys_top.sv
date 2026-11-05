`default_nettype none
`timescale 1ns/1ps

module tb_nexys_top;
  logic clk, cpu_resetn, btnc;
  logic [4:0] sw;
  wire [7:0] led;
  wire oled_dc, oled_res, oled_sclk, oled_sdin, oled_vbat, oled_vdd;
  logic [7:0] previous_pins, previous_data;
  logic previous_done, loaded_valid, run_pending;
  logic [71:0] shifted_word, loaded_word, run_word, completed_word;
  logic [7:0] latched_p, latched_q, run_p, run_q, completed_p, completed_q;
  integer signed cycle_number, last_sdi_change, last_data_change;
  integer signed last_rise [4:1];
  integer signed last_fall [4:1];
  integer unsigned failures, checks, bit_count, words_loaded, starts, completions;
  integer unsigned active_start, completed_start, cases_verified;
  integer unsigned pin_index, gate_index, input_index, saved_words, wait_index;
  logic found;

  nexys_top dut (
    .clk(clk), .cpu_resetn(cpu_resetn), .btnc(btnc), .sw(sw), .led(led),
    .oled_dc(oled_dc), .oled_res(oled_res), .oled_sclk(oled_sclk),
    .oled_sdin(oled_sdin), .oled_vbat(oled_vbat), .oled_vdd(oled_vdd)
  );

  initial begin
    clk = 1'b0;
    forever #(32'd5) clk = ~clk;
  end

  function automatic logic [71:0] preset(input logic [2:0] gate_select);
    case (gate_select)
      3'd1: preset = 72'h00_FF_01_FF_01_01_00_01_01;
      3'd2: preset = 72'h00_FE_01_FF_01_01_00_01_01;
      3'd3: preset = 72'h01_FF_00_FF_01_01_00_01_01;
      3'd4: preset = 72'h01_01_FF_FF_01_01_00_01_01;
      3'd5: preset = 72'h01_02_FF_FF_01_01_00_01_01;
      default: preset = 72'h00_01_00_FF_01_01_00_01_01;
    endcase
  endfunction

  function automatic logic known_preset(input logic [71:0] word);
    case (word)
      72'h00_01_00_FF_01_01_00_01_01,
      72'h00_FF_01_FF_01_01_00_01_01,
      72'h00_FE_01_FF_01_01_00_01_01,
      72'h01_FF_00_FF_01_01_00_01_01,
      72'h01_01_FF_FF_01_01_00_01_01,
      72'h01_02_FF_FF_01_01_00_01_01: known_preset = 1'b1;
      default: known_preset = 1'b0;
    endcase
  endfunction

  function automatic logic truth_value(input logic [71:0] word,
                                        input logic [7:0] p, q);
    logic [3:0] truth_table;
    begin
      case (word)
        72'h00_FF_01_FF_01_01_00_01_01: truth_table = 4'b1110;
        72'h00_FE_01_FF_01_01_00_01_01: truth_table = 4'b0110;
        72'h01_FF_00_FF_01_01_00_01_01: truth_table = 4'b0111;
        72'h01_01_FF_FF_01_01_00_01_01: truth_table = 4'b0001;
        72'h01_02_FF_FF_01_01_00_01_01: truth_table = 4'b1001;
        default: truth_table = 4'b1000;
      endcase
      truth_value = truth_table[{p[0], q[0]}];
    end
  endfunction

  task automatic check(input logic condition, input string context_name);
    begin
      checks = checks + 32'd1;
      if (condition !== 1'b1) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) $display("Mismatch (%s) at %0t", context_name, $time);
      end
    end
  endtask

  // Observe the generated chip pins, never use DUT state as expected data.
  always @(posedge clk) begin
    #(32'd1);
    cycle_number = cycle_number + 32'sd1;
    check({oled_vdd, oled_vbat, oled_res, oled_dc, oled_sclk, oled_sdin} === 6'b110000,
          "OLED power and signal pins remain off");
    check((dut.chip_uio_out === 8'd0) && (dut.chip_uio_oe === 8'd0),
          "chip UIO drivers remain zero");
    if (!cpu_resetn) begin
      check(led === 8'd0, "reset clears LEDs and done");
      previous_pins = 8'd0;
      previous_data = 8'd0;
      previous_done = 1'b0;
      last_sdi_change = cycle_number - 32'sd10;
      last_data_change = cycle_number - 32'sd10;
      for (pin_index = 32'd1; pin_index <= 32'd4; pin_index = pin_index + 32'd1) begin
        last_rise[pin_index] = cycle_number - 32'sd10;
        last_fall[pin_index] = cycle_number - 32'sd10;
      end
      bit_count = 32'd0;
      shifted_word = 72'd0;
      loaded_valid = 1'b0;
      latched_p = 8'd0;
      latched_q = 8'd0;
      run_pending = 1'b0;
    end else begin
      check((^{dut.chip_ui, dut.chip_uio, led}) !== 1'bx, "no unknown chip pins");
      if (dut.chip_uio[0] !== previous_pins[0]) begin
        check(cycle_number - last_rise[1] >= 32'sd5, "sdi hold after sck rise");
        last_sdi_change = cycle_number;
      end
      if (dut.chip_ui !== previous_data) begin
        check((cycle_number - last_rise[3] >= 32'sd5) &&
              (cycle_number - last_rise[4] >= 32'sd5), "data hold after latch rise");
        last_data_change = cycle_number;
      end
      for (pin_index = 32'd1; pin_index <= 32'd4; pin_index = pin_index + 32'd1) begin
        if ((dut.chip_uio[pin_index] === 1'b1) &&
            (previous_pins[pin_index] === 1'b0)) begin
          check(cycle_number - last_fall[pin_index] >= 32'sd5, "control low width");
          last_rise[pin_index] = cycle_number;
          case (pin_index)
            32'd1: begin
              check(!run_pending, "no weight shifting during a run");
              check(cycle_number - last_sdi_change >= 32'sd5, "sdi setup before sck");
              shifted_word = {shifted_word[70:0], dut.chip_uio[0]};
              if (bit_count == 32'd71) begin
                loaded_word = shifted_word;
                loaded_valid = 1'b1;
                words_loaded = words_loaded + 32'd1;
                bit_count = 32'd0;
                check(known_preset(loaded_word), "all 72 bits form a frozen preset");
              end else begin
                loaded_valid = 1'b0;
                bit_count = bit_count + 32'd1;
              end
            end
            32'd2: begin
              check(!run_pending, "no new start while previous run is pending");
              check(loaded_valid && (bit_count == 32'd0), "full weights before start");
              starts = starts + 32'd1;
              active_start = starts;
              run_word = loaded_word;
              run_p = latched_p;
              run_q = latched_q;
              run_pending = 1'b1;
            end
            32'd3, 32'd4: begin
              check(!run_pending, "no input latch during a run");
              check(cycle_number - last_data_change >= 32'sd5, "input data setup");
              check((dut.chip_ui === 8'd0) || (dut.chip_ui === 8'd1),
                    "switch data is integer zero or one");
              if (pin_index == 32'd3) latched_p = dut.chip_ui;
              else latched_q = dut.chip_ui;
            end
            default: begin end
          endcase
        end
        if ((dut.chip_uio[pin_index] === 1'b0) &&
            (previous_pins[pin_index] === 1'b1)) begin
          check(cycle_number - last_rise[pin_index] >= 32'sd5, "control high width");
          last_fall[pin_index] = cycle_number;
          if (pin_index == 32'd2) check(led[7] === 1'b0, "start clears old done");
        end
      end
      if ((led[7] === 1'b1) && (previous_done === 1'b0)) begin
        check(run_pending, "completion belongs to a requested run");
        check(led === {1'b1, 6'd0, truth_value(run_word, run_p, run_q)},
              "result matches independent literal truth table");
        completed_word = run_word;
        completed_p = run_p;
        completed_q = run_q;
        completed_start = active_start;
        completions = completions + 32'd1;
        run_pending = 1'b0;
      end
      previous_pins = dut.chip_uio;
      previous_data = dut.chip_ui;
      previous_done = led[7];
    end
  end

  task automatic wait_case(input logic [2:0] gate_select, input logic p, q);
    integer unsigned start_before, elapsed;
    logic matched;
    begin
      start_before = starts;
      @(negedge clk);
      sw = {gate_select, q, p};
      matched = 1'b0;
      for (elapsed = 32'd0; elapsed < 32'd5000 && !matched; elapsed = elapsed + 32'd1) begin
        @(negedge clk);
        matched = (completed_start > start_before) &&
                  (completed_word === preset(gate_select)) &&
                  (completed_p === {7'd0, p}) && (completed_q === {7'd0, q});
      end
      check(matched, "requested gate and inputs eventually complete");
      if (matched) begin
        check(led[6:0] === {6'd0, truth_value(preset(gate_select), {7'd0, p}, {7'd0, q})},
              "board LEDs match requested switches");
      end
      cases_verified = cases_verified + 32'd1;
    end
  endtask

  task automatic wait_start;
    integer unsigned before_count, elapsed;
    begin
      before_count = starts;
      for (elapsed = 32'd0; elapsed < 32'd5000 && starts == before_count;
           elapsed = elapsed + 32'd1) @(negedge clk);
      check(starts > before_count, "host continues issuing computations");
    end
  endtask

  initial begin
    cpu_resetn = 1'b0;
    btnc = 1'b0;
    sw = 5'd0;
    failures = 32'd0;
    checks = 32'd0;
    starts = 32'd0;
    completions = 32'd0;
    words_loaded = 32'd0;
    completed_start = 32'd0;
    completed_word = 72'd0;
    completed_p = 8'd0;
    completed_q = 8'd0;
    cases_verified = 32'd0;
    cycle_number = 32'sd0;
    repeat (32'd5) @(negedge clk);
    cpu_resetn = 1'b1;
    @(posedge clk);
    #(32'd2);
    check(dut.host_rst_n === 1'b0, "host reset held after one release edge");
    @(posedge clk);
    #(32'd2);
    check(dut.host_rst_n === 1'b1, "host reset releases after two edges");
    repeat (32'd10) @(negedge clk);
    sw[0] = 1'b1;
    @(posedge clk);
    #(32'd2);
    check(dut.sw_meta[0] === 1'b1 && dut.sw_sync[0] === 1'b0,
          "switch reaches only first stage after one edge");
    @(posedge clk);
    #(32'd2);
    check(dut.sw_sync[0] === 1'b1, "switch reaches second stage after two edges");
    @(negedge clk);
    sw[0] = 1'b0;

    for (gate_index = 32'd0; gate_index < 32'd8; gate_index = gate_index + 32'd1) begin
      saved_words = words_loaded;
      for (input_index = 32'd0; input_index < 32'd4;
           input_index = input_index + 32'd1) begin
        btnc = input_index[0];
        wait_case(gate_index[2:0], input_index[1], input_index[0]);
      end
      check(words_loaded > saved_words, "every gate-select code reloads its preset");
    end
    $display("All 32 gate/input cases passed, including selects 110 and 111.");

    @(negedge clk);
    sw = 5'b00100;
    found = 1'b0;
    for (wait_index = 32'd0; wait_index < 32'd5000 && !found;
         wait_index = wait_index + 32'd1) begin
      @(negedge clk);
      found = (bit_count == 32'd10);
    end
    check(found, "observe a weight load in progress");
    sw = 5'b01001;
    wait_start();
    check(loaded_word === preset(3'd2), "gate change during load completes the latest preset");
    wait_case(3'd2, 1'b1, 1'b0);
    $display("Gate change during weight loading checked.");

    wait_start();
    repeat (32'd4) @(negedge clk);
    sw = 5'b00011;
    wait_case(3'd0, 1'b1, 1'b1);
    $display("Gate change during a run checked without busy shifting.");

    wait_start();
    repeat (32'd4) @(negedge clk);
    #(32'd2);
    saved_words = words_loaded;
    cpu_resetn = 1'b0;
    #(32'd1);
    check(led === 8'd0, "asynchronous board reset aborts a live run");
    sw = 5'b00011;
    repeat (32'd5) @(negedge clk);
    cpu_resetn = 1'b1;
    wait_case(3'd0, 1'b1, 1'b1);
    check(words_loaded > saved_words, "reset reloads weights with unchanged gate select");
    check(cases_verified == 32'd35, "all requested cases executed");
    $display("Board reset during a run and complete preset reload checked.");
    $display("Requested cases verified: %0d; complete weight words: %0d.",
             cases_verified, words_loaded);
    $display("Observed computations: %0d; starts: %0d.", completions, starts);
    $display("FPGA pin/protocol checks: %0d; failures: %0d.", checks, failures);
    if (failures == 32'd0) $display("ALL TESTS PASSED");
    else $display("FAILED: %0d", failures);
    $finish;
  end

  initial begin
    #(32'd2000000);
    $display("Watchdog timeout after 2000000 ns.");
    $display("FAILED: 1");
    $finish;
  end
endmodule
