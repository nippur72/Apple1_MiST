// Apple-1 for MiST
//
// Forked from Gehstock's implementation https://github.com/Gehstock/Mist_FPGA
//
//

// TODO make it work with SDRAM
// TODO load binary files into memory
// TODO use 7 MHz clock in display
// TODO isolate ps2 keyboard from apple1
// TODO check ps2 clock
// TODO ram refresh lost cycles
// TODO check display parameters vs real apple1
// TODO reset and cls key from keyboard
// TODO power on-off key ? (init ram)
// TODO reset if pll not locked
// TODO rename "vga" into "display"
// TODO reorganize file structure
// TODO integrate with mist-modules
// TODO support ACI interface for load and save
// TODO special expansion boards: TMS9918, SID

module apple1_mist(
   input         CLOCK_27,
	
   // SPI interface to arm io controller 	
	input         SPI_SCK,
	output        SPI_DO,
	input         SPI_DI,
 //input         SPI_SS2,
	input         SPI_SS3,
 //input 		  SPI_SS4,
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
	"APPLE 1;;",
	"O34,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"T6,Reset;",
	"V,v1.01.",`BUILD_DATE
};

localparam conf_str_len = $size(CONF_STR)>>3;

wire st_reset_switch = buttons[1];
wire st_menu_reset   = status[6];

wire clk14;     // the 14.31818 MHz clock
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

assign LED = 1;

wire reset_button = status[0] | st_menu_reset | st_reset_switch;


pll pll 
(
	.inclk0(CLOCK_27),
	.c0(clk_osd),
	.c1(clk14),
	.locked(),
	.areset()
);

apple1 apple1 
(
	.clk14(clk14),
	.rst_n(~reset_button),
	
	.uart_rx(),             // uart not connected
	.uart_tx(),             // uart not connected
	.uart_cts(),            // uart not connected
	
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
	
	.clk_sys        (clk14          ),
	
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

endmodule 