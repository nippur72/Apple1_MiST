module tms9918
(
	input RESET,
	input clk,
	input ena,
	
	// control signals
   input  csr_n,
   input  csw_n,
	input  mode,
	output int_n,
	
	// cpu I/O 
	input  [0:7] cd_i,
	output [0:7] cd_o,
	
	//	vram
   output        vram_we,
   output [0:13] vram_a,
   output [0:7]  vram_d_o,
   input  [0:7]  vram_d_i,
	
	// video 
	output       HS,
	output       VS,
	output [5:0] R,
	output [5:0] G,
	output [5:0] B
);

vdp18_core
  
#(
	.is_pal_g(0)     // NTSC	
) 

vdp
(
	.clk_i         ( clk         ),
	.clk_en_10m7_i ( ena         ),
	.reset_n_i     ( ~RESET      ),
	
   .csr_n_i       ( csr_n       ),
   .csw_n_i       ( csw_n       ),
   .mode_i        ( mode        ),		
   .int_n_o       ( int_n       ),
	
   .cd_i          ( cd_i        ),
   .cd_o          ( cd_o        ),
		
   .vram_we_o     ( vram_we     ),
   .vram_a_o      ( vram_a      ),
   .vram_d_o      ( vram_d_o    ),
   .vram_d_i      ( vram_d_i    ),
	
   .rgb_r_o       ( vdp_r_  ),
   .rgb_g_o       ( vdp_g_  ),
   .rgb_b_o       ( vdp_b_  ),	
   .hsync_n_o     ( vdp_hs  ),
   .vsync_n_o     ( vdp_vs  )

);

// video wires
wire vdp_vs;
wire vdp_hs;
wire [0:7] vdp_r_;		
wire [0:7] vdp_g_;
wire [0:7] vdp_b_;
wire [5:0] vdp_r = { vdp_r_[0],vdp_r_[1],vdp_r_[2],vdp_r_[3],vdp_r_[4],vdp_r_[5] } ;
wire [5:0] vdp_g = { vdp_g_[0],vdp_g_[1],vdp_g_[2],vdp_g_[3],vdp_g_[4],vdp_g_[5] } ;
wire [5:0] vdp_b = { vdp_b_[0],vdp_b_[1],vdp_b_[2],vdp_b_[3],vdp_b_[4],vdp_b_[5] } ;


/******************************************************************************************/
/******************************************************************************************/
/***************************************** @test ******************************************/
/******************************************************************************************/
/******************************************************************************************/

reg [15:0] hcnt;
reg [15:0] vcnt;
reg flip = 0;

localparam EXTRA_PIXELS = 0; // 5

always @(posedge clk) begin
	if(ena) begin	
		if(RESET) begin
			hcnt <= -36;
			vcnt <= 0;
		end
		else begin
			flip = ~flip;
			if(flip) begin
				hcnt <= hcnt + 1;
				if(hcnt == 341+EXTRA_PIXELS) begin
					hcnt <= 0;
					vcnt <= vcnt + 1;
					if(vcnt == 260) vcnt <= 0;
				end
			end
		end	
	end
end

assign VS = 1 ? (vcnt < 4  ? 0 : 1) : vdp_hs;
assign HS = 1 ? (hcnt < 20 ? 0 : 1) : vdp_vs;

wire blank = (vcnt < 8) || (hcnt < 60 || hcnt > 340);

assign R = 1 ? (blank ? 0 : vdp_r) : vdp_r;
assign G = 1 ? (blank ? 0 : vdp_g) : vdp_r;
assign B = 1 ? (blank ? 0 : vdp_b) : vdp_r;

endmodule
