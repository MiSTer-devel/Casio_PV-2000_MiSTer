
module CasioPV2000
(
	input         clk,
	input         clk_10m7,
	input         clk_3m58,
	input         ce_10m7,
	input         reset,
	
	///////////// CPU RAM Interface /////////////
	output [15:0] cpu_ram_a_o,
	output reg    cpu_ram_we_n_o,
	input   [7:0] cpu_ram_d_i,
	output  [7:0] cpu_ram_d_o,

	//////////// Joystick Interface /////////////
	input  [10:0] ps2_key,
	input [31:0]  joy0,
	input [31:0]  joy1,

	////////////// AUDIO Interface //////////////
	output [7:0] audio,

	////////////// VIDEO Interface //////////////
	output reg    HBlank,
	output reg    nHSync,
	output reg    VBlank,
	output reg    nVSync,

	output [13:0] vram_a,
	output        vram_we,
	output  [7:0] vram_do,
	input   [7:0] vram_di,
	output  [7:0] R,
	output  [7:0] G,
	output  [7:0] B,
	input         border_en
);

reg ce_3m58 = 0;

always @(posedge clk_10m7) begin
	reg [2:0] div;
	if(reset) begin
		div <= 0;
		ce_3m58 <= 0;
	end
	else begin
		div <= div+1'd1;
		if (div == 2) begin
			ce_3m58 <= 1;
			div <= 0;
		end
		else ce_3m58 <= 0;
	end
end

reg nMEM;
reg nRD;
reg nWR;
reg nIRQ;
reg nINT;
reg nNMI;
reg nWAIT;
reg nM1;

reg [15:0] cpu_addr;
reg [7:0] data_to_cpu;
reg [7:0] data_from_cpu;

cpu_z80 Z80CPU(
	.CLK_4M(clk_3m58),
	.nRESET(~reset),
	.SDA(cpu_addr),
	.SDD_IN(data_to_cpu),
	.SDD_OUT(data_from_cpu),
	.nIORQ(nIRQ),
	.nMREQ(nMEM),
	.nM1(nM1),
	.nRD(nRD),
	.nWR(nWR),
	.nINT(nINT),
	.nNMI(nNMI),
	.nWAIT(nWAIT)
);

assign cpu_ram_we_n_o = ((cpu_ram_a_o >= 16'h7000 &&cpu_ram_a_o < 16'h8000) && (~nMEM && ~nWR)) ? 1'b0 : 1'b1;
assign nWAIT = 1'b1;
assign cpu_ram_a_o = cpu_addr;
assign cpu_ram_d_o = data_from_cpu;
assign data_to_cpu = vdp_rd ? vdp_data :
                     (~nRD && nMEM && cpu_addr[7:0] == 8'h10) ? {4'h0, keys[key_col][7:4]} :
                     (~nRD && nMEM && cpu_addr[7:0] == 8'h20) ? {4'hF, keys[key_col][3:0]} :
                     (~nRD && nMEM && cpu_addr[7:0] == 8'h40) ? {4'hF, keys[10][3:0]} :
//                     (~nRD && nMEM && cpu_addr[7:0] == 8'h60) ? 8'h00 :			//Cassette IN (not yet implemented)
							(~nIRQ && ~nM1) ? 8'hFF :
							cpu_ram_d_i;

///////////////////////////Video///////////////////////////
reg vdp_rd;
reg vdp_wr;
reg vdp_int;
reg [7:0] vdp_data;

 vdp18_core vdp(
	.clk_i(clk),
	.clk_en_10m7_i(ce_10m7),
	.reset_n_i(~reset),
	.csr_n_i(~vdp_rd),
	.csw_n_i(~vdp_wr),
	.mode_i(cpu_addr[0]),
	.int_n_o(vdp_int),
	.cd_i(data_from_cpu),
	.cd_o(vdp_data),
	.vram_we_o(vram_we),
	.vram_a_o(vram_a),
	.vram_d_o(vram_do),
	.vram_d_i(vram_di),
	.col_o(),
	.rgb_r_o(R),
	.rgb_g_o(G),
	.rgb_b_o(B),
	.hsync_n_o(nHSync),
	.vsync_n_o(nVSync),
	.blank_n_o(),
	.border_i(border_en),
	.hblank_o(HBlank),
	.vblank_o(VBlank),
	.comp_sync_n_o()
);
reg last_wr;
always @(posedge clk) last_wr <= ~nWR;

