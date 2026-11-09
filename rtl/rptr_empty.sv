//-----------------------------------------------------------------------------
// Module      : rptr_empty
// Description : Read-side pointer logic (rclk domain).
//               - Binary pointer addresses the memory.
//               - Gray-code copy (rptr) is sent to the write domain.
//               - EMPTY: next Gray read pointer equals the synchronized Gray
//                 write pointer.
//               - rempty is registered, computed from the NEXT pointer value,
//                 and resets to 1.
//               - Because the write pointer arrives ~2 cycles late, empty may
//                 stay set slightly longer than necessary (pessimistic, safe).
//-----------------------------------------------------------------------------
module rptr_empty #(
  parameter int AW = 4                          // address width (>= 2)
) (
  input  logic          rclk,
  input  logic          rrst_n,
  input  logic          rinc,                   // read request
  input  logic [AW:0]   rq2_wptr,               // Gray write pointer, synced to rclk
  output logic          rempty,
  output logic [AW-1:0] raddr,                  // memory read address
  output logic [AW:0]   rptr,                   // Gray read pointer (to write domain)
  output logic [AW:0]   rcount                  // fill level seen by reader (<= actual)
);

  logic [AW:0] rbin, rbin_next, rgray_next;
  logic        rempty_next;

  function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
    logic [AW:0] b;
    b[AW] = g[AW];
    for (int i = AW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
    return b;
  endfunction

  // Advance only when the read is accepted
  assign rbin_next   = rbin + {{AW{1'b0}}, (rinc & ~rempty)};
  assign rgray_next  = (rbin_next >> 1) ^ rbin_next;

  // Empty: reader has caught up with the (synchronized) writer
  assign rempty_next = (rgray_next == rq2_wptr);

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rbin   <= '0;
      rptr   <= '0;
      rempty <= 1'b1;
    end else begin
      rbin   <= rbin_next;
      rptr   <= rgray_next;
      rempty <= rempty_next;
    end
  end

  assign raddr  = rbin[AW-1:0];
  assign rcount = gray2bin(rq2_wptr) - rbin;

endmodule
