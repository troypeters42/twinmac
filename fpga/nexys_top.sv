`default_nettype none
`timescale 1ns/1ps

module nexys_top (
  input  wire logic clk,
  input  wire logic cpu_resetn,
  input  wire logic btnc,
  input  wire logic [4:0] sw,
  output wire [7:0] led,
  output wire oled_dc,
  output wire oled_res,
  output wire oled_sclk,
  output wire oled_sdin,
  output wire oled_vbat,
  output wire oled_vdd
);
  typedef enum logic [3:0] {
    INIT_WAIT = 4'd0,
    CHECK_GATE = 4'd1,
    LOAD_SETUP = 4'd2,
    LOAD_HIGH = 4'd3,
    LOAD_LOW = 4'd4,
    X1_SETUP = 4'd5,
    X1_HIGH = 4'd6,
    X1_LOW = 4'd7,
    X2_SETUP = 4'd8,
    X2_HIGH = 4'd9,
    X2_LOW = 4'd10,
    START_HIGH = 4'd11,
    START_LOW = 4'd12,
    WAIT_DONE = 4'd13
  } state_e;

  (* ASYNC_REG = "TRUE" *) logic [1:0] reset_pipe;
  (* ASYNC_REG = "TRUE" *) logic [4:0] sw_meta, sw_sync;
  wire host_rst_n;
  state_e state, next_state;
  logic [2:0] phase_count, loaded_gate;
  logic phase_done, weights_valid;
  logic [6:0] bit_index;
  logic [71:0] weight_word;
  logic [7:0] data_byte;
  logic [7:0] chip_ui, chip_uio;
  wire [7:0] chip_uo, chip_uio_out, chip_uio_oe;

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

  always_ff @(posedge clk or negedge cpu_resetn) begin
    if (!cpu_resetn) reset_pipe <= 2'b00;
    else reset_pipe <= {reset_pipe[0], 1'b1};
  end
  assign host_rst_n = reset_pipe[1];

  always_ff @(posedge clk or negedge host_rst_n) begin
    if (!host_rst_n) begin
      sw_meta <= 5'd0;
      sw_sync <= 5'd0;
    end else begin
      sw_meta <= sw;
      sw_sync <= sw_meta;
    end
  end

  assign phase_done = (phase_count == 3'd4);

  always_comb begin
    next_state = state;
    unique case (state)
      INIT_WAIT: if (phase_done) next_state = CHECK_GATE;
      CHECK_GATE: begin
        if (!weights_valid || (sw_sync[4:2] != loaded_gate)) next_state = LOAD_SETUP;
        else next_state = X1_SETUP;
      end
      LOAD_SETUP: if (phase_done) next_state = LOAD_HIGH;
      LOAD_HIGH: if (phase_done) next_state = LOAD_LOW;
      LOAD_LOW: begin
        if (phase_done) begin
          if (bit_index == 7'd0) next_state = CHECK_GATE;
          else next_state = LOAD_SETUP;
        end
      end
      X1_SETUP: if (phase_done) next_state = X1_HIGH;
      X1_HIGH: if (phase_done) next_state = X1_LOW;
      X1_LOW: if (phase_done) next_state = X2_SETUP;
      X2_SETUP: if (phase_done) next_state = X2_HIGH;
      X2_HIGH: if (phase_done) next_state = X2_LOW;
      X2_LOW: if (phase_done) next_state = START_HIGH;
      START_HIGH: if (phase_done) next_state = START_LOW;
      START_LOW: if (phase_done) next_state = WAIT_DONE;
      WAIT_DONE: if (chip_uo[7]) next_state = CHECK_GATE;
      default: next_state = INIT_WAIT;
    endcase
  end

  always_ff @(posedge clk or negedge host_rst_n) begin
    if (!host_rst_n) begin
      state <= INIT_WAIT;
      phase_count <= 3'd0;
      loaded_gate <= 3'd0;
      weights_valid <= 1'b0;
      bit_index <= 7'd71;
      weight_word <= 72'd0;
      data_byte <= 8'd0;
    end else begin
      state <= next_state;
      if ((state == CHECK_GATE) || (state == WAIT_DONE) || phase_done) begin
        phase_count <= 3'd0;
      end else begin
        phase_count <= phase_count + 3'd1;
      end
      if (state == CHECK_GATE) begin
        if (!weights_valid || (sw_sync[4:2] != loaded_gate)) begin
          weight_word <= gate_preset(sw_sync[4:2]);
          loaded_gate <= sw_sync[4:2];
          bit_index <= 7'd71;
          weights_valid <= 1'b0;
        end else begin
          data_byte <= {7'd0, sw_sync[0]};
        end
      end
      if ((state == LOAD_LOW) && phase_done) begin
        if (bit_index == 7'd0) weights_valid <= 1'b1;
        else bit_index <= bit_index - 7'd1;
      end
      if ((state == X1_LOW) && phase_done) data_byte <= {7'd0, sw_sync[1]};
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

  tt_um_troypeters42_twinmac chip (
    .ui_in(chip_ui),
    .uo_out(chip_uo),
    .uio_in(chip_uio),
    .uio_out(chip_uio_out),
    .uio_oe(chip_uio_oe),
    .ena(1'b1),
    .clk(clk),
    .rst_n(cpu_resetn)
  );

  assign led = chip_uo;
  assign oled_vdd = 1'b1;
  assign oled_vbat = 1'b1;
  assign oled_res = 1'b0;
  assign oled_dc = 1'b0;
  assign oled_sclk = 1'b0;
  assign oled_sdin = 1'b0;
  wire _unused = &{btnc, chip_uio_out, chip_uio_oe, 1'b0};
endmodule
