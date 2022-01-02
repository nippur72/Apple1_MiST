// Apple-1 for MiST
//
// Forked from Gehstock's implementation https://github.com/Gehstock/Mist_FPGA
//
//

// TODO clean reset, reset_n
// TODO take power reset
// TODO take out cpu clock enable 
// TODO make ram work with clock enable
// TODO load binary files into memory
// TODO make it work with SDRAM
// TODO ram refresh lost cycles
// TODO power on-off key ? (init ram)
// TODO ram powerup initial values
// TODO reset if pll not locked
// TODO reorganize file structure
// TODO support ACI interface for load and save
// TODO special expansion boards: TMS9918, SID, AY?
// TODO check diff with updated data_io.v and other modules
// TODO keyboard: isolate ps2 keyboard from apple1
// TODO keyboard: check ps2 clock
// TODO keyboard: reset and cls key
// TODO keyboard: make a true ascii keyboard
// TODO display: powerup values
// TODO display: simplify rom font
// TODO display: reduce to 512 bytes font
// TODO display: use 7 MHz clock
// TODO display: check parameters vs real apple1


module apple1_mist(
   input         CLOCK_27,
	
   // SPI interface to arm io controller 	
	input         SPI_SCK,
	output        SPI_DO,
	input         SPI_DI,
   input         SPI_SS2,
	input         SPI_SS3,
   input 		  SPI_SS4,
	input         CONF_DATA0,
	
	// SDRAM interface
	inout [15:0]  	SDRAM_DQ, 		// SDRAM Data bus 16 Bits
	output [12:0] 	SDRAM_A, 		// SDRAM Address bus 13 Bits
	output        	SDRAM_DQML, 	// SDRAM Low-byte Data Mask
	output        	SDRAM_DQMH, 	// SDRAM High-byte Data Mask
	output        	SDRAM_nWE, 		// SDRAM Write Enable
	output       	SDRAM_nCAS, 	// SDRAM Column Address Strobe
	output        	SDRAM_nRAS, 	// SDRAM Row Address Strobe
	output        	SDRAM_nCS, 		// SDRAM Chip Select
	output [1:0]  	SDRAM_BA, 		// SDRAM Bank Address
	output 			SDRAM_CLK, 		// SDRAM Clock
	output        	SDRAM_CKE, 		// SDRAM Clock Enable
	
	// VGA interface
	output  [5:0] VGA_R,
	output  [5:0] VGA_G,
	output  [5:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

	// other
	output        LED,	
	input         UART_RX,
   output        AUDIO_L,
   output        AUDIO_R		
);

`include "rtl\build_id.v" 

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @user_io ***************************************/
/******************************************************************************************/
/******************************************************************************************/

localparam CONF_STR = {
	"APPLE 1;;",              // 0 download index for "apple1.rom"  
   "F,PRG,Load program;",    // 1 download index for ".prg" files
	"F,ROM,Load firmware;",   // 2 download index for ".rom" files
	"O34,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"T6,Reset;",
	"V,v1.01.",`BUILD_DATE
};

localparam conf_str_len = $size(CONF_STR)>>3;

wire st_reset_switch = buttons[1];
wire st_menu_reset   = status[6];

wire clk7;     // the 14.31818 MHz clock
wire clk_osd;   // x2 clock for the OSD menu
wire r, g, b;
wire hs, vs;

wire [31:0] status;
wire  [1:0] buttons;
wire  [1:0] switches;

wire scandoubler_disable;
wire ypbpr;
wire no_csync;

wire ps2_kbd_clk;
wire ps2_kbd_data;

wire reset_button = status[0] | st_menu_reset | st_reset_switch | !pll_locked;

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @pll *******************************************/
/******************************************************************************************/
/******************************************************************************************/

wire pll_locked;

wire sdram_clock;        // cpu x 8 for sdram.v interface
wire sdram_clock_ph;     // cpu x 8 phase shifted -2.5 ns   	

pll pll 
(
	.inclk0(CLOCK_27),
	.locked(pll_locked),
	.c0(clk_osd),           // x2 clock for OSD menu
	.c1(clk7),	            // 7.15909 MHz (14.318180/2)		
   .c2( sdram_clock    ),  // cpu x 8   
	.c3( sdram_clock_ph )   // cpu x 8 phase shifted -2.5 ns   	

);

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @downloader ************************************/
/******************************************************************************************/
/******************************************************************************************/

wire        is_downloading;      // indicates that downloader is working
wire [24:0] download_addr;       // download address
wire [7:0]  download_data;       // download data
wire        download_wr;         // download write enable
wire        ROM_loaded;          // 1 when boot rom has been downloaded

