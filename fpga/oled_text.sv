`default_nettype none
`timescale 1ns/1ps

module oled_text (
  input wire logic clk, rst_n,
  input wire logic frame_start,
  input wire logic [8:0] frame_addr,
  input wire logic [1:0] mode,
  input wire logic [2:0] gate_select,
  input wire logic bool_x1, bool_x2,
  input wire logic [6:0] bool_y,
  input wire logic [7:0] map_data,
  output wire logic [6:0] map_addr,
  output logic [7:0] frame_data
);
  logic [1:0] saved_mode;
  logic [2:0] saved_gate;
  logic saved_x1, saved_x2;
  logic [6:0] saved_y;
  logic [6:0] column;
  logic [1:0] page;
  logic [3:0] character;
  logic [2:0] glyph_column;
  logic [7:0] letter;
  assign map_addr = {frame_addr[8:7], frame_addr[4:0]};

  function automatic logic [7:0] gate_letter(input logic [2:0] selection,
                                            input logic [1:0] index);
    logic [31:0] name;
    begin
      case (selection)
        3'd1: name = 32'h4F522020;
        3'd2: name = 32'h584F5220;
        3'd3: name = 32'h4E414E44;
        3'd4: name = 32'h4E4F5220;
        3'd5: name = 32'h584E4F52;
        default: name = 32'h414E4420;
      endcase
      case (index)
        2'd0: gate_letter = name[31:24];
        2'd1: gate_letter = name[23:16];
        2'd2: gate_letter = name[15:8];
        default: gate_letter = name[7:0];
      endcase
    end
  endfunction

  function automatic logic [7:0] text_letter(input logic [1:0] row,
                                            input logic [3:0] index);
    begin
      text_letter = 8'h20;
      case (row)
        2'd0: begin
          case (index)
            4'd0: text_letter = 8'h47;
            4'd1: text_letter = 8'h41;
            4'd2: text_letter = 8'h54;
            4'd3: text_letter = 8'h45;
            4'd4: text_letter = 8'h3A;
            4'd6, 4'd7, 4'd8, 4'd9:
              text_letter = gate_letter(saved_gate, index[1:0] - 2'd2);
            default: text_letter = 8'h20;
          endcase
        end
        2'd1: begin
          case (index)
            4'd0, 4'd5: text_letter = 8'h58;
            4'd1: text_letter = 8'h31;
            4'd2, 4'd7: text_letter = 8'h3D;
            4'd3: text_letter = saved_x1 ? 8'h31 : 8'h30;
            4'd6: text_letter = 8'h32;
            4'd8: text_letter = saved_x2 ? 8'h31 : 8'h30;
            default: text_letter = 8'h20;
          endcase
        end
        2'd2: begin
          case (index)
            4'd0: text_letter = 8'h59;
            4'd1: text_letter = 8'h3D;
            4'd2: text_letter = saved_y[0] ? 8'h31 : 8'h30;
            default: text_letter = 8'h20;
          endcase
        end
        default: text_letter = 8'h20;
      endcase
    end
  endfunction

  function automatic logic [7:0] font_column(input logic [7:0] value,
                                            input logic [2:0] index);
    logic [39:0] glyph;
    begin
      case (value)
        8'h41: glyph = 40'h7E0909097E;
        8'h44: glyph = 40'h7F4141413E;
        8'h45: glyph = 40'h7F49494941;
        8'h47: glyph = 40'h3E4149493A;
        8'h4E: glyph = 40'h7F0608307F;
        8'h4F: glyph = 40'h3E4141413E;
        8'h52: glyph = 40'h7F09192946;
        8'h54: glyph = 40'h01017F0101;
        8'h58: glyph = 40'h6314081463;
        8'h59: glyph = 40'h0304780403;
        8'h30: glyph = 40'h3E5149453E;
        8'h31: glyph = 40'h00427F4000;
        8'h32: glyph = 40'h4261514946;
        8'h3A: glyph = 40'h0000360000;
        8'h3D: glyph = 40'h1414141414;
        default: glyph = 40'd0;
      endcase
      case (index)
        3'd0: font_column = glyph[39:32];
        3'd1: font_column = glyph[31:24];
        3'd2: font_column = glyph[23:16];
        3'd3: font_column = glyph[15:8];
        3'd4: font_column = glyph[7:0];
        default: font_column = 8'd0;
      endcase
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      saved_mode <= 2'd0;
      saved_gate <= 3'd0;
      saved_x1 <= 1'b0;
      saved_x2 <= 1'b0;
      saved_y <= 7'd0;
    end else if (frame_start) begin
      saved_mode <= mode;
      saved_gate <= gate_select;
      saved_x1 <= bool_x1;
      saved_x2 <= bool_x2;
      saved_y <= bool_y;
    end
  end

  always_comb begin
    column = frame_addr[6:0];
    page = frame_addr[8:7];
    character = (column - 7'd40) >> 3'd3;
    glyph_column = column[2:0];
    letter = text_letter(page, character);
    frame_data = 8'd0;
    if (saved_mode == 2'd1) frame_data = 8'hFF;
    else if (saved_mode == 2'd2) begin
      if (column == 7'd0 || column == 7'd127) frame_data = 8'hFF;
      else if (page == 2'd0) frame_data = 8'h01;
      else if (page == 2'd3) frame_data = 8'h80;
    end else if (column < 7'd32) frame_data = map_data;
    else if (column >= 7'd40) frame_data = font_column(letter, glyph_column);
  end
endmodule
