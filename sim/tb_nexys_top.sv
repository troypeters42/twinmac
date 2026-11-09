`default_nettype none
`timescale 1ns/1ps

module tb_nexys_top;
  logic clk, cpu_resetn, btnc;
  logic [6:0] sw;
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

  integer unsigned map_index, completed_maps, boolean_results;
  integer unsigned frame_index, pixel_index, before_maps, before_shutdowns;
  logic [7:0] expected_byte;
  logic saved_vdd, saved_vbat;
  logic [1:0] reference_reset_pipe = 2'b00;
  logic [6:0] reference_sw_meta, reference_sw_sync;
  logic reference_image_valid = 1'b0, reference_publish_pending = 1'b0;
  logic [2:0] reference_gate = 3'd0, publication_gate;
  logic reference_p = 1'b0, reference_q = 1'b0, publication_p, publication_q;
  integer unsigned publication_cycle;
  logic frame_snapshot_pending = 1'b0;
  logic [1:0] snapshot_mode;
  logic [2:0] snapshot_gate;
  logic snapshot_p, snapshot_q;
  integer unsigned continuous_frames_checked = 32'd0;
  integer unsigned continuous_address;
  logic [7:0] continuous_wanted;
  logic reset_alignment_active = 1'b0;
  logic reset_guard_vdd, reset_guard_vbat;
  integer unsigned aligned_resets_checked = 32'd0;
  nexys_top #(.OLED_MS_CYCLES(32'd40), .OLED_VBAT_WAIT_CYCLES(32'd80),
              .OLED_DISPLAY_WAIT_CYCLES(32'd60), .OLED_SHUTDOWN_CYCLES(32'd100),
              .BUTTON_DEBOUNCE_CYCLES(32'd5)) dut (
    .clk(clk), .cpu_resetn(cpu_resetn), .btnc(btnc), .sw(sw), .led(led),
    .oled_dc(oled_dc), .oled_res(oled_res), .oled_sclk(oled_sclk),
    .oled_sdin(oled_sdin), .oled_vbat(oled_vbat), .oled_vdd(oled_vdd)
  );

  wire [7:0] default_led;
  wire d0, d1, d2, d3, d4, d5;
  nexys_top defaults (
    .clk(1'b0), .cpu_resetn(1'b0), .btnc(1'b0), .sw(7'd0), .led(default_led),
    .oled_dc(d0), .oled_res(d1), .oled_sclk(d2), .oled_sdin(d3), .oled_vbat(d4), .oled_vdd(d5)
  );
  oled_spi_monitor #(.ON_CYCLES(32'd60)) monitor (
    .clk(clk), .dc(oled_dc), .res(oled_res), .sclk(oled_sclk), .sdin(oled_sdin),
    .vbat(oled_vbat), .vdd(oled_vdd)
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
      72'h01_02_FF_FF_01_01_00_01_01,
      72'h00_01_00_E1_01_01_00_01_01,
      72'h00_FF_01_E1_01_01_00_01_01,
      72'h00_FE_01_E1_01_01_00_01_01,
      72'h1F_FF_00_E1_01_01_00_01_01,
      72'h1F_01_FF_E1_01_01_00_01_01,
      72'h1F_02_FF_E1_01_01_00_01_01: known_preset = 1'b1;
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
        $display("Mismatch (%s) at %0t", context_name, $time);
        $display("FAILED: %0d", failures);
        $finish;
      end
    end
  endtask

  // Independent switch synchronizers model what the renderer samples at a
  // frame boundary. No renderer metadata or DUT state is used as expected data.
  always @(posedge clk) begin
    reference_reset_pipe <= {reference_reset_pipe[0], cpu_resetn};
  end
  always @(posedge clk or negedge reference_reset_pipe[1]) begin
    if (!reference_reset_pipe[1]) begin
      reference_sw_meta <= 7'd0;
      reference_sw_sync <= 7'd0;
    end else begin
      reference_sw_meta <= sw;
      reference_sw_sync <= reference_sw_meta;
    end
  end

  // The strobe supplies only the frame boundary. All expected payload fields
  // come from the independent switch model and completed Boolean pin traffic.
  always @(posedge clk) begin
    if (dut.display_start === 1'b1) begin
      check(reference_image_valid, "user frame waits for completed Boolean publication");
      check(!frame_snapshot_pending, "one snapshot for each complete user frame");
      snapshot_mode = reference_sw_sync[6:5];
      snapshot_gate = reference_gate;
      snapshot_p = reference_p;
      snapshot_q = reference_q;
      frame_snapshot_pending = 1'b1;
    end
    if (reset_alignment_active) begin
      check(oled_vdd === reset_guard_vdd && oled_vbat === reset_guard_vbat,
            "CPU reset never changes OLED power during alignment test");
    end
  end

  // Check every completed user frame, including old snapshots in flight during
  // switch/gate changes and CPU reset. No two-frame grace period is used here.
  always @(negedge clk) begin
    if (monitor.user_frames != continuous_frames_checked) begin
      check(monitor.user_frames == continuous_frames_checked + 32'd1 &&
            frame_snapshot_pending, "every SPI user frame has exactly one snapshot");
      for (continuous_address = 32'd0; continuous_address < 32'd512;
           continuous_address = continuous_address + 32'd1) begin
        continuous_wanted = frame_reference(continuous_address, snapshot_mode,
                                            snapshot_gate, snapshot_p, snapshot_q);
        check(monitor.frame_bytes[continuous_address] === continuous_wanted,
              $sformatf("every user frame %0d byte=%0d expected=%02h got=%02h",
                        monitor.user_frames, continuous_address, continuous_wanted,
                        monitor.frame_bytes[continuous_address]));
      end
      continuous_frames_checked = monitor.user_frames;
      frame_snapshot_pending = 1'b0;
    end
  end

  function automatic logic [2:0] gate_from_boolean_word(input logic [71:0] word);
    case (word)
      72'h00_FF_01_FF_01_01_00_01_01: gate_from_boolean_word = 3'd1;
      72'h00_FE_01_FF_01_01_00_01_01: gate_from_boolean_word = 3'd2;
      72'h01_FF_00_FF_01_01_00_01_01: gate_from_boolean_word = 3'd3;
      72'h01_01_FF_FF_01_01_00_01_01: gate_from_boolean_word = 3'd4;
      72'h01_02_FF_FF_01_01_00_01_01: gate_from_boolean_word = 3'd5;
      default: gate_from_boolean_word = 3'd0;
    endcase
  endfunction

  // Observe the generated chip pins, never use DUT state as expected data.
  always @(posedge clk) begin
    #(32'd1);
    cycle_number = cycle_number + 32'sd1;
    // The host publishes two clocks after the sticky done flag rises. Updating
    // after the edge preserves the old value for a simultaneous frame snapshot.
    if (reference_publish_pending && cycle_number == publication_cycle) begin
      reference_gate = publication_gate;
      reference_p = publication_p;
      reference_q = publication_q;
      reference_image_valid = 1'b1;
      reference_publish_pending = 1'b0;
    end
    check((dut.chip_uio_out === 8'd0) && (dut.chip_uio_oe === 8'd0),
          "chip UIO drivers remain zero");
    if (!reference_reset_pipe[1]) begin
      reference_image_valid = 1'b0;
      reference_publish_pending = 1'b0;
      reference_gate = 3'd0;
      reference_p = 1'b0;
      reference_q = 1'b0;
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
      map_index = 32'd0;
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
              check(!(loaded_word[47:40] == 8'hE1 && map_index > 32'd0 &&
                      map_index < 32'd1024), "finish a sweep before shifting new weights");
              if (bit_count == 32'd0) reference_image_valid = 1'b0;
              shifted_word = {shifted_word[70:0], dut.chip_uio[0]};
              if (bit_count == 32'd71) begin
                loaded_word = shifted_word;
                loaded_valid = 1'b1;
                words_loaded = words_loaded + 32'd1;
                bit_count = 32'd0;
                check(known_preset(loaded_word), "all 72 bits form an approved preset");
                if (loaded_word[47:40] == 8'hE1) map_index = 32'd0;
                else check(map_index == 32'd1024, "Boolean preset follows complete map");
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
              if (run_word[47:40] == 8'hE1) begin
                check(!monitor.frame_active || monitor.blank_frame,
                      "map sweep does not overwrite a displayed frame");
                check(run_p == (map_index % 32'd32) &&
                      run_q == (map_index / 32'd32), "map stimulus x1 fast, x2 slow");
              end
            end
            32'd3, 32'd4: begin
              check(!run_pending, "no input latch during a run");
              check(cycle_number - last_data_change >= 32'sd5, "input data setup");
              if (loaded_word[47:40] == 8'hFF) begin
                check((dut.chip_ui === 8'd0) || (dut.chip_ui === 8'd1),
                      "Boolean switch data is integer zero or one");
              end else begin
                check(dut.chip_ui <= 8'd31, "map inputs stay within 0 through 31");
              end
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
        if (run_word[47:40] == 8'hE1) begin
          check(led[7] && led[6:0] == reference_y(run_word, run_p, run_q),
                "map result matches independent integer neuron math");
          map_index = map_index + 32'd1;
          if (map_index == 32'd1024) completed_maps = completed_maps + 32'd1;
        end else begin
          check(led === {1'b1, 6'd0, truth_value(run_word, run_p, run_q)},
                "Boolean result matches independent literal truth table");
          boolean_results = boolean_results + 32'd1;
          publication_gate = gate_from_boolean_word(run_word);
          publication_p = run_p[0];
          publication_q = run_q[0];
          publication_cycle = cycle_number + 32'd2;
          reference_publish_pending = 1'b1;
        end
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


  function automatic logic [71:0] map_preset(input logic [2:0] gate_select);
    case (gate_select)
      3'd1: map_preset = 72'h00_FF_01_E1_01_01_00_01_01;
      3'd2: map_preset = 72'h00_FE_01_E1_01_01_00_01_01;
      3'd3: map_preset = 72'h1F_FF_00_E1_01_01_00_01_01;
      3'd4: map_preset = 72'h1F_01_FF_E1_01_01_00_01_01;
      3'd5: map_preset = 72'h1F_02_FF_E1_01_01_00_01_01;
      default: map_preset = 72'h00_01_00_E1_01_01_00_01_01;
    endcase
  endfunction

  function automatic integer signed byte_value(input logic [7:0] value);
    byte_value = $signed(value);
  endfunction
  function automatic integer signed relu(input integer signed value);
    if (value < 32'sd0) relu = 32'sd0;
    else if (value > 32'sd127) relu = 32'sd127;
    else relu = value;
  endfunction
  function automatic integer signed reference_y(input logic [71:0] word,
                                                input integer signed p, q);
    integer signed h1_ref, h2_ref;
    begin
      h1_ref = relu(byte_value(word[23:16]) + byte_value(word[7:0])*p +
                    byte_value(word[15:8])*q);
      h2_ref = relu(byte_value(word[47:40]) + byte_value(word[31:24])*p +
                    byte_value(word[39:32])*q);
      reference_y = relu(byte_value(word[71:64]) + byte_value(word[55:48])*h1_ref +
                         byte_value(word[63:56])*h2_ref);
    end
  endfunction
  function automatic integer unsigned lit_count(input logic [2:0] gate_select);
    case (gate_select)
      3'd1, 3'd3: lit_count = 32'd888;
      3'd2: lit_count = 32'd752;
      3'd5: lit_count = 32'd272;
      default: lit_count = 32'd136;
    endcase
  endfunction

  // Row bitmap font oracle; the RTL uses separately encoded column bitmaps.
  function automatic logic [7:0] font_row(input logic [7:0] letter,
                                         input integer unsigned row);
    logic [63:0] rows;
    begin
      case (letter)
        8'h41: rows = 64'h708888F888888800;
        8'h44: rows = 64'hF08888888888F000;
        8'h45: rows = 64'hF88080F08080F800;
        8'h47: rows = 64'h708880B888887000;
        8'h4E: rows = 64'h88C8C8A898988800;
        8'h4F: rows = 64'h7088888888887000;
        8'h52: rows = 64'hF08888F0A0908800;
        8'h54: rows = 64'hF820202020202000;
        8'h58: rows = 64'h8888502050888800;
        8'h59: rows = 64'h8888502020202000;
        8'h30: rows = 64'h708898A8C8887000;
        8'h31: rows = 64'h2060202020207000;
        8'h32: rows = 64'h708808102040F800;
        8'h3A: rows = 64'h0020200020200000;
        8'h3D: rows = 64'h0000F800F8000000;
        default: rows = 64'd0;
      endcase
      font_row = rows >> ((32'd7-row)*32'd8);
    end
  endfunction

  function automatic logic [7:0] frame_reference(input integer unsigned address,
      input logic [1:0] mode, input logic [2:0] gate_select, input logic p, q);
    integer unsigned page, column, bit_no, char_no;
    logic [7:0] value, row;
    string text_line;
    begin
      page = address / 32'd128;
      column = address % 32'd128;
      value = 8'd0;
      if (mode == 2'd1) value = 8'hFF;
      else if (mode == 2'd2) begin
        if (column == 32'd0 || column == 32'd127) value = 8'hFF;
        else if (page == 32'd0) value = 8'h01;
        else if (page == 32'd3) value = 8'h80;
      end else if (column < 32'd32) begin
        for (bit_no = 32'd0; bit_no < 32'd8; bit_no = bit_no + 32'd1)
          value[bit_no] = reference_y(map_preset(gate_select), column,
                                    32'd31-(page*32'd8+bit_no)) >= 32'sd16;
      end else if (column >= 32'd40) begin
        if (page == 32'd0) begin
          case (gate_select)
            3'd1: text_line = "GATE: OR";
            3'd2: text_line = "GATE: XOR";
            3'd3: text_line = "GATE: NAND";
            3'd4: text_line = "GATE: NOR";
            3'd5: text_line = "GATE: XNOR";
            default: text_line = "GATE: AND";
          endcase
        end else if (page == 32'd1) text_line = $sformatf("X1=%0d X2=%0d", p, q);
        else if (page == 32'd2)
          text_line = $sformatf("Y=%0d", truth_value(preset(gate_select), {7'd0,p}, {7'd0,q}));
        else text_line = "";
        char_no = (column-32'd40) / 32'd8;
        if (char_no < text_line.len()) begin
          for (bit_no = 32'd0; bit_no < 32'd8; bit_no = bit_no + 32'd1) begin
            row = font_row(text_line[char_no], bit_no);
            value[bit_no] = row[32'd7-((column-32'd40) % 32'd8)];
          end
        end
      end
      frame_reference = value;
    end
  endfunction

  task automatic wait_case(input logic [2:0] gate_select, input logic p, q);
    integer unsigned start_before, elapsed;
    logic matched;
    begin
      start_before = starts;
      @(negedge clk); sw[4:0] = {gate_select, q, p};
      matched = 1'b0;
      for (elapsed = 32'd0; elapsed < 32'd500000 && !matched; elapsed = elapsed + 32'd1) begin
        @(negedge clk);
        matched = completed_start > start_before && completed_word === preset(gate_select) &&
                  completed_p === {7'd0,p} && completed_q === {7'd0,q};
      end
      check(matched, "requested Boolean gate and inputs eventually complete");
      check(led[6:0] === {6'd0,truth_value(preset(gate_select),{7'd0,p},{7'd0,q})},
            "LEDs match requested Boolean switches");
      cases_verified = cases_verified + 32'd1;
    end
  endtask
  task automatic wait_start;
    integer unsigned before_count;
    begin
      before_count = starts;
      wait (starts > before_count && run_word[47:40] == 8'hFF);
      @(negedge clk);
    end
  endtask
  task automatic check_frame(input logic [1:0] mode, input logic [2:0] gate_select,
                             input logic p, q);
    integer unsigned before_frame, address, bit_no, lit_pixels;
    logic [7:0] wanted;
    begin
      // One frame can already contain the preceding switch snapshot. Check a
      // whole subsequent frame after the inputs and completed result are stable.
      before_frame = monitor.user_frames;
      wait (monitor.user_frames >= before_frame + 32'd2);
      @(negedge clk);
      lit_pixels = 32'd0;
      for (address = 32'd0; address < 32'd512; address = address + 32'd1) begin
        wanted = frame_reference(address, mode, gate_select, p, q);
        check(monitor.frame_bytes[address] === wanted,
              $sformatf("frame gate=%0d mode=%0d byte=%0d expected=%02h got=%02h",
                        gate_select, mode, address, wanted, monitor.frame_bytes[address]));
        if ((address % 32'd128) < 32'd32) begin
          for (bit_no = 32'd0; bit_no < 32'd8; bit_no = bit_no + 32'd1)
            if (monitor.frame_bytes[address][bit_no]) lit_pixels = lit_pixels + 32'd1;
        end
      end
      if (mode == 2'd0 || mode == 2'd3)
        check(lit_pixels == lit_count(gate_select), "literal map lit-pixel count");
      $display("SPI frame checked: gate=%0d mode=%0d map pixels=%0d.",
               gate_select, mode, lit_pixels);
    end
  endtask
  // Observe storage, excluding unreset weight/map memories and the two reset
  // synchronizer stages themselves. No RTL signal supplies expected arithmetic.
  function automatic logic [255:0] host_registers();
    host_registers = {dut.sw_meta, dut.sw_sync, dut.state, dut.phase_count,
                      dut.loaded_gate, dut.boolean_gate, dut.map_mode, dut.map_valid,
                      dut.map_x, dut.map_y, dut.bit_index, dut.weight_word,
                      dut.data_byte, dut.run_x1, dut.run_x2,
                      dut.boolean_x1, dut.boolean_x2, dut.boolean_y};
  endfunction
  function automatic logic [255:0] host_reset_values();
    host_reset_values = {7'd0, 7'd0, 5'd0, 3'd0, 3'd0, 3'd0, 1'b1, 1'b0,
                         5'd0, 5'd0, 7'd71, 72'd0, 8'd0, 8'd0, 8'd0,
                         1'b0, 1'b0, 7'd0};
  endfunction
  function automatic logic [255:0] chip_registers();
    chip_registers = {dut.chip.reset_pipe, dut.chip.control_meta, dut.chip.control_sync,
                      dut.chip.control_previous, dut.chip.sdi_meta, dut.chip.sdi_sync,
                      dut.chip.x1_reg, dut.chip.x2_reg, dut.chip.done_flag,
                      dut.chip.core.controller.state, dut.chip.core.done,
                      dut.chip.core.acc0, dut.chip.core.acc1,
                      dut.chip.core.h1, dut.chip.core.h2, dut.chip.core.y};
  endfunction

  task automatic aligned_cpu_reset(input string context_name,
                                    input logic finish_current_frame);
    logic [255:0] before_host, before_chip;
    logic [255:0] first_edge_host, first_edge_chip;
    integer unsigned frame_before;
    begin
      @(posedge clk);
      #(3.3);
      check(dut.host_rst_n && dut.chip.rst_n && dut.chip.core_rst_n,
            "reset alignment starts from running host and chip");
      before_host = host_registers();
      before_chip = chip_registers();
      reset_guard_vdd = oled_vdd;
      reset_guard_vbat = oled_vbat;
      reset_alignment_active = 1'b1;
      frame_before = monitor.user_frames;
      if (finish_current_frame)
        check(frame_snapshot_pending && monitor.frame_active,
              "reset alignment exercises a user frame already in flight");
      cpu_resetn = 1'b0;
      #(0.1);
      check(dut.host_rst_n === 1'b1 && dut.chip.rst_n === 1'b1 &&
            host_registers() === before_host && chip_registers() === before_chip,
            "off-edge CPU RESET leaves host and chip storage unchanged");
      #(6.5);
      check(host_registers() === before_host && chip_registers() === before_chip,
            "no host or chip storage changes before the first sampling edge");
      @(posedge clk);
      #(0.2);
      check(dut.reset_pipe === 2'b10 && dut.host_rst_n === 1'b1 &&
            dut.chip.rst_n === 1'b1 && dut.chip.core_rst_n === 1'b1,
            "CPU RESET does not assert after only one sampling edge");
      // Normal clocked work may continue at edge one. Its resulting storage
      // must then remain unchanged until the second edge asserts reset.
      first_edge_host = host_registers();
      first_edge_chip = chip_registers();
      #(9.7);
      check(dut.host_rst_n === 1'b1 && host_registers() === first_edge_host &&
            chip_registers() === first_edge_chip,
            "no off-edge host or chip change before second reset edge");
      @(posedge clk);
      #(0.2);
      check(dut.reset_pipe === 2'b00 && dut.host_rst_n === 1'b0 &&
            dut.chip.rst_n === 1'b0 && dut.chip.core_rst_n === 1'b0,
            "CPU RESET asserts host and chip on second sampling edge");
      check(host_registers() === host_reset_values(),
            "all CPU-reset host registers reach specified reset values");
      check(chip_registers() === 256'd0 && led === 8'd0,
            "all resettable chip registers and LEDs clear on second reset edge");
      if (finish_current_frame) begin
        wait (monitor.user_frames == frame_before + 32'd1);
        @(negedge clk);
        #(32'd1);
        check(continuous_frames_checked == monitor.user_frames,
              "reset frame completed byte for byte using its old snapshot");
        repeat (32'd20) @(negedge clk);
        check(monitor.user_frames == frame_before + 32'd1 && !dut.display_start,
              "no new user frame while CPU RESET is held");
      end else repeat (32'd5) @(negedge clk);
      check(oled_vdd === reset_guard_vdd && oled_vbat === reset_guard_vbat,
            "OLED power remains unchanged throughout CPU RESET");
      @(negedge clk); cpu_resetn = 1'b1;
      @(posedge clk); #(0.2);
      check(dut.host_rst_n === 1'b0, "aligned reset release waits through edge one");
      @(posedge clk); #(0.2);
      check(dut.host_rst_n === 1'b1, "aligned reset releases at edge two");
      reset_alignment_active = 1'b0;
      aligned_resets_checked = aligned_resets_checked + 32'd1;
      $display("Aligned CPU reset checked: %s (fall 3.3 ns after clk).", context_name);
    end
  endtask

  task automatic press_button;
    begin
      @(negedge clk); btnc = 1'b1;
      repeat (32'd30) @(negedge clk);
      btnc = 1'b0;
      repeat (32'd30) @(negedge clk);
    end
  endtask

  initial begin
    cpu_resetn = 1'b0; btnc = 1'b0; sw = 7'd0;
    failures = 32'd0; checks = 32'd0; starts = 32'd0; completions = 32'd0;
    words_loaded = 32'd0; completed_start = 32'd0; completed_word = 72'd0;
    completed_p = 8'd0; completed_q = 8'd0; loaded_word = 72'd0;
    cases_verified = 32'd0; cycle_number = 32'sd0;
    completed_maps = 32'd0; boolean_results = 32'd0; map_index = 32'd0;
    for (gate_index = 32'd0; gate_index < 32'd8; gate_index = gate_index + 32'd1) begin
      pixel_index = 32'd0;
      for (frame_index = 32'd0; frame_index < 32'd1024; frame_index = frame_index + 32'd1)
        if (reference_y(map_preset(gate_index[2:0]), frame_index % 32'd32,
                        frame_index / 32'd32) >= 32'sd16) pixel_index = pixel_index + 32'd1;
      check(pixel_index == lit_count(gate_index[2:0]), "integer reference matches frozen counts");
    end
    check(defaults.BUTTON_DEBOUNCE_CYCLES == 32'd2000000, "real 20 ms debounce default");
    check(defaults.display_ctrl.MS_CYCLES == 32'd100000, "real top 1 ms default");
    check(defaults.display_ctrl.VBAT_WAIT_CYCLES == 32'd10000000, "real top 100 ms default");
    check(defaults.display_ctrl.DISPLAY_WAIT_CYCLES == 32'd5000000, "real top 50 ms default");
    check(defaults.display_ctrl.SHUTDOWN_CYCLES == 32'd350000000, "real top 3.5 s default");
    repeat (32'd5) @(negedge clk);
    cpu_resetn = 1'b1;
    @(posedge clk); #(32'd2);
    check(dut.host_rst_n === 1'b0, "host reset held after one release edge");
    @(posedge clk); #(32'd2);
    check(dut.host_rst_n === 1'b1, "host reset releases after two edges");
    repeat (32'd10) @(negedge clk);
    sw[0] = 1'b1;
    @(posedge clk); #(32'd2);
    check(dut.sw_meta[0] && !dut.sw_sync[0], "switch first synchronizer stage");
    @(posedge clk); #(32'd2);
    check(dut.sw_sync[0], "switch second synchronizer stage");
    @(negedge clk); sw[0] = 1'b0;
    for (gate_index = 32'd0; gate_index < 32'd8; gate_index = gate_index + 32'd1) begin
      saved_words = words_loaded;
      for (input_index = 32'd0; input_index < 32'd4; input_index = input_index + 32'd1)
        wait_case(gate_index[2:0], input_index[1], input_index[0]);
      check(words_loaded >= saved_words + 32'd2, "map then Boolean load for every select");
      check_frame(2'd0, gate_index[2:0], 1'b1, 1'b1);
    end
    check(cases_verified == 32'd32, "all original gate/input cases retained");
    $display("All 32 Boolean cases and eight complete 1024-pixel maps checked.");
    @(negedge clk); sw[6:5] = 2'd1;
    check_frame(2'd1, 3'd7, 1'b1, 1'b1);
    @(negedge clk); sw[6:5] = 2'd2;
    check_frame(2'd2, 3'd7, 1'b1, 1'b1);
    @(negedge clk); sw[6:5] = 2'd3;
    check_frame(2'd3, 3'd7, 1'b1, 1'b1);
    @(negedge clk); sw[6:5] = 2'd0;

    // Change display mode while data bytes are on the wire. The whole current
    // frame must keep its original snapshot in both directions.
    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd50);
    @(negedge clk); sw[6:5] = 2'd1;
    check_frame(2'd1, 3'd7, 1'b1, 1'b1);
    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd50);
    @(negedge clk); sw[6:5] = 2'd0;
    check_frame(2'd0, 3'd7, 1'b1, 1'b1);

    // Change Y before its text bytes are transmitted. An unsnapshotted Y would
    // now disagree with the X1/X2 values captured for this user frame.
    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd50);
    @(negedge clk); sw[0] = 1'b0;
    wait_case(3'd7, 1'b0, 1'b1);
    check_frame(2'd0, 3'd7, 1'b0, 1'b1);

    // A gate switch during a frame must finish the old map/text together, then
    // publish the new map only after its first completed Boolean result.
    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd50);
    @(negedge clk); sw[4:0] = 5'b01011;
    wait_case(3'd2, 1'b1, 1'b1);
    check_frame(2'd0, 3'd2, 1'b1, 1'b1);
    $display("Mode, Y, and gate changed during user frames; every frame checked.");

    // Preserve the earlier load-change and busy-start pin checks.
    @(negedge clk); sw[4:0] = 5'b00100;
    wait (bit_count == 32'd10);
    @(negedge clk); sw[4:0] = 5'b01001;
    saved_words = starts;
    wait (starts > saved_words);
    @(negedge clk);
    check(run_word === map_preset(3'd2) || run_word === preset(3'd2),
          "gate change during load uses latest selection before starting");
    wait_case(3'd2, 1'b1, 1'b0);
    check_frame(2'd0, 3'd2, 1'b1, 1'b0);
    wait_start(); repeat (32'd4) @(negedge clk);
    sw[4:0] = 5'b00011;
    wait_case(3'd0, 1'b1, 1'b1);

    @(negedge clk); sw[4:0] = 5'b00101;
    wait (loaded_word === map_preset(3'd1) && map_index == 32'd128);
    before_maps = completed_maps;
    @(negedge clk); sw[4:0] = 5'b01010;
    wait_case(3'd2, 1'b0, 1'b1);
    check_frame(2'd0, 3'd2, 1'b0, 1'b1);
    check(completed_maps >= before_maps + 32'd2, "finish sweep then sweep changed gate");

    @(negedge clk); sw[4:0] = 5'b01100;
    wait (loaded_word === map_preset(3'd3) && map_index == 32'd80 && run_pending);
    saved_words = words_loaded;
    aligned_cpu_reset("during map sweep", 1'b0);
    wait_case(3'd3, 1'b0, 1'b0);
    check(words_loaded >= saved_words + 32'd2, "reset restarts full map then Boolean load");
    check_frame(2'd0, 3'd3, 1'b0, 1'b0);

    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd100);
    aligned_cpu_reset("during SPI user frame", 1'b1);
    wait_case(3'd3, 1'b0, 1'b0);
    check_frame(2'd0, 3'd3, 1'b0, 1'b0);

    // Separate reset with known nonzero Boolean storage proves that early
    // chip reset cannot be hidden by outputs that were already zero.
    wait (dut.boolean_y == 7'd1 && dut.chip.core.y == 7'd1);
    check(dut.boolean_y == 7'd1, "nonzero Boolean value before aligned CPU RESET");
    aligned_cpu_reset("nonzero Boolean result", 1'b0);
    wait_case(3'd3, 1'b0, 1'b0);
    check_frame(2'd0, 3'd3, 1'b0, 1'b0);
    check(aligned_resets_checked == 32'd3, "all three reset-alignment scenarios exercised");

    before_shutdowns = monitor.shutdowns;
    repeat (32'd3) begin
      @(negedge clk); btnc = 1'b1;
      repeat (32'd2) @(negedge clk); btnc = 1'b0;
      repeat (32'd2) @(negedge clk);
    end
    repeat (32'd20) @(negedge clk);
    check(monitor.shutdowns == before_shutdowns && !oled_vdd && !oled_vbat,
          "button bounce does not toggle OLED");
    wait (monitor.phase == 32'd21 && monitor.data_index == 32'd120);
    @(negedge clk); btnc = 1'b1;
    for (wait_index = 32'd0;
         wait_index < 32'd100000 && monitor.shutdowns == before_shutdowns;
         wait_index = wait_index + 32'd1) @(negedge clk);
    check(btnc && monitor.shutdowns == before_shutdowns + 32'd1,
          "BTNC press triggers shutdown before release");
    repeat (32'd30) @(negedge clk);
    check(oled_vdd && oled_vbat && monitor.powerups == 32'd1,
          "held BTNC does not restart OLED");
    btnc = 1'b0;
    repeat (32'd30) @(negedge clk);
    check(oled_vdd && oled_vbat && monitor.shutdowns == before_shutdowns + 32'd1,
          "BTNC release does not toggle OLED");
    saved_words = boolean_results;
    repeat (32'd200) @(negedge clk);
    check(boolean_results > saved_words, "Boolean computation continues while OLED is off");
    press_button();
    wait (monitor.powerups == 32'd2);
    check_frame(2'd0, 3'd3, 1'b0, 1'b0);
    $display("Gate-change, reset-during-sweep, CPU-reset power, debounce, and BTNC tests passed.");
    // Let the falling-edge frame checker finish before comparing its count.
    #(32'd1);
    check(continuous_frames_checked == monitor.user_frames &&
          continuous_frames_checked > 32'd0, "all completed user frames verified");
    $display("Self-consistent user frames checked: %0d.", continuous_frames_checked);
    $display("Completed maps: %0d; Boolean results: %0d; requested cases: %0d.",
             completed_maps, boolean_results, cases_verified);
    $display("FPGA pin/protocol checks: %0d; SPI/power checks: %0d; failures: %0d.",
             checks, monitor.checks, failures);
    $display("ALL TESTS PASSED");
    $finish;
  end
  initial begin
    #(32'd200000000);
    $display("FAILED: 1 (OLED integration watchdog)");
    $finish;
  end
endmodule
