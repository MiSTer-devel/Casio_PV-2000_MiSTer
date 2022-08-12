//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v" 
localparam CONF_STR = {
	"Casio_PV-2000;;",
	"-;",
	"FC1,BIN,Load Cartridge;",
	"-;",

	"P2,Video Settings;",
	"P2O[2],Aspect ratio,Original,Full Screen;",
	"P2O[3],Show Border,No,Yes;",
	"P2O[5:4],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"R[6],Eject Cartridge and Reset;",
	"R[0],Reset;",
	"J,Attack 0,Attack 1,Select,Start;",
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [31:0] joy0, joy1;
wire         ioctl_download;
wire   [7:0] ioctl_index;
wire         ioctl_wr;
wire  [24:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire  [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),

	.joystick_0(joy0),
	.joystick_1(joy1),
	
	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_10m7;
wire clk_3m58;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_10m7),
	.outclk_2(clk_3m58)
);

reg ce_10m7 = 0;
reg ce_5m3 = 0;
always @(posedge clk_sys) begin
	reg [2:0] div;
	
	div <= div+1'd1;
	ce_10m7 <= !div[1:0];
	ce_5m3  <= !div[2:0];
end

//////////////////////////////////////////////////////////////////
wire reset = RESET | status[0] | buttons[1] | ioctl_download | download_reset;

// reset after download
reg [7:0] download_reset_cnt;
wire download_reset = download_reset_cnt != 0;

always @(posedge CLK_50M) begin
	if(ioctl_download || status[0] || buttons[1] || RESET || erasing) download_reset_cnt <= 8'd255;
	else if(download_reset_cnt != 0) download_reset_cnt <= download_reset_cnt - 8'd1;
end

///////////////////////// Erase Cart Ram /////////////////////////
reg erasing;
wire [15:0] erase_addr;
wire        erase_wr;

always @(posedge clk_sys) begin
	reg old_clear = 0;
	old_clear <= status[6];
	if (~old_clear & status[6]) begin
		erasing <= 1;
		erase_addr <= 16'h7000;
		erase_wr <= 1;
	end
	if(erasing == 1) begin
		if(~erase_wr) begin
			if(erase_addr >= 16'h7000 && erase_addr <= 16'hFFFF) begin
				erase_wr <= 1;
				erase_addr <= erase_addr + 8'd1;
			end
			else begin
				erase_addr <= 16'h7000;
				erasing <= 0;
				erase_wr <= 0;
			end
		end
		else erase_wr <= 0;
	end
end


////////////////////////   RAM   ///////////////////////////////
wire [15:0] ram_a;
wire        ram_we_n, ram_ce_n;
wire  [7:0] ram_di;
wire  [7:0] ram_do;

spram #(16) ram
(
	.clock(clk_sys),
	.address(erasing ? erase_addr : ioctl_download ? (ioctl_index == 0 ? ioctl_addr[15:0] : ioctl_addr[15:0] + 16'hC000) : ram_a),
	.wren(ioctl_wr | erase_wr | ~ram_we_n),
	.data(erasing ? 8'd0 : ioctl_download ? ioctl_dout : ram_do),
	.q(ram_di)
);
wire  [7:0] audio;

assign AUDIO_L = {1'd0,audio,7'd0};
assign AUDIO_R = {1'd0,audio,7'd0};
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

///////////////////////   CLOCKS   ///////////////////////////////
wire [13:0] vram_a;
wire        vram_we;
wire  [7:0] vram_di;
wire  [7:0] vram_do;

spram #(14) vram
(
	.clock(clk_sys),
	.address(erasing? erase_addr[13:0]:vram_a),
	.wren(erasing? erase_wr: vram_we),
	.data(erasing? 8'd0 : vram_do),
	.q(vram_di)
);

wire [7:0] R,G,B;
wire HBlank;
wire nHSync;
wire VBlank;
wire nVSync;

assign CLK_VIDEO = clk_sys;

wire ar = status[2];
wire vga_de_s;

video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de_s),
	.ARX((!ar) ? 12'd400 : ar ),
	.ARY((!ar) ? 12'd300 : 12'd0),
	.CROP_SIZE(10'd0),
	.CROP_OFF(0),
	.SCALE(status[5:4])
);

video_mixer #(.LINE_LENGTH(284), .GAMMA(1)) video_mixer
(

	.CLK_VIDEO(CLK_VIDEO),
	.ce_pix(ce_5m3),
	.CE_PIXEL(CE_PIXEL),

	.scandoubler(forced_scandoubler),
	.hq2x(0),
	.gamma_bus(gamma_bus),


	.R(R),
	.G(G),
	.B(B),

	// Positive pulses.
	.HSync(~nHSync),
	.VSync(~nVSync),
	.HBlank(HBlank),
	.VBlank(VBlank),
	
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de_s)

);


CasioPV2000 console
(
	.clk(clk_sys),
	.clk_10m7(clk_10m7),
	.clk_3m58(clk_3m58),
	.ce_10m7(ce_10m7),
	.reset(reset),
	
	.audio(audio),
	
	////////////// CPU RAM Interface //////////////
	.cpu_ram_a_o(ram_a),
	.cpu_ram_we_n_o(ram_we_n),
	.cpu_ram_d_i(ram_di),
	.cpu_ram_d_o(ram_do),

	.vram_a(vram_a),
	.vram_we(vram_we),
	.vram_do(vram_do),
	.vram_di(vram_di),

	.ps2_key(ps2_key),
	.joy0(joy0),
	.joy1(joy1),


	.HBlank(HBlank),
	.nHSync(nHSync),
	.VBlank(VBlank),
	.nVSync(nVSync),
	.R(R),
	.G(G),
	.B(B),
	.border_en(status[3])
);

endmodule

