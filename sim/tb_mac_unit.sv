`default_nettype none
`timescale 1ns/1ps

module tb_mac_unit;
  localparam logic [31:0] RANDOM_SEED = 32'h54574D32;

  logic clk;
  logic rst_n;
  logic en;
  logic first;
  logic signed [7:0] bias;
  logic signed [7:0] operand_a;
  logic signed [7:0] operand_b;
  logic signed [16:0] acc;

  integer signed expected_acc;
  integer unsigned failures;
  integer unsigned checks;
  integer unsigned random_cases;
  integer unsigned case_index;
  integer unsigned seed;
  integer unsigned seed_sample;

  mac_unit dut (
    .clk(clk),
    .rst_n(rst_n),
    .en(en),
    .first(first),
    .bias(bias),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .acc(acc)
  );

  initial begin
    clk = 1'b0;
    forever #(32'd5) clk = ~clk;
  end

  task automatic check_acc(input integer signed wanted, input string context_name);
    begin
      checks = checks + 32'd1;
      if ($signed(acc) !== wanted) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Mismatch (%s): expected=%0d actual=%0d at %0t",
                   context_name, wanted, $signed(acc), $time);
        end
      end
    end
  endtask

  task automatic cycle(
    input logic requested_en,
    input logic requested_first,
    input integer signed requested_bias,
    input integer signed requested_a,
    input integer signed requested_b
  );
    integer signed next_expected;
    begin
      @(negedge clk);
      en = requested_en;
      first = requested_first;
      bias = requested_bias[7:0];
      operand_a = requested_a[7:0];
      operand_b = requested_b[7:0];
      #(32'd1);
      check_acc(expected_acc, "input changes before rising edge");

      // Reference arithmetic uses integer stimulus values, never the DUT output.
      next_expected = expected_acc;
      if (requested_en) begin
        if (requested_first) begin
          next_expected = requested_bias + requested_a * requested_b;
        end else begin
          next_expected = expected_acc + requested_a * requested_b;
        end
      end
      if ((next_expected < -32'sd65536) || (next_expected > 32'sd65535)) begin
        failures = failures + 32'd1;
        $display("Reference stimulus exceeds 17-bit range: %0d", next_expected);
      end

      @(posedge clk);
      #(32'd1);
      expected_acc = next_expected;
      check_acc(expected_acc, "after rising edge");
    end
  endtask

  task automatic apply_reset(input logic enabled_during_reset,
                             input logic first_during_reset);
    begin
      @(negedge clk);
      en = enabled_during_reset;
      first = first_during_reset;
      bias = 8'sd37;
      operand_a = -8'sd7;
      operand_b = 8'sd9;
      #(32'd2);
      rst_n = 1'b0;
      expected_acc = 32'sd0;
      #(32'd1);
      check_acc(32'sd0, "asynchronous reset before next rising edge");
      @(posedge clk);
      #(32'd1);
      check_acc(32'sd0, "reset priority at rising edge");
      @(negedge clk);
      rst_n = 1'b1;
      #(32'd1);
      check_acc(32'sd0, "reset release between rising edges");
      en = 1'b0;
      @(posedge clk);
      #(32'd1);
      check_acc(32'sd0, "hold after reset release");
    end
  endtask

  function automatic integer signed random_byte();
    integer signed byte_value;
    begin
      byte_value = $urandom() % 32'd256;
      random_byte = byte_value - 32'sd128;
    end
  endfunction

  initial begin
    rst_n = 1'b1;
    en = 1'b0;
    first = 1'b0;
    bias = 8'sd0;
    operand_a = 8'sd0;
    operand_b = 8'sd0;
    expected_acc = 32'sd0;
    failures = 32'd0;
    checks = 32'd0;
    random_cases = 32'd0;
    seed = RANDOM_SEED;
    seed_sample = $urandom(seed);
    $display("Random seed: 0x%08h", RANDOM_SEED);

    apply_reset(1'b0, 1'b0);
    cycle(1'b0, 1'b1, 32'sd127, -32'sd128, -32'sd128);

    // Product-only checks use bias zero and first=1.
    cycle(1'b1, 1'b1, 32'sd0, -32'sd128, -32'sd128);
    check_acc(32'sd16384, "-128 times -128");
    cycle(1'b1, 1'b1, 32'sd0, 32'sd127, -32'sd128);
    check_acc(-32'sd16256, "127 times -128");
    cycle(1'b1, 1'b1, 32'sd0, 32'sd127, 32'sd127);
    check_acc(32'sd16129, "127 times 127");
    $display("Product corners checked: 16384, -16256, 16129.");

    cycle(1'b1, 1'b1, 32'sd127, -32'sd128, -32'sd128);
    check_acc(32'sd16511, "maximum first partial sum");
    cycle(1'b0, 1'b1, -32'sd128, 32'sd127, -32'sd128);
    cycle(1'b1, 1'b0, -32'sd128, -32'sd128, -32'sd128);
    check_acc(32'sd32895, "accumulator high");
    $display("Accumulator high: expected=32895 actual=%0d", $signed(acc));

    cycle(1'b1, 1'b1, -32'sd128, 32'sd127, -32'sd128);
    check_acc(-32'sd16384, "minimum first partial sum");
    cycle(1'b0, 1'b0, 32'sd127, -32'sd128, -32'sd128);
    cycle(1'b1, 1'b0, 32'sd127, 32'sd127, -32'sd128);
    check_acc(-32'sd32640, "accumulator low");
    $display("Accumulator low: expected=-32640 actual=%0d", $signed(acc));

    // These prove that first replaces an existing sum and later bias is ignored.
    cycle(1'b1, 1'b1, 32'sd7, 32'sd2, 32'sd3);
    check_acc(32'sd13, "first replaces old accumulator");
    cycle(1'b1, 1'b0, 32'sd127, -32'sd4, 32'sd5);
    check_acc(-32'sd7, "later negative product ignores bias");
    cycle(1'b0, 1'b1, -32'sd128, 32'sd127, 32'sd127);
    cycle(1'b1, 1'b1, -32'sd3, -32'sd2, -32'sd6);
    check_acc(32'sd9, "negative bias and positive product");
    cycle(1'b1, 1'b1, -32'sd128, 32'sd0, -32'sd128);
    check_acc(-32'sd128, "negative bias sign extension");
    cycle(1'b1, 1'b0, 32'sd127, 32'sd127, 32'sd0);
    check_acc(-32'sd128, "zero product leaves accumulated sum");
    cycle(1'b1, 1'b1, 32'sd127, 32'sd0, 32'sd0);
    check_acc(32'sd127, "positive bias with zero product");

    apply_reset(1'b1, 1'b1);
    cycle(1'b1, 1'b0, 32'sd127, -32'sd1, 32'sd1);
    check_acc(-32'sd1, "accumulation resumes from reset zero");
    apply_reset(1'b0, 1'b0);

    for (case_index = 32'd0; case_index < 32'd1000;
         case_index = case_index + 32'd1) begin
      // Two enabled products keep the reference in the frozen neuron range.
      cycle(1'b1, 1'b1, random_byte(), random_byte(), random_byte());
      cycle(1'b0, 1'b1, random_byte(), random_byte(), random_byte());
      cycle(1'b1, 1'b0, random_byte(), random_byte(), random_byte());
      cycle(1'b0, 1'b0, random_byte(), random_byte(), random_byte());
      random_cases = random_cases + 32'd1;
    end

    if (random_cases != 32'd1000) begin
      failures = failures + 32'd1;
      $display("Coverage mismatch: random cases=%0d", random_cases);
    end
    $display("Random cases completed: %0d (two updates and two holds each).", random_cases);
    $display("Accumulator checks completed: %0d; failures: %0d.", checks, failures);
    if (failures == 32'd0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("FAILED: %0d", failures);
    end
    $finish;
  end

  initial begin
    #(32'd100000);
    $display("Watchdog timeout after 100000 ns.");
    $display("FAILED: 1");
    $finish;
  end
endmodule
