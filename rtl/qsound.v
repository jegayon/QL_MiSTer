//
// qsound.v - QSound Adapter for Sinclair QL powered by Jotego's JT49 Engine
// Accurate Control Bus decoding: BC1=Bit 0, BDIR=Bit 2
// Includes Mono / Stereo ABC / Stereo ACB Mixer
//

module qsound
(
	input         clk,          // 84 MHz clk_sys
	input         reset,
	input         enable,

	// CPU Bus Interface (68008)
	input  [23:0] addr,
	input   [7:0] din,
	output  [7:0] dout,
	input         rd,
	input         wr,

	// Clock Enable (750 kHz / 1.0 MHz / 1.77 MHz / 2.0 MHz)
	input         ce_ay,

	// Modo de Audio: 0=Mono, 1=Estéreo ABC, 2=Estéreo ACB
	input   [1:0] stereo_mode,

	// Audio Output (15-bit unsigned)
	output [14:0] sound_l,
	output [14:0] sound_r
);

// Decodificación de espacio 0xC0000 - 0xC3FFF
wire qsound_space = enable && (addr[23:16] == 8'h0C);
wire sel_pia_data = qsound_space && (addr[15:2] == 14'b0010_0000_0000_00) && !addr[1]; // 0xC2000
wire sel_pia_ctrl = qsound_space && (addr[15:2] == 14'b0010_0000_0000_00) &&  addr[1]; // 0xC2002
wire sel_dir_addr = qsound_space && (addr[15:2] == 14'b0011_0000_0000_00) && !addr[1]; // 0xC3000
wire sel_dir_data = qsound_space && (addr[15:2] == 14'b0011_0000_0000_00) &&  addr[1]; // 0xC3002

reg [7:0] port_a;
reg [7:0] port_b;
reg [3:0] ay_addr;

// A bus cycle of the 68008 lasts many cycles of clk: each write acts only on
// its first one (writing the envelope shape twice would restart it)
wire wr_access = wr && (sel_pia_data || sel_pia_ctrl || sel_dir_addr || sel_dir_data);
reg  wr_access_d;
wire wr_start = wr_access && !wr_access_d;

always @(posedge clk) begin
	if (reset) begin
		port_a  <= 8'h00;
		port_b  <= 8'h00;
		ay_addr <= 4'h0;
		wr_access_d <= 1'b0;
	end else begin
		wr_access_d <= wr_access;
		if (wr_start && sel_dir_addr) ay_addr <= din[3:0];
		if (wr_start && sel_pia_data) port_a  <= din;
		if (wr_start && sel_pia_ctrl) begin
			port_b <= din;
			// BDIR=Bit 2, BC1=Bit 0 -> 0x0F = Latch Address
			if (din[2] && din[0]) ay_addr <= port_a[3:0];
		end
	end
end

// Pulso de escritura SOLO cuando BDIR=1 y BC1=0 (0x0E en control) o en modo directo
wire jt49_wr_pulse = (wr_start && sel_dir_data) ||
                     (wr_start && sel_pia_ctrl && din[2] && !din[0]);

wire [7:0] jt49_din = sel_dir_data ? din : port_a;
wire [7:0] jt49_dout;

assign dout = (sel_pia_data && port_b[0]) ? jt49_dout :
              (sel_pia_data)              ? port_a    :
              (sel_dir_data)              ? jt49_dout : 8'hFF;

// *************************************************************************
// 					INSTANCIA DEL NÚCLEO JT49 DE JOTEGO
// *************************************************************************

wire [7:0] ch_a, ch_b, ch_c;
wire [9:0] jt49_sample;

jt49 u_jt49 (
	.rst_n    ( ~reset           ),
	.clk      ( clk              ),
	.clk_en   ( ce_ay            ),
	.addr     ( ay_addr          ),
	.cs_n     ( ~enable          ),
	.wr_n     ( ~jt49_wr_pulse   ),
	.din      ( jt49_din         ),
	.sel      ( 1'b1             ), // 1 = Modo AY-3-8910
	.dout     ( jt49_dout        ),
	.sound    (                  ),
	.A        ( ch_a             ),
	.B        ( ch_b             ),
	.C        ( ch_c             ),
	.sample   ( jt49_sample      ),
	.IOA_in   ( 8'hFF            ),
	.IOB_in   ( 8'hFF            ),
	.IOA_out  (                  ),
	.IOB_out  (                  ),
	.IOA_oe   (                  ),
	.IOB_oe   (                  )
);

// *************************************************************************
// 					MEZCLADOR MONO / ESTÉREO ABC / ACB
// *************************************************************************

// Amplitud base de cada canal
wire [14:0] amp_a = {ch_a, 5'd0};
wire [14:0] amp_b = {ch_b, 5'd0};
wire [14:0] amp_c = {ch_c, 5'd0};

// Mezcla Mono (A + B + C)
wire [14:0] mono_mix = (amp_a + amp_b + amp_c);

// Salidas según el modo seleccionado (0=Mono, 1=ABC, 2=ACB)
assign sound_l = !enable ? 15'd0 :
                 (stereo_mode == 2'b00) ? mono_mix :                      // Mono
                 (stereo_mode == 2'b01) ? (amp_a + amp_a + amp_b) :       // ABC (A izquierda + B centro)
                                          (amp_a + amp_a + amp_c);        // ACB (A izquierda + C centro)

assign sound_r = !enable ? 15'd0 :
                 (stereo_mode == 2'b00) ? mono_mix :                      // Mono
                 (stereo_mode == 2'b01) ? (amp_c + amp_c + amp_b) :       // ABC (C derecha + B centro)
                                          (amp_b + amp_b + amp_c);        // ACB (B derecha + C centro)

endmodule