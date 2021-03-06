module display (
	 input reset,            // active high reset signal	 
	 
    input sys_clock,        // system clock
	 input pixel_clken,      // pixel clock enable	 
    input cpu_clken,        // cpu clock enable

	 input clr_screen,       // clear screen button
	 
	 // video output	
    output       vga_h_sync, // horizontal sync pulse
    output       vga_v_sync, // vertical sync pulse
    output [5:0] vga_red,    // red signal
    output [5:0] vga_grn,    // green signal
    output [5:0] vga_blu,    // blue signal
	 
	 output reg ready,       // display ready (PB7 of CIA)

	 // cpu interface
    input address,          // address bus
    input w_en,             // active high write enable strobe
    input [7:0] din,        // 8-bit data bus (input)   
	 output reg [6:0] dout   // input data is also seen as output
);

    //////////////////////////////////////////////////////////////////////////
    // Registers and Parameters

    // video structure constants
    parameter h_pixels = 455; // 910;    // horizontal pixels per line    
    parameter h_pulse  = 32;  // 65;     // hsync pulse length 
    parameter hbp      = 104; // 208;    // end of horizontal back porch
    parameter hfp      = 424; // 848;    // beginning of horizontal front porch	 
    parameter v_lines  = 262;    // vertical lines per frame
    parameter v_pulse  = 2;      // vsync pulse length    
	 parameter vbp      = 42;     // end of vertical back porch
    parameter vfp      = 234;    // beginning of vertical front porch

    // registers for storing the horizontal & vertical counters
    reg  [9:0] h_cnt;  // horizontal counter
    reg  [9:0] v_cnt;  // vertical counter
	 reg  [2:0] v_dot;  // vertical counter within character matrix (0-7) 
    wire [2:0] h_dot;  // horizontal counter within character matrix (0-7)
    
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
    wire [2:0] font_pixel;
    wire [4:0] font_line;
    wire font_out;

    // active region strobes
    wire h_active = (h_cnt >= hbp && h_cnt < hfp);
    wire v_active = (v_cnt >= vbp && v_cnt < vfp);	 

    // horizontal and vertical counters
    always @(posedge sys_clock or posedge reset) begin
        if (reset) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
            v_dot <= 5'd0;
        end
        else 
		  if(pixel_clken) begin
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
    
    assign h_dot = h_active ? h_cnt[2:0] : 0;

    //////////////////////////////////////////////////////////////////////////
    // Character ROM

    font_rom font_rom(
        .clk(sys_clock),        
        .character(font_char),
        .pixel(font_pixel),
        .line(font_line),
        .out(font_out)
    );

    //////////////////////////////////////////////////////////////////////////
    // Video RAM

    display_ram display_ram(
        .clk(sys_clock),
        .read_addr(vram_r_addr),
        .write_addr(vram_w_addr),
        .r_en(h_active),
        .w_en(vram_w_en),
        .din(vram_din),
        .dout(vram_dout)
    );

    //////////////////////////////////////////////////////////////////////////
    // Video Signal Generation

    always @(posedge sys_clock or posedge reset) begin
        if (reset) begin
            vram_h_addr <= 0;
            vram_v_addr <= 0;
        end 
		  else 
		  if(pixel_clken) begin
            // start the pipeline for reading vram and font details
            // 3 pixel clock cycles early
            if (h_dot == 6)
                vram_h_addr <= vram_h_addr + 1;

            // advance to next row when last display line is reached for row
            if (v_dot == 7 && h_cnt == 0)   
                vram_v_addr <= vram_v_addr + 1;

            // clear the address registers if we're not in visible area
            if (~h_active) vram_h_addr <= 0;
            if (~v_active) vram_v_addr <= vram_start_addr;
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // Cursor blinking. 
	 // On the real Apple-I it's made via a 555 configured to trigger 1.92 Hz

	 localparam blink_max    = 7457385;                  // 14318180/2/(1.92/2)
	 localparam blink_thr    = blink_max * 3/4;          // ~3/4 duty cycle
	 localparam blink_rewind = blink_thr - (455 * 262);  // sets blinking 1 frame before cursor turns on
	 
    reg [31:0] blink_cnt;
	 wire cursor_on = blink_cnt > blink_thr;
    always @(posedge sys_clock or posedge reset)
    begin	     
        if (reset) 	      
            blink_cnt <= 0;						  
        else 
		  if(pixel_clken) begin		      
		           if(cpu_clken & w_en & ready) blink_cnt <= blink_rewind;    // when a char is received, blinking is turned off briefly
		      else if(blink_cnt > blink_max)    blink_cnt <= 0;
				else                              blink_cnt <= blink_cnt + 1;
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // Pipeline and VGA signals

    // vram to font rom to display pipeline assignments
    assign cursor = {v_cursor, h_cursor};
    assign vram_r_addr = {vram_v_addr, vram_h_addr};
	 
	 wire [5:0] cursor_character = cursor_on ? 6'd0 : 6'd32;   // "@" or space

    assign font_char = (vram_r_addr != cursor) ? vram_dout : cursor_character;
    assign font_pixel = h_dot;     
                                   
    assign font_line = v_dot * 2 + 4;
	 
	 wire cross_talk_artifact = (h_active & v_active) && v_dot == 0 && h_dot == 0;
	 
	 wire [5:0] pixel_out = { font_out, font_out, font_out, font_out, font_out | cross_talk_artifact, font_out };

    // vga signals out to monitor
    assign vga_red = (h_active & v_active) ? pixel_out : 6'b0;
    assign vga_grn = (h_active & v_active) ? pixel_out : 6'b0;    
	 assign vga_blu = (h_active & v_active) ? pixel_out : 6'b0;

    assign vga_h_sync = (h_cnt < h_pulse) ? 0 : 1;
    assign vga_v_sync = (v_cnt < v_pulse) ? 0 : 1;

    //////////////////////////////////////////////////////////////////////////
    // CPU control and hardware cursor

    assign vram_clr_addr = vram_end_addr + {3'd0, vram_v_addr[1:0]};

    always @(posedge sys_clock or posedge reset)
    begin
        if (reset) begin
            h_cursor <= 6'd0;
            v_cursor <= 5'd0;            
            vram_start_addr <= 5'd0;
            vram_end_addr <= 5'd24;
				ready <= 0;
        end
        else
        if(pixel_clken) begin
            vram_w_en <= 0;
				
				// accepts a new character only at the start of each frame
				if(v_cnt == 0 && h_cnt == 0) 
				   ready <= 1;

            if(clr_screen) begin
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
            else begin
                // cursor overflow handling
                if (h_cursor == 6'd40) begin
                    h_cursor <= 6'd0;
                    v_cursor <= v_cursor + 'd1;
                end

                if (v_cursor == vram_end_addr) begin
                    vram_start_addr <= vram_start_addr + 'd1;
                    vram_end_addr <= vram_end_addr + 'd1;
                end

					 // address low == TX register
                if (address == 1'b0) begin
                    if (cpu_clken & w_en & ready) begin
                        // incoming character                        
					         ready <= 0;
					         dout[6:0] <= din[6:0];
								
								if(din[6:0]=='h0D) begin
									 // handle carriage return
									 h_cursor <= 0;
									 v_cursor <= v_cursor + 'd1;
								end 
								else if(din[6:0] < 32) begin
								    // 0-31 non printable characters, do nothing
								end								
								else begin
                            vram_w_addr <= cursor;
                            vram_din <= {~din[6], din[4:0]};
                            vram_w_en <= 1;
                            h_cursor <= h_cursor + 1;
                        end                        
                    end                    
                end
                else begin
                    vram_w_addr <= {vram_clr_addr, vram_h_addr};
                    vram_din <= 6'd32;
                    vram_w_en <= 1;
                end
            end
        end
    end

endmodule
