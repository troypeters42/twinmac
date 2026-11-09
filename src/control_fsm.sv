`default_nettype none
`timescale 1ns/1ps

module control_fsm (
  input  wire logic clk,
  input  wire logic rst_n,
  input  wire logic start,
  output logic mac0_en,
  output logic mac1_en,
  output logic mac_first,
  output logic [1:0] operand_sel,
  output logic hidden_en,
  output logic output_en,
  output logic done
);
  typedef enum logic [2:0] {
    IDLE = 3'd0,
    STEP1 = 3'd1,
    STEP2 = 3'd2,
    STEP3 = 3'd3,
    STEP4 = 3'd4,
    STEP5 = 3'd5,
    STEP6 = 3'd6
  } state_t;

  state_t state;
  state_t next_state;

  always_comb begin
    next_state = IDLE;
    mac0_en = 1'b0;
    mac1_en = 1'b0;
    mac_first = 1'b0;
    operand_sel = 2'd0;
    hidden_en = 1'b0;
    output_en = 1'b0;

    unique case (state)
      IDLE: begin
        if (start) begin
          next_state = STEP1;
        end
      end
      STEP1: begin
        next_state = STEP2;
        mac0_en = 1'b1;
        mac1_en = 1'b1;
        mac_first = 1'b1;
      end
      STEP2: begin
        next_state = STEP3;
        mac0_en = 1'b1;
        mac1_en = 1'b1;
        operand_sel = 2'd1;
      end
      STEP3: begin
        next_state = STEP4;
        hidden_en = 1'b1;
      end
      STEP4: begin
        next_state = STEP5;
        mac0_en = 1'b1;
        mac_first = 1'b1;
        operand_sel = 2'd2;
      end
      STEP5: begin
        next_state = STEP6;
        mac0_en = 1'b1;
        operand_sel = 2'd3;
      end
      STEP6: begin
        next_state = IDLE;
        output_en = 1'b1;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      done <= 1'b0;
    end else begin
      state <= next_state;
      done <= (state == STEP6);
    end
  end
endmodule
