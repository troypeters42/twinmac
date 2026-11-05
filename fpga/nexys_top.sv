`default_nettype none
`timescale 1ns/1ps

module nexys_top #(
  parameter integer unsigned OLED_MS_CYCLES = 32'd100000,
  parameter integer unsigned OLED_VBAT_WAIT_CYCLES = 32'd10000000,
  parameter integer unsigned OLED_DISPLAY_WAIT_CYCLES = 32'd5000000,
  parameter integer unsigned OLED_SHUTDOWN_CYCLES = 32'd350000000,
  parameter integer unsigned BUTTON_DEBOUNCE_CYCLES = 32'd2000000
) (
  input wire logic clk,
  input wire logic cpu_resetn,
  input wire logic btnc,
  input wire logic [6:0] sw,
  output wire [7:0] led,
  output wire oled_dc, oled_res, oled_sclk, oled_sdin, oled_vbat, oled_vdd
);
  typedef enum logic [4:0] {
    INIT_WAIT = 5'd0, BEGIN_MAP = 5'd1, WAIT_DISPLAY = 5'd2,
    LOAD_SETUP = 5'd3, LOAD_HIGH = 5'd4, LOAD_LOW = 5'd5,
    CHECK_RUN = 5'd6, X1_SETUP = 5'd7, X1_HIGH = 5'd8, X1_LOW = 5'd9,
    X2_SETUP = 5'd10, X2_HIGH = 5'd11, X2_LOW = 5'd12,
    START_HIGH = 5'd13, START_LOW = 5'd14, WAIT_DONE = 5'd15,
    RESULT = 5'd16, END_MAP = 5'd17, BEGIN_BOOL = 5'd18
  } state_e;
  (* ASYNC_REG = "TRUE" *) logic [1:0] reset_pipe = 2'b00;
  (* ASYNC_REG = "TRUE" *) logic [6:0] sw_meta, sw_sync;
  // FPGA configuration initializes this separate power-on reset. CPU RESET
  // never enters the OLED power, SPI, or button-reset domain.
  (* ASYNC_REG = "TRUE" *) logic [1:0] oled_reset_pipe = 2'b00;
  (* ASYNC_REG = "TRUE" *) logic btn_meta, btn_sync;
  logic btn_stable, btn_pulse;
  logic [31:0] debounce_count;
  wire host_rst_n, oled_rst_n;
  state_e state, next_state;
  logic [2:0] phase_count, loaded_gate, boolean_gate;
  logic phase_done, map_mode, map_valid;
  logic [4:0] map_x, map_y;
  logic [6:0] bit_index;
  logic [71:0] weight_word;
  logic [7:0] data_byte, run_x1, run_x2;
  logic boolean_x1, boolean_x2;
  logic [6:0] boolean_y;
  logic [7:0] chip_ui, chip_uio;
  wire [7:0] chip_uo, chip_uio_out, chip_uio_oe;
  wire display_start, display_busy, map_write_en, map_write_lit;
  wire [8:0] display_addr;
  wire [6:0] map_addr;
  wire [7:0] map_data, display_data;

  function automatic logic [71:0] gate_preset(input logic [2:0] gate_select);
    case (gate_select)
      3'd1: gate_preset = 72'h00_FF_01_FF_01_01_00_01_01;
      3'd2: gate_preset = 72'h00_FE_01_FF_01_01_00_01_01;
      3'd3: gate_preset = 72'h01_FF_00_FF_01_01_00_01_01;
      3'd4: gate_preset = 72'h01_01_FF_FF_01_01_00_01_01;
      3'd5: gate_preset = 72'h01_02_FF_FF_01_01_00_01_01;
      default: gate_preset = 72'h00_01_00_FF_01_01_00_01_01;
    endcase
  endfunction
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

  always_ff @(posedge clk or negedge cpu_resetn) begin
    if (!cpu_resetn) reset_pipe <= 2'b00;
    else reset_pipe <= {reset_pipe[0], 1'b1};
  end
  assign host_rst_n = reset_pipe[1];
  always_ff @(posedge clk) oled_reset_pipe <= {oled_reset_pipe[0], 1'b1};
  assign oled_rst_n = oled_reset_pipe[1];

  always_ff @(posedge clk or negedge host_rst_n) begin
    if (!host_rst_n) begin sw_meta <= 7'd0; sw_sync <= 7'd0; end
    else begin sw_meta <= sw; sw_sync <= sw_meta; end
  end
  always_ff @(posedge clk or negedge oled_rst_n) begin
    if (!oled_rst_n) begin
      btn_meta <= 1'b0;
      btn_sync <= 1'b0;
      btn_stable <= 1'b0;
      btn_pulse <= 1'b0;
      debounce_count <= 32'd0;
    end else begin
      btn_meta <= btnc;
      btn_sync <= btn_meta;
      btn_pulse <= 1'b0;
      if (btn_sync == btn_stable) debounce_count <= 32'd0;
      else if (debounce_count == BUTTON_DEBOUNCE_CYCLES - 32'd1) begin
        btn_stable <= btn_sync;
        debounce_count <= 32'd0;
        if (btn_sync) btn_pulse <= 1'b1;
      end else debounce_count <= debounce_count + 32'd1;
    end
  end
  assign phase_done = (phase_count == 3'd4);
  assign map_write_en = (state == RESULT) && map_mode && host_rst_n;
  assign map_write_lit = (chip_uo[6:0] >= 7'd16);

  always_comb begin
    next_state = state;
    unique case (state)
      INIT_WAIT: if (phase_done) next_state = BEGIN_MAP;
      BEGIN_MAP: next_state = WAIT_DISPLAY;
      WAIT_DISPLAY: if (!display_busy) next_state = LOAD_SETUP;
      LOAD_SETUP: if (phase_done) next_state = LOAD_HIGH;
      LOAD_HIGH: if (phase_done) next_state = LOAD_LOW;
      LOAD_LOW: if (phase_done) begin
        if (bit_index == 7'd0) next_state = CHECK_RUN;
        else next_state = LOAD_SETUP;
      end
      CHECK_RUN: begin
        if ((!map_mode || (map_x == 5'd0 && map_y == 5'd0)) &&
            sw_sync[4:2] != loaded_gate) next_state = BEGIN_MAP;
        else next_state = X1_SETUP;
      end
      X1_SETUP: if (phase_done) next_state = X1_HIGH;
      X1_HIGH: if (phase_done) next_state = X1_LOW;
      X1_LOW: if (phase_done) next_state = X2_SETUP;
      X2_SETUP: if (phase_done) next_state = X2_HIGH;
      X2_HIGH: if (phase_done) next_state = X2_LOW;
      X2_LOW: if (phase_done) next_state = START_HIGH;
      START_HIGH: if (phase_done) next_state = START_LOW;
      START_LOW: if (phase_done) next_state = WAIT_DONE;
      WAIT_DONE: if (chip_uo[7]) next_state = RESULT;
      RESULT: begin
        if (map_mode && map_x == 5'd31 && map_y == 5'd31) next_state = END_MAP;
        else next_state = CHECK_RUN;
      end
      END_MAP: begin
        if (sw_sync[4:2] != loaded_gate) next_state = BEGIN_MAP;
        else next_state = BEGIN_BOOL;
      end
      BEGIN_BOOL: next_state = LOAD_SETUP;
      default: next_state = INIT_WAIT;
    endcase
  end

  always_ff @(posedge clk or negedge host_rst_n) begin
    if (!host_rst_n) begin
      state <= INIT_WAIT;
      phase_count <= 3'd0;
      loaded_gate <= 3'd0;
      boolean_gate <= 3'd0;
      map_mode <= 1'b1;
      map_valid <= 1'b0;
      map_x <= 5'd0;
      map_y <= 5'd0;
      bit_index <= 7'd71;
      weight_word <= 72'd0;
      data_byte <= 8'd0;
      run_x1 <= 8'd0;
      run_x2 <= 8'd0;
      boolean_x1 <= 1'b0;
      boolean_x2 <= 1'b0;
      boolean_y <= 7'd0;
    end else begin
      state <= next_state;
      if ((state == CHECK_RUN) || (state == WAIT_DONE) || (state == RESULT) ||
          (state == WAIT_DISPLAY) || (state == BEGIN_MAP) || (state == BEGIN_BOOL) ||
          (state == END_MAP) || phase_done) phase_count <= 3'd0;
      else phase_count <= phase_count + 3'd1;
      if (state == BEGIN_MAP) begin
        loaded_gate <= sw_sync[4:2];
        weight_word <= map_preset(sw_sync[4:2]);
        map_mode <= 1'b1;
        map_valid <= 1'b0;
        map_x <= 5'd0;
        map_y <= 5'd0;
        bit_index <= 7'd71;
      end
      if (state == BEGIN_BOOL) begin
        weight_word <= gate_preset(loaded_gate);
        bit_index <= 7'd71;
        map_mode <= 1'b0;
      end
      if (state == LOAD_LOW && phase_done && bit_index != 7'd0)
        bit_index <= bit_index - 7'd1;
      if (state == CHECK_RUN) begin
        data_byte <= map_mode ? {3'd0, map_x} : {7'd0, sw_sync[0]};
        run_x1 <= map_mode ? {3'd0, map_x} : {7'd0, sw_sync[0]};
      end
      if (state == X1_LOW && phase_done) begin
        data_byte <= map_mode ? {3'd0, map_y} : {7'd0, sw_sync[1]};
        run_x2 <= map_mode ? {3'd0, map_y} : {7'd0, sw_sync[1]};
      end
      if (state == RESULT) begin
        if (map_mode) begin
          if (map_x != 5'd31) map_x <= map_x + 5'd1;
          else if (map_y != 5'd31) begin map_x <= 5'd0; map_y <= map_y + 5'd1; end
        end else begin
          boolean_gate <= loaded_gate;
          boolean_x1 <= run_x1[0];
          boolean_x2 <= run_x2[0];
          boolean_y <= chip_uo[6:0];
          map_valid <= 1'b1;
        end
      end
    end
  end
  always_comb begin
    chip_ui = data_byte;
    chip_uio = 8'd0;
    chip_uio[0] = weight_word[bit_index];
    unique case (state)
      LOAD_HIGH: chip_uio[1] = 1'b1;
      X1_HIGH: chip_uio[3] = 1'b1;
      X2_HIGH: chip_uio[4] = 1'b1;
      START_HIGH: chip_uio[2] = 1'b1;
      default: begin end
    endcase
  end

  // FPGA mapping preference only: no ASIC source or pipeline is changed.
  (* use_dsp = "yes" *) tt_um_troypeters42_twinmac chip (
    .ui_in(chip_ui), .uo_out(chip_uo), .uio_in(chip_uio),
    .uio_out(chip_uio_out), .uio_oe(chip_uio_oe),
    .ena(1'b1), .clk(clk), .rst_n(cpu_resetn)
  );
  assign led = chip_uo;
  oled_map bitmap (
    .clk(clk), .write_en(map_write_en), .write_x(map_x), .write_y(map_y),
    .write_lit(map_write_lit), .read_addr(map_addr), .read_data(map_data)
  );
  oled_text render (
    .clk(clk), .rst_n(oled_rst_n), .frame_start(display_start), .frame_addr(display_addr),
    .mode(sw_sync[6:5]), .gate_select(boolean_gate), .bool_x1(boolean_x1),
    .bool_x2(boolean_x2), .bool_y(boolean_y), .map_data(map_data),
    .map_addr(map_addr), .frame_data(display_data)
  );
  oled_ctrl #(.MS_CYCLES(OLED_MS_CYCLES), .VBAT_WAIT_CYCLES(OLED_VBAT_WAIT_CYCLES),
              .DISPLAY_WAIT_CYCLES(OLED_DISPLAY_WAIT_CYCLES),
              .SHUTDOWN_CYCLES(OLED_SHUTDOWN_CYCLES)) display_ctrl (
    .clk(clk), .rst_n(oled_rst_n), .toggle(btn_pulse), .frame_enable(map_valid),
    .frame_data(display_data), .frame_addr(display_addr),
    .frame_start(display_start), .frame_busy(display_busy),
    .oled_dc(oled_dc), .oled_res(oled_res), .oled_sclk(oled_sclk), .oled_sdin(oled_sdin),
    .oled_vbat(oled_vbat), .oled_vdd(oled_vdd)
  );
  wire _unused = &{chip_uio_out, chip_uio_oe, 1'b0};
endmodule
