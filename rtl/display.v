module display (
    input clk,              // 14 MHz clock signal
    input enable,           // clock enable strobe,
    input rst,              // active high reset signal
    output vga_h_sync,      // horizontal VGA sync pulse
    output vga_v_sync,      // vertical VGA sync pulse
    output vga_red,         // red VGA signal
    output vga_grn,         // green VGA signal
    output vga_blu,         // blue VGA signal
    input address,          // address bus
    input w_en,             // active high write enable strobe
    input [7:0] din,        // 8-bit data bus (input)
    input [1:0] mode,       // 2-bit mode setting for pixel doubling
    input [2:0] fg_colour,  // 3 bit background colour
    input [2:0] bg_colour,  // 3 bit foreground colour
    input clr_screen        // clear screen button
);

    //////////////////////////////////////////////////////////////////////////
    // Registers and Parameters

    // video structure constants
    parameter h_pixels = 910;    // horizontal pixels per line
    parameter v_lines  = 262;    // vertical lines per frame
    parameter h_pulse  = 65;     // hsync pulse length (was: 96)
    parameter v_pulse  = 2;      // vsync pulse length
    parameter hbp      = 208;    // end of horizontal back porch
    parameter hfp      = 848;    // beginning of horizontal front porch
    parameter vbp      = 42;     // end of vertical back porch
    parameter vfp      = 234;    // beginning of vertical front porch

    // registers for storing the horizontal & vertical counters
    reg  [9:0] h_cnt;  // horizontal counter
    reg  [9:0] v_cnt;  // vertical counter
	 reg  [4:0] v_dot;  // vertical counter within character matrix (0-7)
    wire [3:0] h_dot;  // horizontal counter within character matrix (0-7)
    
    // hardware cursor registers
    wire [10:0] cursor;
    reg  [5:0]  h_cursor;
    reg  [4:0]  v_cursor;

    // vram indexing registers
    reg  [5:0] vram_h_addr;
    reg  [4:0] vram_v_addr;
    reg  [4:0] vram_start_addr;
    reg  [4:0] vram_end_addr;
    wire [4:0] vram_clr_addr;

    // vram registers
    wire [10:0] vram_r_addr;
    reg  [10:0] vram_w_addr;
    reg         vram_w_en;
    reg  [5:0]  vram_din;
    wire [5:0]  vram_dout;

    // font rom registers
    wire [5:0] font_char;
    wire [3:0] font_pixel;
    wire [4:0] font_line;
    wire font_out;

    // cpu control registers
    reg char_seen;

    // active region strobes
    wire h_active = (h_cnt >= hbp && h_cnt < hfp);
    wire v_active = (v_cnt >= vbp && v_cnt < vfp);

    // horizontal and vertical counters
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
            v_dot <= 5'd0;
        end
        else begin
            if (h_cnt < h_pixels)
                h_cnt <= h_cnt + 1;
            else begin
                // reset horizontal counters
                h_cnt <= 0;

                if (v_cnt < v_lines) begin
                    v_cnt <= v_cnt + 1;
                    
                    if (v_active) begin
                        v_dot <= v_dot + 1;  

                        if (v_dot == 5'd7)  
                            v_dot <= 0;
                    end
                end
                else begin
                    // reset vertical counters
                    v_cnt <= 0;
                    v_dot <= 0;
                end
            end
        end
    end

    // count 16 pixels, so 640px / 16 = 40 characters
    assign h_dot = h_active ? h_cnt[3:0] : 4'd0;

    //////////////////////////////////////////////////////////////////////////
    // Character ROM

    font_rom font_rom(
        .clk(clk),
        .mode(mode),
        .character(font_char),
        .pixel(font_pixel),
        .line(font_line),
        .out(font_out)
    );

    //////////////////////////////////////////////////////////////////////////
    // Video RAM

    vram vram(
        .clk(clk),
        .read_addr(vram_r_addr),
        .write_addr(vram_w_addr),
        .r_en(h_active),
        .w_en(vram_w_en),
        .din(vram_din),
        .dout(vram_dout)
    );

    //////////////////////////////////////////////////////////////////////////
    // Video Signal Generation

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vram_h_addr <= 'd0;
            vram_v_addr <= 'd0;
        end 
		  else begin
            // start the pipeline for reading vram and font details
            // 3 pixel clock cycles early
            if (h_dot == 4'hC)
                vram_h_addr <= vram_h_addr + 'd1;

            // advance to next row when last display line is reached for row
            if (v_dot == 5'd7 && h_cnt == 10'd0)   
                vram_v_addr <= vram_v_addr + 'd1;

            // clear the address registers if we're not in visible area
            if (~h_active) vram_h_addr <= 'd0;
            if (~v_active) vram_v_addr <= vram_start_addr;
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // Cursor blink

    reg blink;
    reg [22:0] blink_div;
    always @(posedge clk or posedge rst)
    begin
        if (rst)
            blink_div <= 0;
        else
        begin
            blink_div <= blink_div + 1;

            if (blink_div == 23'd0)
                blink <= ~blink;
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // Pipeline and VGA signals

    // vram to font rom to display pipeline assignments
    assign cursor = {v_cursor, h_cursor};
    assign vram_r_addr = {vram_v_addr, vram_h_addr};

    assign font_char = (vram_r_addr != cursor) ? vram_dout : (blink) ? 6'd0 : 6'd32;
    assign font_pixel = h_dot + 1; // offset by one to get pixel into right cycle,
                                   // font output one pixel clk behind
    assign font_line = v_dot * 2 + 4;

    // vga signals out to monitor
    assign vga_red = (h_active & v_active) ? (font_out ? fg_colour[2] : bg_colour[2]) : 1'b0;
    assign vga_grn = (h_active & v_active) ? (font_out ? fg_colour[1] : bg_colour[1]) : 1'b0;    
	 assign vga_blu = (h_active & v_active) ? (font_out ? fg_colour[0] : bg_colour[0]) : 1'b0;

    assign vga_h_sync = (h_cnt < h_pulse) ? 0 : 1;
    assign vga_v_sync = (v_cnt < v_pulse) ? 0 : 1;

    //////////////////////////////////////////////////////////////////////////
    // CPU control and hardware cursor

    assign vram_clr_addr = vram_end_addr + {3'd0, vram_v_addr[1:0]};

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            h_cursor <= 6'd0;
            v_cursor <= 5'd0;
            char_seen <= 'b0;
            vram_start_addr <= 5'd0;
            vram_end_addr <= 5'd24;
        end
        else
        begin
            vram_w_en <= 0;

            if (clr_screen)
            begin
                // return to top of screen
                h_cursor <= 6'd0;
                v_cursor <= 5'd0;

                vram_start_addr <= 5'd0;
                vram_end_addr <= 5'd24;

                // clear the screen
                vram_w_addr <= {vram_v_addr, vram_h_addr};
                vram_din <= 6'd32;
                vram_w_en <= 1;
            end
            else
            begin
                // cursor overflow handling
                if (h_cursor == 6'd40)
                begin
                    h_cursor <= 6'd0;
                    v_cursor <= v_cursor + 'd1;
                end

                if (v_cursor == vram_end_addr)
                begin
                    vram_start_addr <= vram_start_addr + 'd1;
                    vram_end_addr <= vram_end_addr + 'd1;
                end

                if (address == 1'b0) // address low == TX register
                begin
                    if (enable & w_en & ~char_seen)
                    begin
                        // incoming character
                        char_seen <= 1;

                        case(din)
                        8'h0D,
                        8'h8D: begin
                            // handle carriage return
                            h_cursor <= 0;
                            v_cursor <= v_cursor + 'd1;
                        end

                        8'h00,
                        8'h0A,
                        8'h9B,
                        8'h7F: begin
                            // ignore the escape key
                            h_cursor <= 0;
                        end

                        default: begin
                            vram_w_addr <= cursor;
                            vram_din <= {~din[6], din[4:0]};
                            vram_w_en <= 1;
                            h_cursor <= h_cursor + 1;
                        end
                        endcase
                    end
                    else if(~enable & ~w_en)
                        char_seen <= 0;
                end
                else
                begin
                    vram_w_addr <= {vram_clr_addr, vram_h_addr};
                    vram_din <= 6'd32;
                    vram_w_en <= 1;
                end
            end
        end
    end

endmodule