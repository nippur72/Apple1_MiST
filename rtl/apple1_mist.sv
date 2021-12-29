// Apple-1 for MiST
//
// Forked from Gehstock's implementation https://github.com/Gehstock/Mist_FPGA
//
//

// TODO integrate with mist-modules
// TODO load binary files into memory
// TODO support ACI interface for load and save
// TODO additional RAM with SDRAM
// TODO reset key from keyboard
// TODO cls key from keyboard
// TODO power on-off
// TODO special expansion boards: TMS9918, SID
// TODO white/green/amber switch?
// TODO reset if pll not locked
// TODO rename "vga" into "display"
// TODO reorganize file structure
// TODO check ps2 clock


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
	"V,v1.00.",`BUILD_DATE
};

localparam conf_str_len = $size(CONF_STR)>>3;

wire st_reset_switch = buttons[1];
wire st_menu_reset   = status[6];

wire clk14;     // the 14.31818 MHz clock
wire clk_osd;   // x4 clock for the OSD menu
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
	.ps2_select(1'b1),

	.vga_h_sync(hs),
   .vga_v_sync(vs),
	.vga_red(r),
	.vga_grn(g),
	.vga_blu(b),

	.vga_cls(),         // clear screen button (not connected yet) 
   .pc_monitor()       // debug program counter (not used)
);

mist_video 
#(
	.COLOR_DEPTH(1),
	.OSD_AUTO_CE(1)
)
mist_video
(
	.clk_sys(clk_osd),    // 2x the VDP clock for the scandoubler
	
	// OSD SPI interface
	.SPI_DI(SPI_DI),
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS3),
		
	.scanlines(2'b00),           // scanlines (00-none 01-25% 10-50% 11-75%)	
	.ce_divider(1),              // non-scandoubled pixel clock divider 0 - clk_sys/4, 1 - clk_sys/2
	.scandoubler_disable(scandoubler_disable),
	
	.no_csync(no_csync),                         // 1 = disable csync without scandoubler	
	.ypbpr(ypbpr),                               // 1 = YPbPr output on composite sync

	.rotate(2'b00),              // Rotate OSD [0] - rotate [1] - left or right	
	.blend(0),                   // composite-like blending
	
	// video input	
	.R(r),
	.G(g),
	.B(b),
	.HSync(hs),
	.VSync(vs),
	
	// MiST video output signals
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

	.scandoubler_disable ( scandoubler_disable ),
	.ypbpr               ( ypbpr               ),
	.no_csync            ( no_csync            ),
	
	// ps2 interface
	.ps2_kbd_clk    (ps2_kbd_clk    ),
	.ps2_kbd_data   (ps2_kbd_data   )
);

endmodule 