assign vdp_rd = (cpu_ram_a_o[15:1] == 15'h2000 && ~nRD && ~nMEM) ? 1'b1: 1'b0;
assign vdp_wr = (cpu_ram_a_o[15:1] == 15'h2000 && ~nWR && !last_wr) ? 1'b1: 1'b0;

///////////////////////////SOUND///////////////////////////
wire audio_we;
wire psg_ready_s;
wire [7:0] audio_data_in;
wire [7:0] aout_o;
sn76489_top #(.clock_div_16_g(1)) sound
(
      .clock_i(clk_10m7),
      .clock_en_i(ce_3m58),
      .res_n_i(~reset),
      .ce_n_i(~audio_we),
      .we_n_i(~audio_we),
      .ready_o(psg_ready_s),
      .d_i(audio_data_in),
      .aout_o(aout_o)
);




/////////////////////////// IO ///////////////////////////

reg [1:0] rd_sampler,wr_sampler;


always @(posedge clk_3m58) begin
	rd_sampler = {rd_sampler[0],nRD};
	wr_sampler = {wr_sampler[0],nWR};
end

reg [3:0] key_col;
reg last_vdp_int;
reg key_pressed;
reg new_key_pressed = 0;
always @(posedge clk_3m58) begin
   if(reset) begin
		audio_we <= 1'b0;
		audio_data_in <= 8'd0;
		key_pressed <= 1'b0;
	end
	else begin
		last_vdp_int <= vdp_int;
		if(~vdp_int && last_vdp_int) nNMI <=1'b0;
		if(~nNMI) nNMI <= 1'b1;
		
		//Check for Keypresses on VDP Interrupts when KEYBOARD COLUMN Requested is 0xF
		if(vdp_int != last_vdp_int) begin
			if( key_col == 4'hF) begin
				new_key_pressed = |keys[0] | |keys[1] | |keys[2] | |keys[3] | |keys[4] | |keys[5] | |keys[6] | |keys[7] | |keys[8];
				if(new_key_pressed && key_pressed != new_key_pressed) nINT <= 1'b0;
				key_pressed <= new_key_pressed;
			end
		end
			
		//IO WRITES
		if(~nWR && nMEM && wr_sampler == 2'b10) begin
			if(cpu_addr[7:0] == 8'h00) begin	//Cassette Motor Control
			end
			if(cpu_addr[7:0] == 8'h20) begin //Sets Keyboard Column to scan
				key_col <= data_from_cpu[3:0];
				nINT <= 1'b1;
			end

			if(cpu_addr[7:0] == 8'h40) begin //Audio
				audio_we <= 1'b1;
				audio_data_in <= data_from_cpu;
			end
			if(cpu_addr[7:0] == 8'h60) begin //Cassette OUT
			end
		
		end
		
		if (psg_ready_s && audio_we) audio_we <= 1'b0;
	end
end

assign audio = aout_o;

///////////////////////////Keyboard///////////////////////////

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];

always @(posedge clk) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code[7:0])
			'h16: btn_1     <= pressed; // 1
			'h1E: btn_2     <= pressed; // 2
			'h26: btn_3     <= pressed; // 3
			'h25: btn_4     <= pressed; // 4
			'h2E: btn_5     <= pressed; // 5
			'h36: btn_6     <= pressed; // 6
			'h3D: btn_7     <= pressed; // 7
			'h3E: btn_8     <= pressed; // 8
			'h46: btn_9     <= pressed; // 9
			'h45: btn_0     <= pressed; // 0
			'h4E: btn_min   <= pressed; // -
			'h55: btn_yen   <= pressed; // = => YEN Key

			'h15: btn_q     <= pressed; // q
			'h1D: btn_w     <= pressed; // w
			'h24: btn_e     <= pressed; // e
			'h2D: btn_r     <= pressed; // r
			'h2C: btn_t     <= pressed; // t
			'h35: btn_y     <= pressed; // y
			'h3C: btn_u     <= pressed; // u
			'h43: btn_i     <= pressed; // i
			'h44: btn_o     <= pressed; // o
			'h4D: btn_p     <= pressed; // p
			'h54: btn_ob    <= pressed; // [ => _
			'h5D: btn_at    <= pressed; // \ => ]
			'h5B: btn_cb    <= pressed; // ] => [
			
			'h1C: btn_a     <= pressed; // a
			'h1B: btn_s     <= pressed; // s
			'h23: btn_d     <= pressed; // d
			'h2B: btn_f     <= pressed; // f
			'h34: btn_g     <= pressed; // g
			'h33: btn_h     <= pressed; // h
			'h3B: btn_j     <= pressed; // j
			'h42: btn_k     <= pressed; // k
			'h4B: btn_l     <= pressed; // l
			'h4C: btn_se    <= pressed; // ;
			'h5A: btn_rt    <= pressed; // enter
			
			'h12: btn_sh    <= pressed; // lshift
			'h1A: btn_z     <= pressed; // z
			'h22: btn_x     <= pressed; // x
			'h21: btn_c     <= pressed; // c
			'h2A: btn_v     <= pressed; // v
			'h32: btn_b     <= pressed; // b
			'h31: btn_n     <= pressed; // n
			'h3A: btn_m     <= pressed; // m
			'h41: btn_co    <= pressed; // ,
			'h49: btn_pe    <= pressed; // .
			'h4A: btn_fs    <= pressed; // /
			'h59: btn_sh    <= pressed; // rshift

			'h58: btn_al    <= pressed; // caps => English/Hiragana
			'h14:
				begin
					if(code[8]) btn_func <= pressed; //rctrl
					else btn_atk0  <= pressed; // lctrl
				end
			'h11:
				begin
					if(code[8]) btn_color <= pressed; //ralt
					else btn_atk1  <= pressed; // lalt
				end
			'h29: btn_sp    <= pressed; // space
			'h66: btn_left  <= pressed; // BackSpace
			'h76: btn_stop  <= pressed; // ESC
			'h70: btn_del   <= pressed; // INS
			'h71: btn_del   <= pressed; // DEL
			'h6C:
				begin
					if(code[8]) btn_home  <= pressed; // HOME
					else btn_cul <= pressed;
				end
			'h52: btn_col   <= pressed; // Quotes => ;/*
			'h0E: btn_tilde <= pressed; // Tilde
			'h05: btn_mode  <= pressed; // F1 => MODE Key
			
			'h69: btn_cdl   <= pressed; // KeyPad 1
			'h72: btn_down  <= pressed; // KeyPad 2
			'h7A: btn_cdr   <= pressed; // KeyPad 3
			'h6B: btn_left  <= pressed; // KeyPad 4
			'h74: btn_right <= pressed; // KeyPad 6
			'h75: btn_up    <= pressed; // KeyPad 8
			'h7D:
				begin
					if(code[8]) btn_stop <= pressed;
					else btn_cur   <= pressed; // KeyPad 9
				end
			'h78: btn_us<= pressed; // F1

		endcase
	end
end


// Keyboard
reg btn_1 = 0;
reg btn_2 = 0;
reg btn_3 = 0;
reg btn_4 = 0;
reg btn_5 = 0;
reg btn_6 = 0;
reg btn_7 = 0;
reg btn_8 = 0;
reg btn_9 = 0;
reg btn_0 = 0;
reg btn_min = 0;

reg btn_q = 0;
reg btn_w = 0;
reg btn_e = 0;
reg btn_r = 0;
reg btn_t = 0;
reg btn_y = 0;
reg btn_u = 0;
reg btn_i = 0;
reg btn_o = 0;
reg btn_p = 0;
reg btn_rt = 0;
			
reg btn_a = 0;
reg btn_s = 0;
reg btn_d = 0;
reg btn_f = 0;
reg btn_g = 0;
reg btn_h = 0;
reg btn_j = 0;
reg btn_k = 0;
reg btn_l = 0;
reg btn_se = 0;
reg btn_col = 0;
reg btn_ob = 0; //Open Bracket
			
reg btn_z = 0;
reg btn_x = 0;
reg btn_c = 0;
reg btn_v = 0;
reg btn_b = 0;
reg btn_n = 0;
reg btn_m = 0;
reg btn_co = 0;
reg btn_pe = 0;
reg btn_fs = 0;
reg btn_cb = 0; //Close Bracket

reg btn_at = 0;
reg btn_al = 0;
reg btn_sh = 0;
reg btn_atk0 = 0;
reg btn_atk1 = 0;
reg btn_sp = 0;
reg btn_mode = 0;
reg btn_yen = 0;
reg btn_color = 0;
reg btn_stop = 0;
reg btn_func = 0;
reg btn_del = 0;
reg btn_home = 0;
reg btn_tilde = 0;

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_left  = 0;
reg btn_right = 0;

reg btn_cdl = 0;
reg btn_cdr = 0;
reg btn_cul = 0;
reg btn_cur = 0;

reg btn_us = 0;

wire [7:0] keys[11];

assign keys[0] = {btn_5,    btn_6,    btn_7,    btn_8,    btn_1,    btn_2,    btn_3,    btn_4};
assign keys[1] = {btn_t,    btn_y,    btn_u,    btn_i,    btn_q,    btn_w,    btn_e,    btn_r};
assign keys[2] = {btn_g,    btn_h,    btn_j,    btn_k,    btn_a,    btn_s,    btn_d,    btn_f};
assign keys[3] = {btn_v,    btn_b,    btn_n,    btn_sp,    btn_al,    btn_z,    btn_x,    btn_c};
assign keys[4] = {btn_0,    btn_tilde,    btn_min,    btn_9,    btn_home,    joy0[6] | joy1[6],    joy0[7] | joy1[7],    btn_yen};
assign keys[5] = {btn_p,    btn_ob,    btn_at,    btn_o,    btn_cur,    btn_cdr,    btn_cdl,    btn_cul};
assign keys[6] = {btn_se,    btn_cb,    btn_col,    btn_l,    joy1[0],    joy1[2],    btn_right | joy0[0],    btn_down | joy0[2]};
assign keys[7] = {btn_co,    btn_fs,    btn_pe,    btn_m,    joy1[3],    joy1[1],    btn_up | joy0[3],    btn_left | joy0[1]};
assign keys[8] = {btn_us,    btn_del,    btn_mode,    btn_rt,    joy1[5],    joy1[4],    btn_atk1 | joy0[5],    btn_atk0 | joy0[4]};
assign keys[9] = {4'd0,    btn_stop,    3'd0};
assign keys[10] = {5'd0,    btn_sh,    btn_func,    btn_color};


endmodule
//224x224
//  380x262
//  HBLANK 239 -> 15 (16-1)
//  VBLANK 223 -> 262
//  HSYNC  341 -> 360
//  VSYNC  260 -> 0  (end of 259 to end of 262)