`default_nettype none
`timescale 1ns/1ps

module tb_weight_sr;
  localparam logic [71:0] FIRST_WORD = 72'hA5_3C_81_FF_12_69_00_7E_C3;
  localparam logic [71:0] SECOND_WORD = 72'h5A_C3_7E_00_ED_96_FF_81_3C;
  localparam logic [71:0] EXTRA_BIT_WORD = 72'hB5_86_FC_01_DB_2D_FF_02_79;

  logic clk;
  logic load;
  logic sdi;
  logic [71:0] weights;
  logic [71:0] expected_weights;
  integer unsigned failures;
  integer unsigned checks;
  integer unsigned shift_edges;
  integer unsigned hold_edges;
  integer unsigned bit_index;
  integer unsigned hold_index;

  weight_sr dut (
    .clk(clk),
    .load(load),
    .sdi(sdi),
    .weights(weights)
  );

  initial begin
    clk = 1'b0;
    forever #(32'd5) clk = ~clk;
  end

  task automatic check_weights(input logic [71:0] wanted, input string context_name);
    begin
      checks = checks + 32'd1;
      if (weights !== wanted) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Mismatch (%s): expected=%018h actual=%018h at %0t",
                   context_name, wanted, weights, $time);
        end
      end
    end
  endtask

  task automatic check_byte(input logic [7:0] actual, input logic [7:0] wanted,
                            input string field_name);
    begin
      checks = checks + 32'd1;
      if (actual !== wanted) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Byte mismatch (%s): expected=%02h actual=%02h", field_name, wanted, actual);
        end
      end
    end
  endtask

  task automatic cycle(input logic requested_load, input logic requested_sdi,
                       input logic [71:0] wanted, input string context_name);
    begin
      @(negedge clk);
      load = requested_load;
      sdi = requested_sdi;
      #(32'd1);
      check_weights(expected_weights, "inputs change before rising edge");
      @(posedge clk);
      #(32'd1);
      expected_weights = wanted;
      check_weights(wanted, context_name);
      if (requested_load) begin
        shift_edges = shift_edges + 32'd1;
      end else begin
        hold_edges = hold_edges + 32'd1;
      end
    end
  endtask

  task automatic shift_word(input logic [71:0] word_to_send, input logic insert_pauses);
    logic [71:0] starting_word;
    logic [71:0] wanted;
    integer unsigned sent_index;
    integer unsigned bits_sent;
    begin
      starting_word = expected_weights;
      for (sent_index = 32'd0; sent_index < 32'd72;
           sent_index = sent_index + 32'd1) begin
        if (insert_pauses && ((sent_index % 32'd8) == 32'd0)) begin
          cycle(1'b0, 1'b0, expected_weights, "pause with sdi low");
          cycle(1'b0, 1'b1, expected_weights, "pause with sdi high");
        end
        bits_sent = sent_index + 32'd1;
        // Expected word uses the original word and sent prefix, never DUT output.
        wanted = (starting_word << bits_sent) | (word_to_send >> (32'd72 - bits_sent));
        cycle(1'b1, word_to_send[32'd71 - sent_index], wanted, "enabled serial shift");
      end
    end
  endtask

  task automatic pulse_load_between_edges;
    begin
      @(negedge clk);
      load = 1'b0;
      sdi = 1'b1;
      #(32'd1);
      check_weights(expected_weights, "falling edge with load low");
      @(posedge clk);
      #(32'd1);
      hold_edges = hold_edges + 32'd1;
      check_weights(expected_weights, "rising edge with load low");
      load = 1'b1;
      #(32'd1);
      check_weights(expected_weights, "load rises while clock stays high");
      sdi = 1'b0;
      #(32'd1);
      check_weights(expected_weights, "sdi changes while clock stays high");
      load = 1'b0;
      sdi = 1'b1;
      #(32'd1);
      check_weights(expected_weights, "load falls while clock stays high");
    end
  endtask

  initial begin
    load = 1'b0;
    sdi = 1'b0;
    expected_weights = 72'd0;
    failures = 32'd0;
    checks = 32'd0;
    shift_edges = 32'd0;
    hold_edges = 32'd0;

    // There is no reset or assumed startup value. Flush through the real ports.
    for (bit_index = 32'd0; bit_index < 32'd72; bit_index = bit_index + 32'd1) begin
      @(negedge clk);
      load = 1'b1;
      sdi = 1'b0;
      @(posedge clk);
      #(32'd1);
      shift_edges = shift_edges + 32'd1;
    end
    check_weights(72'd0, "72 zero bits establish known contents");
    cycle(1'b0, 1'b1, 72'd0, "initial hold with sdi high");
    cycle(1'b0, 1'b0, 72'd0, "initial hold with sdi low");

    shift_word(FIRST_WORD, 1'b1);
    check_weights(FIRST_WORD, "complete first word after 72 enabled shifts");
    check_byte(weights[71:64], 8'hA5, "b");
    check_byte(weights[63:56], 8'h3C, "c");
    check_byte(weights[55:48], 8'h81, "a");
    check_byte(weights[47:40], 8'hFF, "b2");
    check_byte(weights[39:32], 8'h12, "w22");
    check_byte(weights[31:24], 8'h69, "w21");
    check_byte(weights[23:16], 8'h00, "b1");
    check_byte(weights[15:8], 8'h7E, "w12");
    check_byte(weights[7:0], 8'hC3, "w11");
    $display("First word: expected=%018h actual=%018h", FIRST_WORD, weights);

    pulse_load_between_edges();
    for (hold_index = 32'd0; hold_index < 32'd4; hold_index = hold_index + 32'd1) begin
      cycle(1'b0, 1'b0, FIRST_WORD, "stored word holds with sdi low");
      cycle(1'b0, 1'b1, FIRST_WORD, "stored word holds with sdi high");
    end

    shift_word(SECOND_WORD, 1'b0);
    check_weights(SECOND_WORD, "second word replaces previous contents");
    check_byte(weights[71:64], 8'h5A, "b");
    check_byte(weights[63:56], 8'hC3, "c");
    check_byte(weights[55:48], 8'h7E, "a");
    check_byte(weights[47:40], 8'h00, "b2");
    check_byte(weights[39:32], 8'hED, "w22");
    check_byte(weights[31:24], 8'h96, "w21");
    check_byte(weights[23:16], 8'hFF, "b1");
    check_byte(weights[15:8], 8'h81, "w12");
    check_byte(weights[7:0], 8'h3C, "w11");
    $display("Second word: expected=%018h actual=%018h", SECOND_WORD, weights);

    cycle(1'b1, 1'b1, EXTRA_BIT_WORD, "extra bit still shifts after a full word");
    cycle(1'b0, 1'b0, EXTRA_BIT_WORD, "hold after extra bit with sdi low");
    cycle(1'b0, 1'b1, EXTRA_BIT_WORD, "hold after extra bit with sdi high");
    $display("All nine byte fields checked for both patterns.");
    $display("Extra-bit word: expected=%018h actual=%018h", EXTRA_BIT_WORD, weights);
    $display("Tracked rising edges: %0d shifts, %0d holds.", shift_edges, hold_edges);
    $display("Weight comparisons completed: %0d; failures: %0d.", checks, failures);
    if (failures == 32'd0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("FAILED: %0d", failures);
    end
    $finish;
  end

  initial begin
    #(32'd10000);
    $display("Watchdog timeout after 10000 ns.");
    $display("FAILED: 1");
    $finish;
  end
endmodule
