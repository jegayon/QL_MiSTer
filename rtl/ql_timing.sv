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
	
	input			cpu_uds,
	input			cpu_lds,
	input       cpu_rw,
	input			cpu_rom,
	input			cpu_bram,	// the 128K of RAM on the motherboard, shared with the ZX8301

	output		ram_delay_dtack
);

reg delay_reg;


reg [5:0] chunk;					// We got 40 chunks per display line...
reg [3:0] chunkCycle;			// ...with 12 cycles per chunk

wire [5:0] num_busy_chunks = VBlank ? 6'd13 : 6'd31;	// 31 chunks used by ZX8301 for video, 13 in the border lines (measured on a real QL)
wire could_start = chunk >= num_busy_chunks || chunkCycle == 4'd0; // For used chunks, the CPU can only access RAM in-between 


wire ds;
assign ds = cpu_uds || cpu_lds;
reg prev_ds;

// The 68000 asserts DS late in a write cycle, just before it samples DTACK: the wait must
// start as soon as DS rises, not on the next bus cycle, or a write would not see it.
// (Reads assert DS earlier, so for them nothing changes.)
wire new_access_wait = enable && ds && !prev_ds && (cpu_bram || (cpu_uds && cpu_lds));
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
	end 
	else
	begin
		if (ce_bus_p)
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

			if (ds && ~prev_ds && !cpu_bram)
			begin
				// New bus access outside the 128K on the motherboard (ROM, I/O, expansion RAM):
				// the ZX8301 is not involved, so there are no wait states. A 16 bit access only
				// takes the second access of the 8 bit bus of the 68008 (counted from DS, which
				// rises one cycle later in a write).
				delay_reg <= cpu_uds && cpu_lds;
				dtack_count <= cpu_rw ? 3'd4 : 3'd3;
				extra_access <= 0;
			end
			else if (ds && ~prev_ds && could_start)
			begin
				// New bus access to the 128K on the motherboard in a free chunk: it goes on at
				// once. A 16 bit access still takes its second access, which again waits for a
				// free chunk. (A write gets its first wait state from new_access_wait, as the
				// ZX8301 only checks DS.)
				delay_reg <= cpu_uds && cpu_lds;
				dtack_count <= cpu_rw ? 3'd4 : 3'd5;
				extra_access <= 0;
			end
			else if (ds && ~prev_ds)
			begin
				// New bus access to the 128K on the motherboard in a busy chunk: wait for the
				// ZX8301 to let it start.
				delay_reg <= 1;
				dtack_count <= 3'd1;
				extra_access <= cpu_uds && cpu_lds;	// 16bit access?
			end
			else
			begin
				if (dtack_count == 3'd1 && delay_reg)
				begin
					// Only the 128K on the motherboard are shared with the ZX8301: ROM,
					// I/O and expansion RAM never wait for its chunks (they still pay
					// the second access of the 8 bit bus of the 68008)
					if (could_start || !cpu_bram)
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