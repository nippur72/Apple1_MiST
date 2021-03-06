// Apple-1 Audio cassette interface (ACI) 

// A good explanation of ACI can be found at:
// https://www.sbprojects.net/projects/apple1/aci.php

module ACI (
   input clk,              // clock signal
   input cpu_clken,        // CPU clock enable      

   input [15:0] addr,      // address bus   
   output reg [7:0] dout,  // 8-bit data bus (output)

   output reg tape_out,    // tape output
   input      tape_in      // tape input
);

   reg [7:0] rom_data[0:255];

   initial
      $readmemh("roms/aci.hex", rom_data, 0, 255);

	wire io_range = addr >= 16'hC000 && addr <= 16'hC0FF;
	
   wire [7:0] read_addr = io_range ? { addr[7:1], addr[0] & debounced_tape_in } : addr[7:0];
		
   always @(posedge clk) begin

      if(cpu_clken & io_range)
         tape_out <= ~tape_out;

      dout <= rom_data[read_addr];
   end
	
	// filters tape_in with anti bounce 
	wire debounced_tape_in = last_tape_in;
	reg last_tape_in;
	reg [31:0] bounce_cnt;
	localparam bounce_max = 3579;   // 57272719 / 3579 = ~16 KHz max
	
	always @(posedge clk) begin
		if(tape_in != last_tape_in) begin			
			if(bounce_cnt < bounce_max) begin
				bounce_cnt <= bounce_cnt + 1;
			end
			else begin
				bounce_cnt <= 0;				
				last_tape_in = tape_in;		
			end
		end
	end

endmodule
    