// ROM download helper
downloader 
#(
   .BOOT_INDEX (0),    // menu index 0 is for automatic download of "apple1.rom" at FPGA boot 
	.PRG_INDEX  (1),    // menu index for load .prg
	.ROM_INDEX  (2),    // menu index for load .prg	
	.ROM_START_ADDR(0)  // start of ROM (bank 0 of SDRAM)
)
downloader 
(	
	// new SPI interface
   .SPI_DO ( SPI_DO  ),
	.SPI_DI ( SPI_DI  ),
   .SPI_SCK( SPI_SCK ),
   .SPI_SS2( SPI_SS2 ),
   .SPI_SS3( SPI_SS3 ),
   .SPI_SS4( SPI_SS4 ),
	
	// signal indicating an active rom download
	.downloading ( is_downloading  ),
   .ROM_done    ( ROM_loaded      ),	
	         
   // external ram interface
   .clk     ( clk7         ),
	.clk_ena ( cpu_clken     ),
   .wr      ( download_wr   ),
   .addr    ( download_addr ),
   .data    ( download_data )	
);

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @apple1 ****************************************/
/******************************************************************************************/
/******************************************************************************************/

// RAM
ram ram(
  .clk    (clk7     ),
  .ena    (cpu_clken ),
  .address(sdram_addr[15:0]),
  .w_en   (sdram_wr  ),
  .din    (sdram_din ),
  .dout   (sdram_dout)
);

// SDRAM control signals
//assign SDRAM_CKE = 1'b1;

wire [24:0] sdram_addr;
wire  [7:0] sdram_din;
wire        sdram_wr;
wire        sdram_rd;
wire [7:0]  sdram_dout;

assign dummy = is_downloading && download_wr;

always @(*) begin
	if(is_downloading && download_wr) begin
		sdram_addr   <= download_addr;
		sdram_din    <= download_data;
		sdram_wr     <= download_wr;
		sdram_rd     <= 1'b1;	      
	end
   /*	
	else if(eraser_busy) begin		
		sdram_addr   <= eraser_addr;
		sdram_din    <= eraser_data;
		sdram_wr     <= eraser_wr;
		sdram_rd     <= 1'b1;		
	end	
	*/
	else begin
		sdram_addr   <= { 9'b0, cpu_addr[15:0] };
		sdram_din    <= cpu_dout;		
		sdram_wr     <= cpu_wr;
		sdram_rd     <= cpu_rd;		
	end	
end

assign LED = ~dummy;

// WozMon ROM
wire [7:0] rom_dout;
rom_wozmon rom_wozmon(
  .clk(clk7),
  .address(cpu_addr[7:0]),
  .dout(rom_dout)
);

// Basic ROM
wire [7:0] basic_dout;
rom_basic rom_basic(
  .clk(clk7),
  .address(cpu_addr[11:0]),
  .dout(basic_dout)
);

// ram interface
wire [15:0] cpu_addr;
wire [7:0]  cpu_dout;
wire        cpu_rd;
wire        cpu_wr;

wire ram_cs   = cpu_addr < 16'hc000;                          //  (cpu_addr[15:13] ==  3'b000);       // 0x0000 -> 0x1FFF
wire basic_cs = cpu_addr >= 16'hE000 && cpu_addr <= 16'hEFFF; //  (cpu_addr[15:12] ==  4'b1110);      // 0xE000 -> 0xEFFF
wire rom_cs   = cpu_addr >= 16'hFF00 && cpu_addr <= 16'hFFFF; //  (cpu_addr[15:8]  ==  8'b11111111);  // 0xFF00 -> 0xFFFF

wire [7:0] bus_dout = basic_cs ? basic_dout :
                      rom_cs   ? rom_dout   :
					       ram_cs   ? sdram_dout :
					       8'b0;

apple1 apple1 
(
	.clk7(clk7),
	.reset(reset_button),
	
	.cpu_clken(cpu_clken),     // apple1 outputs the CPU clock enable
	
	// RAM interface
	.ram_addr (cpu_addr),
	.ram_din  (cpu_dout),
	.ram_dout (bus_dout),
	.ram_rd   (cpu_rd),
	.ram_wr   (cpu_wr),
		
	.ps2_clk(ps2_kbd_clk),
	.ps2_din(ps2_kbd_data),

	.vga_h_sync(hs),
   .vga_v_sync(vs),
	.vga_red(r),
	.vga_grn(g),
	.vga_blu(b),

	.vga_cls()             // clear screen button (not connected yet) 
);

