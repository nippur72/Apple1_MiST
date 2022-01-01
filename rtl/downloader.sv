// This module allows easy download of three types of files into system ram:
//
// 1) ROM file that is injected by the firmware at startup/boot (loaded at address 0)
// 2) PRG file, containing load address in the first two bytes as in C64's .prg
// 3) ROM as 1) but with different .rom file name selected by the user from the menu


module downloader (	

	// SPI interface with the ARM controller
   input SPI_DO,
	input SPI_DI,
   input SPI_SCK,
   input SPI_SS2,
   input SPI_SS3,
   input SPI_SS4,
	
	input 			   clk,
	input             clk_ena,
	
	output reg        wr,
	output reg [24:0] addr,
	output reg [7:0]  data,

	output reg        downloading,   // 1 = active download is in process
	output reg        ROM_done       // 1 = boot ROM has already been loaded
);

parameter BOOT_INDEX = 0;     // menu index for the boot rom (0 by default in MiST firmware)
parameter PRG_INDEX;          // menu index for .prg files
parameter ROM_INDEX;          // menu index for .rom files (not loaded at boot)
parameter ROM_START_ADDR = 0; // start of ROM 

reg [15:0] prg_start_addr;  // first two bytes of the .prg file containing ram loading address

// simplify checks
wire is_rom_download = dio_index == BOOT_INDEX || dio_index == ROM_INDEX;
wire is_prg_download = dio_index == PRG_INDEX;

reg dio_dowloading_old = 0;    // used to detect changes in dio_dowloading

always @(posedge clk) begin	
			
	if(dio_dowloading == 1) begin
		downloading <= 1;
		
		if(is_rom_download) begin 
			addr <= dio_addr + ROM_START_ADDR;				
   		wr   <= dio_wr;
	   	data <= dio_data;
		end
		else if(is_prg_download) begin
		   if(dio_addr == 0) begin 
				prg_start_addr [7:0] = dio_data;  // extracts address low byte
				wr <= 0;                          // do not write yet
			end   
			else if(dio_addr == 1) begin         
			   prg_start_addr[15:8] = dio_data;  // extracts address high byte
				wr <= 0;                          // do not write yet
			end                   
			else begin
				addr <= dio_addr + { 9'b0, prg_start_addr } - 2; // write prg at load address and skip first two bytes	 
				wr   <= dio_wr;
				data <= dio_data;
			end
		end								
	end
	
	// end of transfer
	if(dio_dowloading_old == 1 && dio_dowloading == 0) begin
		downloading <= 0;
		if(is_rom_download) ROM_done <= 1;
	end
	
   // detect change in dio_dowloading
	dio_dowloading_old <= dio_dowloading;	

end

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @data_io ***************************************/
/******************************************************************************************/
/******************************************************************************************/

wire        dio_dowloading;
wire [7:0]  dio_index;      
wire        dio_wr;
wire [24:0] dio_addr;
wire [7:0]  dio_data;

data_io data_io (
	.clk_sys ( clk      ),
	.clkref_n( ~clk_ena ),  // keep this to zero
	
	// io controller spi interface
	.SPI_SCK( SPI_SCK ),
	.SPI_SS2( SPI_SS2 ),
	.SPI_SS4( SPI_SS4 ),
	.SPI_DI ( SPI_DI  ),
	.SPI_DO ( SPI_DO  ), 	  
	
	.ioctl_download ( dio_dowloading ),  // signal indicating an active rom download
	.ioctl_index    ( dio_index      ),  // 0=rom download, 1=prg dowload
   .ioctl_addr     ( dio_addr       ),
   .ioctl_dout     ( dio_data       ),
	.ioctl_wr       ( dio_wr         )
);

endmodule

