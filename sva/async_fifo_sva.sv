//-----------------------------------------------------------------------------
// Module      : async_fifo_sva
// Description : SystemVerilog Assertions for async_fifo, attached with `bind`.
//               Write-domain properties are clocked by wclk, read-domain
//               properties by rclk. Cross-domain safety properties use the
//               real (unsynchronized) pointers to prove the FIFO never
//               overwrites unread data and never reads unwritten data.
//-----------------------------------------------------------------------------
module async_fifo_sva #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16
) (
  // Write domain
  input logic                    wclk,
  input logic                    wrst_n,
  input logic                    wr_en,
  input logic                    full,
  input logic [$clog2(DEPTH):0]  wr_count,
  input logic                    overflow,
  // Read domain
  input logic                    rclk,
  input logic                    rrst_n,
  input logic                    rd_en,
  input logic                    empty,
  input logic [$clog2(DEPTH):0]  rd_count,
  input logic                    underflow,
  input logic [DATA_WIDTH-1:0]   rd_data,
  // Internal DUT signals
  input logic [$clog2(DEPTH):0]  wptr,       // Gray write pointer
  input logic [$clog2(DEPTH):0]  rptr,       // Gray read pointer
  input logic [$clog2(DEPTH):0]  wq2_rptr,   // read pointer synced to wclk
  input logic [$clog2(DEPTH):0]  rq2_wptr    // write pointer synced to rclk
);

  localparam int AW = $clog2(DEPTH);

  function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
    logic [AW:0] b;
    b[AW] = g[AW];
    for (int i = AW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
    return b;
  endfunction

  // True number of entries, computed from the real pointers
  logic [AW:0] occupancy;
  assign occupancy = gray2bin(wptr) - gray2bin(rptr);

  //===========================================================================
  // WRITE DOMAIN (wclk)
  //===========================================================================
  a_wreset_state: assert property (@(posedge wclk)
    !wrst_n |-> (wptr == '0 && !full && !overflow))
    else $error("SVA: write side not cleared during reset");

  a_wptr_gray: assert property (@(posedge wclk) disable iff (!wrst_n)
    $onehot0(wptr ^ $past(wptr)))
    else $error("SVA: Gray write pointer changed more than 1 bit");

  a_wptr_advance: assert property (@(posedge wclk) disable iff (!wrst_n)
    (wr_en && !full) |=> (wptr != $past(wptr)))
    else $error("SVA: accepted write did not advance write pointer");

  a_wptr_hold_idle: assert property (@(posedge wclk) disable iff (!wrst_n)
    !wr_en |=> $stable(wptr))
    else $error("SVA: write pointer moved without a write");

  a_wptr_hold_full: assert property (@(posedge wclk) disable iff (!wrst_n)
    (wr_en && full) |=> $stable(wptr))
    else $error("SVA: write pointer moved while FIFO was full");

  a_overflow_set: assert property (@(posedge wclk) disable iff (!wrst_n)
    (wr_en && full) |=> overflow)
    else $error("SVA: overflow not flagged");

  a_overflow_clr: assert property (@(posedge wclk) disable iff (!wrst_n)
    !(wr_en && full) |=> !overflow)
    else $error("SVA: spurious overflow flag");

  a_wr_count_range: assert property (@(posedge wclk) disable iff (!wrst_n)
    wr_count <= DEPTH)
    else $error("SVA: wr_count %0d exceeds DEPTH", wr_count);

  a_wr_known: assert property (@(posedge wclk) disable iff (!wrst_n)
    !$isunknown({full, wr_count, overflow, wptr}))
    else $error("SVA: X/Z on write-side outputs");

  //===========================================================================
  // READ DOMAIN (rclk)
  //===========================================================================
  a_rreset_state: assert property (@(posedge rclk)
    !rrst_n |-> (rptr == '0 && empty && !underflow))
    else $error("SVA: read side not cleared during reset");

  a_rptr_gray: assert property (@(posedge rclk) disable iff (!rrst_n)
    $onehot0(rptr ^ $past(rptr)))
    else $error("SVA: Gray read pointer changed more than 1 bit");

  a_rptr_advance: assert property (@(posedge rclk) disable iff (!rrst_n)
    (rd_en && !empty) |=> (rptr != $past(rptr)))
    else $error("SVA: accepted read did not advance read pointer");

  a_rptr_hold_idle: assert property (@(posedge rclk) disable iff (!rrst_n)
    !rd_en |=> $stable(rptr))
    else $error("SVA: read pointer moved without a read");

  a_rptr_hold_empty: assert property (@(posedge rclk) disable iff (!rrst_n)
    (rd_en && empty) |=> $stable(rptr))
    else $error("SVA: read pointer moved while FIFO was empty");

  a_underflow_set: assert property (@(posedge rclk) disable iff (!rrst_n)
    (rd_en && empty) |=> underflow)
    else $error("SVA: underflow not flagged");

  a_underflow_clr: assert property (@(posedge rclk) disable iff (!rrst_n)
    !(rd_en && empty) |=> !underflow)
    else $error("SVA: spurious underflow flag");

  a_rd_count_range: assert property (@(posedge rclk) disable iff (!rrst_n)
    rd_count <= DEPTH)
    else $error("SVA: rd_count %0d exceeds DEPTH", rd_count);

  a_rd_known: assert property (@(posedge rclk) disable iff (!rrst_n)
    !$isunknown({empty, rd_count, underflow, rptr}))
    else $error("SVA: X/Z on read-side outputs");

  a_rd_data_known: assert property (@(posedge rclk) disable iff (!rrst_n)
    (rd_en && !empty) |=> !$isunknown(rd_data))
    else $error("SVA: X/Z on rd_data after a read");

  //===========================================================================
  // CROSS-DOMAIN SAFETY (uses the real pointers)
  //===========================================================================
  a_no_overwrite: assert property (@(posedge wclk) disable iff (!wrst_n || !rrst_n)
    (wr_en && !full) |-> (occupancy < DEPTH))
    else $error("SVA: write accepted while FIFO truly full (data overwritten)");

  a_no_read_unwritten: assert property (@(posedge rclk) disable iff (!wrst_n || !rrst_n)
    (rd_en && !empty) |-> (occupancy != 0))
    else $error("SVA: read accepted while FIFO truly empty");

  a_occupancy_range: assert property (@(posedge wclk) disable iff (!wrst_n || !rrst_n)
    occupancy <= DEPTH)
    else $error("SVA: occupancy %0d exceeds DEPTH", occupancy);

  //===========================================================================
  // COVER PROPERTIES
  //===========================================================================
  c_full:            cover property (@(posedge wclk) disable iff (!wrst_n) full);
  c_write_when_full: cover property (@(posedge wclk) disable iff (!wrst_n) wr_en && full);
  c_full_released:   cover property (@(posedge wclk) disable iff (!wrst_n) full ##1 !full);
  c_read_when_empty: cover property (@(posedge rclk) disable iff (!rrst_n) rd_en && empty);
  c_empty_released:  cover property (@(posedge rclk) disable iff (!rrst_n) empty ##1 !empty);
  c_rd_sees_full:    cover property (@(posedge rclk) disable iff (!rrst_n) rd_count == DEPTH);

endmodule

//-----------------------------------------------------------------------------
// Bind the checker into every instance of async_fifo
//-----------------------------------------------------------------------------
bind async_fifo async_fifo_sva #(
  .DATA_WIDTH (DATA_WIDTH),
  .DEPTH      (DEPTH)
) u_async_fifo_sva (
  .wclk      (wclk),
  .wrst_n    (wrst_n),
  .wr_en     (wr_en),
  .full      (full),
  .wr_count  (wr_count),
  .overflow  (overflow),
  .rclk      (rclk),
  .rrst_n    (rrst_n),
  .rd_en     (rd_en),
  .empty     (empty),
  .rd_count  (rd_count),
  .underflow (underflow),
  .rd_data   (rd_data),
  .wptr      (wptr),
  .rptr      (rptr),
  .wq2_rptr  (wq2_rptr),
  .rq2_wptr  (rq2_wptr)
);