mist_video 
#(
	.COLOR_DEPTH(1),    // 1 bit color depth
	.OSD_AUTO_CE(1)     // OSD autodetects clock enable
)
mist_video
(
	.clk_sys(clk_osd),    // OSD needs 2x the VDP clock for the scandoubler
	
	// OSD SPI interface
	.SPI_DI(SPI_DI),
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS3),
		
	.scanlines(2'b00),                           // scanline emulation disabled for now
	.ce_divider(1),                              // non-scandoubled pixel clock divider 0 - clk_sys/4, 1 - clk_sys/2

	.scandoubler_disable(scandoubler_disable),   // disable scandoubler option from mist.ini	
	.no_csync(no_csync),                         // csync option from mist.ini
	.ypbpr(ypbpr),                               // YPbPr option from mist.ini

	.rotate(2'b00),                              // no ODS rotation
	.blend(0),                                   // composite-like blending
	
	// video input	signals to mist_video
	.R(r),
	.G(g),
	.B(b),
	.HSync(hs),
	.VSync(vs),
	
	// video output signals that go into MiST hardware
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),	
);

user_io 
#(
	.STRLEN(conf_str_len)
	//.PS2DIV(14)              // ps2 clock divider: CLOCK / 14 must be approx = 15 Khz
) 
user_io (
   .conf_str       (CONF_STR       ),
	
	.clk_sys        (clk7          ),
	
	.SPI_CLK        (SPI_SCK        ),
	.SPI_SS_IO      (CONF_DATA0     ),	
	.SPI_MISO       (SPI_DO         ),
	.SPI_MOSI       (SPI_DI         ),
	
	.status         (status         ),
	.buttons        (buttons        ),
	.switches   	 (switches       ),

	.scandoubler_disable ( scandoubler_disable ),   // get this option from mist.ini
	.ypbpr               ( ypbpr               ),   // get this option from mist.ini
	.no_csync            ( no_csync            ),   // get this option from mist.ini
		
	.ps2_kbd_clk    (ps2_kbd_clk    ),              // ps2 keyboard from mist firmware 
	.ps2_kbd_data   (ps2_kbd_data   )               // ps2 keyboard from mist firmware
);

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @sdram *****************************************/
/******************************************************************************************/
/******************************************************************************************/
			
// SDRAM control signals
assign SDRAM_CKE = 1'b1;
assign SDRAM_CLK = sdram_clock_ph;

/*
wire [24:0] sdram_addr;
wire  [7:0] sdram_din;
wire        sdram_wr;
wire        sdram_rd;
wire [7:0]  sdram_dout;

always @(*) begin
	if(is_downloading && download_wr) begin
		sdram_addr   <= download_addr;
		sdram_din    <= download_data;
		sdram_wr     <= download_wr;
		sdram_rd     <= 1'b1;			
	end	
	else if(eraser_busy) begin		
		sdram_addr   <= eraser_addr;
		sdram_din    <= eraser_data;
		sdram_wr     <= eraser_wr;
		sdram_rd     <= 1'b1;		
	end	
	else begin
		sdram_addr   <= { 9'd0, cpu_addr[15:0] };
		sdram_din    <= cpu_dout;		
		sdram_wr     <= cpu_wr;
		sdram_rd     <= cpu_rd;
	end	
end

sdram sdram (
	// interface to the MT48LC16M16 chip
   .sd_data        ( SDRAM_DQ                  ),
   .sd_addr        ( SDRAM_A                   ),
   .sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML}  ),
   .sd_cs          ( SDRAM_nCS                 ),
   .sd_ba          ( SDRAM_BA                  ),
   .sd_we          ( SDRAM_nWE                 ),
   .sd_ras         ( SDRAM_nRAS                ),
   .sd_cas         ( SDRAM_nCAS                ),

   // system interface
   .clk            ( sys_clock                 ),
   .clkref         ( cpu_clock                 ),
   .init           ( !pll_locked               ),

   // cpu interface
   .din            ( sdram_din                 ),
   .addr           ( sdram_addr                ),
   .we             ( sdram_wr                  ),
   .oe         	 ( sdram_rd                  ),
   .dout           ( sdram_dout                )
);
*/

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @clock_ena *************************************/
/******************************************************************************************/
/******************************************************************************************/

wire cpu_clken;  // provides the cpu clock enable signal derived from main clock

//wire cpu_clken;
clock clock(
  .clk7     ( clk7          ),   // input: main clock
  .reset    ( reset_button  ),   // input: reset signal
  .cpu_clken( cpu_clken     )    // output: cpu clock enable
);

endmodule 
