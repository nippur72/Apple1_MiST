// Apple-1 for MiST
//
// Forked from Gehstock's implementation https://github.com/Gehstock/Mist_FPGA
//
//

// TODO use a CPU that allows illegal instructions
// TODO make it work with SDRAM
// TODO ram refresh lost CPU cycles
// TODO power on-off key ? (init ram)
// TODO ram powerup initial values
// TODO reorganize file structure
// TODO ACI: create ROM 
// TODO ACI: implementation
// TODO more accurate chip selection circuit
// TODO check diff with updated data_io.v and other modules
// TODO keyboard: use a PIA
// TODO keyboard: isolate ps2 keyboard from apple1
// TODO keyboard: check ps2 clock
// TODO keyboard: reset key
// TODO keyboard: make a true ascii keyboard
// TODO keyboard: check backspace key
// TODO osd menu yellow, why it doesn't work?
// TODO display: remove char_seen
// TODO display: check NTSC AD724 hsync problem
// TODO display: powerup values
// TODO display: simplify rom font
// TODO display: reduce to 512 bytes font
// TODO display: check parameters vs real apple1
// TODO display: check cursor blinking vs 555 timings
// TODO display: emulate PIA registers
// TODO tms9918: fix video sync on composite and mist_video
// TODO tms9918: make it selectable / use include in code
// TODO tms9918: connect /INT 
// TODO sid: implement 6581

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
	"O2,TMS9918 output,Off,On;",
	"T6,Reset;",
	"V,v1.01.",`BUILD_DATE
};

localparam conf_str_len = $size(CONF_STR)>>3;

wire st_reset_switch = buttons[1];
wire st_menu_reset   = status[6];

wire r, g, b;
wire hs, vs;

wire [31:0] status;
wire  [1:0] buttons;
wire  [1:0] switches;

wire st_tms9918_output = status[2];

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

wire sys_clock;          // cpu x 7 x 8 system clock (sdram.v)
wire osd_clock;          // cpu x 7 x 2 for the OSD menu
wire vdp_clock;          // tms9918 x 2 for osd menu 

pll pll 
(
	.inclk0(CLOCK_27),
	.locked(pll_locked),
	
	.c0( osd_clock      ),  // cpu x 7 x 2 video clock for OSD menu
   .c2( sys_clock      ),  // cpu x 7 x 8 system clock (sdram.v)
	.c3( SDRAM_CLK      ),  // cpu x 7 x 8 phase shifted -2.5 ns  
   .c4( vdp_clock      )   // tms9918 x 2 for osd menu (10.738635 x 2 = 21.47727)
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
   .clk     ( sys_clock     ),
	.clk_ena ( cpu_clken     ),
   .wr      ( download_wr   ),
   .addr    ( download_addr ),
   .data    ( download_data )	
);

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @ram *******************************************/
/******************************************************************************************/
/******************************************************************************************/

wire [7:0] ram_dout;

// low system RAM
ram #(.SIZE(16384)) ram(
  .clk    (sys_clock ),
  .address(sdram_addr[15:0]),
  .w_en   (sdram_wr & ram_cs),
  .din    (sdram_din ),
  .dout   (ram_dout  )  
);

// WozMon ROM
wire [7:0] rom_dout;
rom_wozmon rom_wozmon(
  .clk(sys_clock),
  .address(cpu_addr[7:0]),
  .dout(rom_dout)
);


// Basic RAM
wire [7:0] basic_dout;
ram #(.SIZE(4096)) rom_basic(
  .clk(sys_clock),
  .address({4'b000, sdram_addr[11:0]}),
  .w_en   (sdram_wr & basic_cs),
  .din    (sdram_din ),
  .dout   (basic_dout)
);

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @ACI *******************************************/
/******************************************************************************************/
/******************************************************************************************/

wire [7:0] aci_dout;
wire CASOUT;
ACI ACI(
  .clk(sys_clock),
  .cpu_clken(cpu_clken),
  .addr(sdram_addr[15:0]),
  .dout(aci_dout),
  .tape_in(CASIN),
  .tape_out(CASOUT),
);

// latches cassette audio input
reg CASIN;
always @(posedge sys_clock) begin
	CASIN <= ~UART_RX;    // on the Mistica UART_RX is the audio input
end

wire audio;
dac #(.C_bits(16)) dac_AUDIO
(
	.clk_i(sys_clock),
   .res_n_i(pll_locked),	
	.dac_i({ CASOUT, 15'b0000000 }),   // TODO not sure about polarity
	.dac_o(audio)
);

always @(posedge sys_clock) begin
	AUDIO_L <= audio;
	AUDIO_R <= audio;
end

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @apple1 ****************************************/
/******************************************************************************************/
/******************************************************************************************/

// SDRAM control signals

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
	else begin
		sdram_addr   <= { 9'b0, cpu_addr[15:0] };
		sdram_din    <= cpu_dout;		
		sdram_wr     <= cpu_wr;
		sdram_rd     <= 1'b1;		
	end	
end

wire dummy = is_downloading && download_wr;
assign LED = ~dummy;


// ram interface
wire [15:0] cpu_addr;
wire [7:0]  cpu_dout;
wire        cpu_rd;
wire        cpu_wr;

wire ram_cs   = sdram_addr <  'h4000;                         // 0x0000 -> 0x3FFF
wire sdram_cs = sdram_addr >= 'h4000 && sdram_addr <= 'hBFFF; // 0x4000 -> 0xBFFF
wire aci_cs   = sdram_addr >= 'hC000 && sdram_addr <= 'hC1FF; // 0xC000 -> 0xC1FF
wire tms_cs   = sdram_addr >= 'hCC00 && sdram_addr <= 'hCC01; // 0xCC00 -> 0xCC01
wire basic_cs = sdram_addr >= 'hE000 && sdram_addr <= 'hEFFF; // 0xE000 -> 0xEFFF
wire rom_cs   = sdram_addr >= 'hFF00;                         // 0xFF00 -> 0xFFFF

wire [7:0] bus_dout = rom_cs   ? rom_dout   :
                      basic_cs ? basic_dout :
							 tms_cs   ? vdp_dout   :
							 aci_cs   ? aci_dout   :
                      sdram_cs ? sdram_dout :
					       ram_cs   ? ram_dout   :
					       8'b0;

apple1 apple1 
(  
	.reset(reset_button), 
	
	.sys_clock   ( sys_clock   ),  // system clock
	.cpu_clken   ( cpu_clken   ),  // CPU clock enable	
	.pixel_clken ( pixel_clken ),  // pixel clock enable
	
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

	.vga_cls()               // clear screen button (not connected yet) 
);


/******************************************************************************************/
/******************************************************************************************/
/***************************************** @mist_video ************************************/
/******************************************************************************************/
/******************************************************************************************/

mist_video 
#(
	.COLOR_DEPTH(1),    // 1 bit color depth
	.OSD_AUTO_CE(1),    // OSD autodetects clock enable
	.OSD_COLOR(3'b110), // yellow menu color
	.SYNC_AND(1),
	.SD_HCNT_WIDTH(11)		
)
mist_video
(
	.clk_sys(osd_clock),    // OSD needs 2x the VDP clock for the scandoubler
	
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
	.VGA_R(apple1_R),
	.VGA_G(apple1_G),
	.VGA_B(apple1_B),
	.VGA_VS(apple1_VS),
	.VGA_HS(apple1_HS)	
);

wire  [5:0] apple1_R;
wire  [5:0] apple1_G;
wire  [5:0] apple1_B;
wire        apple1_HS;
wire        apple1_VS;

// mix video
assign VGA_R   = st_tms9918_output ? tms_R  : apple1_R ;
assign VGA_G   = st_tms9918_output ? tms_G  : apple1_G ;
assign VGA_B   = st_tms9918_output ? tms_B  : apple1_B ;
assign VGA_HS  = st_tms9918_output ? tms_HS & tms_VS : apple1_HS;
assign VGA_VS  = st_tms9918_output ? tms_VS : apple1_VS;

wire  [5:0] tms_out_R;
wire  [5:0] tms_out_G;
wire  [5:0] tms_out_B;
wire        tms_out_HS;
wire        tms_out_VS;

mist_video 
#(
	.COLOR_DEPTH(6),    // 1 bit color depth
	.OSD_AUTO_CE(1),    // OSD autodetects clock enable
	.OSD_COLOR(3'b110), // yellow menu color
	.SYNC_AND(1),
	.SD_HCNT_WIDTH(11)	
)
tms_mist_video
(
	//.clk_sys(vdp_clock),    // OSD needs 2x the VDP clock for the scandoubler
	.clk_sys(osd_clock),    
	
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
	.R    (tms_R ),
	.G    (tms_G ),
	.B    (tms_B ),
	.HSync(tms_HS),
	.VSync(tms_vs),
	
	// video output signals that go into MiST hardware
	.VGA_R(tms_out_R),
	.VGA_G(tms_out_G),
	.VGA_B(tms_out_B),
	.VGA_VS(tms_out_VS),
	.VGA_HS(tms_out_HS)	
);

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @user_io ***************************************/
/******************************************************************************************/
/******************************************************************************************/

user_io 
#(
	.STRLEN(conf_str_len)
	//.PS2DIV(14)              // ps2 clock divider: CLOCK / 14 must be approx = 15 Khz
) 
user_io (
   .conf_str       (CONF_STR       ),
	
	.clk_sys        (sys_clock      ),
	
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
*/

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

/******************************************************************************************/
/******************************************************************************************/
/***************************************** @clock *****************************************/
/******************************************************************************************/
/******************************************************************************************/

wire cpu_clken;    // provides the cpu clock enable signal derived from main clock
wire pixel_clken;  // provides the cpu clock enable signal derived from main clock
wire cpu_clock;

clock clock(
  .sys_clock  ( sys_clock     ),   // input: main clock
  .reset      ( reset_button  ),   // input: reset signal

  .cpu_clock  ( cpu_clock     ),  
  .cpu_clken  ( cpu_clken     ),   // output: cpu clock enable
  .pixel_clken( pixel_clken   )    // output: pixel clock enable
);


/******************************************************************************************/
/******************************************************************************************/
/***************************************** @vdp *******************************************/
/******************************************************************************************/
/******************************************************************************************/

wire        vram_we;
wire [0:13] vram_a;        
wire [0:7]  vram_din;      
wire [0:7]  vram_dout;

vram vram
(
  .clock  ( vdp_clock  ),  
  .address( vram_a     ),  
  .data   ( vram_din   ),                       
  .wren   ( vram_we    ),                       
  .q      ( vram_dout  )
);

wire [7:0] vdp_dout;
wire VDP_INT_n;         // TODO not connected yet

// divide by two the vdp_clock (which is doubled for the scandoubler)
reg vdp_ena;
always @(posedge vdp_clock) begin
	vdp_ena <= ~vdp_ena;
end

wire csr = tms_cs & sdram_rd;
wire csw = tms_cs & sdram_wr;

wire         tms_HS;
wire         tms_VS;
wire   [5:0] tms_R;
wire   [5:0] tms_G;
wire   [5:0] tms_B;

tms9918_async 
#(
	.HORIZONTAL_SHIFT(-36)    // -36 good empiric value to center the image on the screen
) 
tms9918
(
	// clock
	.RESET(reset_button),
	
	.clk(vdp_clock),
	.ena(vdp_ena),
	
	/*
	.clk(sys_clock),
	.ena(pixel_clken),
	*/
	
	// control signals
   .csr_n  ( ~csr          ),
   .csw_n  ( ~csw          ),
	.mode   ( sdram_addr[0] ),	    
   .int_n  ( VDP_INT_n     ),

	// cpu I/O 	
   .cd_i          ( sdram_din   ),
   .cd_o          ( vdp_dout    ),
		
	//	vram	
   .vram_we       ( vram_we     ),
   .vram_a        ( vram_a      ),
   .vram_d_o      ( vram_din    ),
   .vram_d_i      ( vram_dout   ),		
		
	// video 
	.HS(tms_HS),
	.VS(tms_VS),
	.R (tms_R),
	.G (tms_G),
	.B (tms_B)
);

endmodule 

