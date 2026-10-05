// QL RAM timing simulation
//
// Copyright (C) 2019 Marcel Kilgus
// Copyright (c) 2021 Daniele Terdina
//
// Much of the original QL RAM is used to generate the video signal. This module tries to slow
// down the SDRAM access similarly to the original timing

module ql_timing
(
	input			clk_sys,
	input  		reset,
	input			enable,
	input			ce_bus_p,
	input			VBlank,
	input			line_start,	// first pixel of the visible area of a line (zx8301)
	
	input			cpu_uds,
	input			cpu_lds,
	input       cpu_rw,
	input			cpu_rom,
	input			cpu_bram,	// the 128K of RAM on the motherboard, shared with the ZX8301
	input			ql_io,		// the peripheral registers, $18000-$1BFFF

	output		ram_delay_dtack
);

reg delay_reg;


reg [5:0] chunk;					// We got 40 chunks per display line...
reg [3:0] chunkCycle;			// ...with 12 cycles per chunk

// On a ZX8301 the chunks are always in the same place within each line, as
// the chip that draws the line also decides when the CPU may access the RAM.
// So the chunk counter is set again at every line, when the visible area
// begins: the busy chunks start at the first visible pixel. With this
// position ql26inv runs as on a real QL. Chunk 18 brings a pass of one of
// its scenes one count closer to a real QL (drawing 1449 against 1448,
// 1452 here), but then the demo crashes, so the result of the demo, which
// is on a knife edge, decided. The position hardly changes simpler loops
// (perfil3_bas) or the timing tests
localparam [5:0] CHUNK_AT_LINE = 6'd0;
localparam [3:0] CYCLE_AT_LINE = 4'd0;
reg line_sync;

// 32 chunks used by the ZX8301 in the visible lines and 8 in the border ones, measured on a
// real QL by timing a copy loop line by line through the frame (perfil3_bas)
wire [5:0] num_busy_chunks = VBlank ? 6'd8 : 6'd32;

// Accesses that wait for the ZX8301: the 128K on the motherboard, and reads of the peripheral
// registers (on a real QL a loop reading $18021 is slower on the visible lines than on the
// border ones, by as much as a RAM access; writes do not wait, or the link with the IPC would
// be slower than on a real QL)
wire contended = cpu_bram || (ql_io && cpu_rw);
wire could_start = chunk >= num_busy_chunks || chunkCycle == 4'd0; // For used chunks, the CPU can only access RAM in-between 


wire ds;
assign ds = cpu_uds || cpu_lds;
reg prev_ds;

// The 68000 asserts DS late in a write cycle, just before it samples DTACK: the wait must
// start as soon as DS rises, not on the next bus cycle, or a write would not see it.
// (Reads assert DS earlier, so for them nothing changes.)
wire new_access_wait = enable && ds && !prev_ds && (contended || (cpu_uds && cpu_lds));
assign ram_delay_dtack = delay_reg || new_access_wait;


reg [2:0] dtack_count;
reg extra_access;

always @(posedge clk_sys)
begin
	if (reset || !enable)
	begin
		chunk <= 0;
		chunkCycle <= 0;
		delay_reg <= 0;
		line_sync <= 0;
	end 
	else
	begin
		if (line_start)
			line_sync <= 1;

		if (ce_bus_p)
		begin
			if (line_sync)
			begin
				// New line
				line_sync <= 0;
				chunk <= CHUNK_AT_LINE;
				chunkCycle <= CYCLE_AT_LINE;
			end
			else
			begin
				chunkCycle <= chunkCycle + 4'd1;
				if (chunkCycle == 4'd11)
				begin
					chunkCycle <= 4'd0;
					if (chunk == 6'd39) 
						chunk <= 6'd0;
					else
						chunk <= chunk + 6'd1;
				end
			end

			if (ds && ~prev_ds && !contended)
			begin
				// New bus access that does not wait for the ZX8301 (ROM, expansion RAM, writes
				// to the peripheral registers): there are no wait states. A 16 bit access only
				// takes the second access of the 8 bit bus of the 68008 (counted from DS, which
				// rises one cycle later in a write).
				delay_reg <= cpu_uds && cpu_lds;
				dtack_count <= cpu_rw ? 3'd4 : 3'd3;
				extra_access <= 0;
			end
			else if (ds && ~prev_ds && could_start)
			begin
				// New bus access that waits for the ZX8301, in a free chunk: it goes on at
				// once. A 16 bit access still takes its second access, which again waits for a
				// free chunk. (A write gets its first wait state from new_access_wait, as the
				// ZX8301 only checks DS.)
				delay_reg <= cpu_uds && cpu_lds;
				dtack_count <= cpu_rw ? 3'd4 : 3'd5;
				extra_access <= 0;
			end
			else if (ds && ~prev_ds)
			begin
				// New bus access that waits for the ZX8301, in a busy chunk: wait for the
				// ZX8301 to let it start.
				delay_reg <= 1;
				dtack_count <= 3'd1;
				extra_access <= cpu_uds && cpu_lds;	// 16bit access?
			end
			else
			begin
				if (dtack_count == 3'd1 && delay_reg)
				begin
					// Only the 128K on the motherboard and the reads of the peripheral
					// registers wait for its chunks: ROM, expansion RAM and the writes to
					// the peripheral registers never do (they still pay the second access
					// of the 8 bit bus of the 68008)
					if (could_start || !contended)
					begin
						if (extra_access)
						begin
							// For 16 bit access, add wait states to simulate the time it takes the 68008
							// to complete a second bus access
							dtack_count <= cpu_rw ? 3'd4 : 3'd5;
							extra_access <= 0;
						end
						else
						begin
							delay_reg <= 0;
						end
					end
				end
				else
				begin
					dtack_count <= dtack_count - 3'd1;
				end
			end
			prev_ds <= ds;
		end
	end
end

endmodule