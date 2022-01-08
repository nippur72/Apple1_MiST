
module clock
(
   input sys_clock,        // master clock at cpu x 7 x 8
   input reset,            // reset
   
   output cpu_clken,     // 1MHz clock enable for the CPU 
	output pixel_clken,   // 7MHz clock enable for the display
		
	output cpu_clock
);

localparam CPU_DIVISOR     = 56;  // (sys_clock / CPU_DIVISOR)   = 1 MHz
localparam PIXEL_DIVISOR   =  8;  // (sys_clock / PIXEL_DIVISOR) = 7 MHz
localparam REFRESH_DIVISOR = 65;  // 

	reg [5:0] counter_cpu;
	reg [2:0] counter_pixel;
	reg [7:0] counter_refresh;
	
	always @(posedge sys_clock or posedge reset)
	begin
	   if(reset) begin
			counter_cpu     <= 0;
			counter_pixel   <= 0;
			counter_refresh <= 0;
		end
		else begin			
		   
			if (counter_cpu == (CPU_DIVISOR-1)) begin
				counter_cpu <= 0;
				counter_refresh <= (counter_refresh == REFRESH_DIVISOR-1) ? 0 : counter_refresh + 1;  				
			end 
			else 
			   counter_cpu <= counter_cpu + 1;

			counter_pixel <= (counter_pixel == PIXEL_DIVISOR-1) ? 0 : counter_pixel + 1;
						
		end
	end
	
	assign cpu_clken   = counter_cpu   == 0 /*&& counter_refresh > 3*/;
	assign pixel_clken = counter_pixel == 0;
	
	assign cpu_clock = counter_pixel < 4 ? 1 : 0; 
	
endmodule
