`default_nettype none
`timescale 1ns/1ps

module tb_clamp;
  logic signed [16:0] value;
  logic [6:0] clamped;
  integer signed candidate;
  integer signed expected;
  integer unsigned failures;
  integer unsigned checked;

  clamp dut (
    .value(value),
    .clamped(clamped)
  );

  initial begin
    value = 17'sd0;
    failures = 32'd0;
    checked = 32'd0;

    for (candidate = -32'sd65536; candidate <= 32'sd65535;
         candidate = candidate + 32'sd1) begin
      value = candidate[16:0];
      #1;

      // The reference uses integer math, independently of the DUT output.
      if (candidate < 32'sd0) begin
        expected = 32'sd0;
      end else if (candidate > 32'sd127) begin
        expected = 32'sd127;
      end else begin
        expected = candidate;
      end

      if (clamped !== expected[6:0]) begin
        failures = failures + 32'd1;
        if (failures <= 32'd16) begin
          $display("Mismatch: value=%0d expected=%0d actual=%0d",
                   candidate, expected, clamped);
        end
      end
      checked = checked + 32'd1;
    end

    if (checked != 32'd131072) begin
      failures = failures + 32'd1;
      $display("Coverage mismatch: checked %0d inputs", checked);
    end
    $display("Checked %0d signed inputs (-65536 through 65535).", checked);
    if (failures == 32'd0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("FAILED: %0d", failures);
    end
    $finish;
  end
endmodule
