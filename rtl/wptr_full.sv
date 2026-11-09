//-----------------------------------------------------------------------------
// Module      : wptr_full
// Description : Write-side pointer logic (wclk domain).
//               - Binary pointer addresses the memory.
//               - Gray-code copy (wptr) is sent to the read domain, so only
//                 one bit changes per increment.
//               - FULL: next Gray write pointer equals the synchronized Gray
//                 read pointer with its two MSBs inverted.
//               - wfull is registered and computed from the NEXT pointer
//                 value, so it asserts in the same cycle the last slot fills.
//               - Because the read pointer arrives ~2 cycles late, full may
//                 stay set slightly longer than necessary (pessimistic, safe).
//-----------------------------------------------------------------------------
module wptr_full #(
  parameter int AW = 4                          // address width (>= 2)
) (
  input  logic          wclk,
  input  logic          wrst_n,
  input  logic          winc,                   // write request
  input  logic [AW:0]   wq2_rptr,               // Gray read pointer, synced to wclk
  output logic          wfull,
  output logic [AW-1:0] waddr,                  // memory write address
  output logic [AW:0]   wptr,                   // Gray write pointer (to read domain)
  output logic [AW:0]   wcount                  // fill level seen by writer (>= actual)
);

  logic [AW:0] wbin, wbin_next, wgray_next;
  logic        wfull_next;

  function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
    logic [AW:0] b;
    b[AW] = g[AW];
    for (int i = AW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
    return b;
  endfunction

  // Advance only when the write is accepted
  assign wbin_next  = wbin + {{AW{1'b0}}, (winc & ~wfull)};
  assign wgray_next = (wbin_next >> 1) ^ wbin_next;

  // Full: wrapped one more time than the reader (MSB and MSB-1 differ in Gray)
  assign wfull_next = (wgray_next == {~wq2_rptr[AW:AW-1], wq2_rptr[AW-2:0]});

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wbin  <= '0;
      wptr  <= '0;
      wfull <= 1'b0;
    end else begin
      wbin  <= wbin_next;
      wptr  <= wgray_next;
      wfull <= wfull_next;
    end
  end

  assign waddr  = wbin[AW-1:0];
  assign wcount = wbin - gray2bin(wq2_rptr);

endmodule
