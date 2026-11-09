//-----------------------------------------------------------------------------
// Module      : async_fifo
// Description : Parameterized asynchronous (dual-clock) FIFO.
//               Write and read sides run on unrelated clocks.
//               Clock domain crossing uses Gray-code pointers passed through
//               2-flop synchronizers (Cummings-style architecture).
//
//               Reset: assert wrst_n and rrst_n together; release each one
//               synchronously to its own clock (use a reset synchronizer in
//               a real system).
//-----------------------------------------------------------------------------
module async_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16                  // power of 2, >= 4
) (
  // Write side (wclk domain)
  input  logic                    wclk,
  input  logic                    wrst_n,
  input  logic                    wr_en,
  input  logic [DATA_WIDTH-1:0]   wr_data,
  output logic                    full,
  output logic [$clog2(DEPTH):0]  wr_count,      // fill level seen by writer
  output logic                    overflow,      // 1-cycle pulse: write while full

  // Read side (rclk domain)
  input  logic                    rclk,
  input  logic                    rrst_n,
  input  logic                    rd_en,
  output logic [DATA_WIDTH-1:0]   rd_data,       // valid 1 rclk after accepted read
  output logic                    empty,
  output logic [$clog2(DEPTH):0]  rd_count,      // fill level seen by reader
  output logic                    underflow      // 1-cycle pulse: read while empty
);

  localparam int AW = $clog2(DEPTH);

  // synthesis translate_off
  initial begin
    if (DEPTH < 4 || (DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "async_fifo: DEPTH (%0d) must be a power of 2 and >= 4", DEPTH);
  end
  // synthesis translate_on

  //---------------------------------------------------------------------------
  // Internal signals
  //---------------------------------------------------------------------------
  logic [AW-1:0] waddr, raddr;
  logic [AW:0]   wptr, rptr;          // Gray pointers (source domains)
  logic [AW:0]   wq2_rptr;            // read pointer synchronized to wclk
  logic [AW:0]   rq2_wptr;            // write pointer synchronized to rclk
  logic          wen, ren;

  assign wen = wr_en & ~full;
  assign ren = rd_en & ~empty;

  //---------------------------------------------------------------------------
  // Dual-port memory
  //---------------------------------------------------------------------------
  fifo_mem #(
    .DATA_WIDTH (DATA_WIDTH),
    .AW         (AW)
  ) u_mem (
    .wclk  (wclk),
    .wen   (wen),
    .waddr (waddr),
    .wdata (wr_data),
    .rclk  (rclk),
    .ren   (ren),
    .raddr (raddr),
    .rdata (rd_data)
  );

  //---------------------------------------------------------------------------
  // Clock domain crossing: Gray pointers through 2-flop synchronizers
  //---------------------------------------------------------------------------
  sync_2ff #(.WIDTH(AW + 1)) u_sync_r2w (
    .clk   (wclk),
    .rst_n (wrst_n),
    .d     (rptr),
    .q     (wq2_rptr)
  );

  sync_2ff #(.WIDTH(AW + 1)) u_sync_w2r (
    .clk   (rclk),
    .rst_n (rrst_n),
    .d     (wptr),
    .q     (rq2_wptr)
  );

  //---------------------------------------------------------------------------
  // Pointer and flag logic
  //---------------------------------------------------------------------------
  wptr_full #(.AW(AW)) u_wptr_full (
    .wclk     (wclk),
    .wrst_n   (wrst_n),
    .winc     (wr_en),
    .wq2_rptr (wq2_rptr),
    .wfull    (full),
    .waddr    (waddr),
    .wptr     (wptr),
    .wcount   (wr_count)
  );

  rptr_empty #(.AW(AW)) u_rptr_empty (
    .rclk     (rclk),
    .rrst_n   (rrst_n),
    .rinc     (rd_en),
    .rq2_wptr (rq2_wptr),
    .rempty   (empty),
    .raddr    (raddr),
    .rptr     (rptr),
    .rcount   (rd_count)
  );

  //---------------------------------------------------------------------------
  // Error pulses (each in its own domain)
  //---------------------------------------------------------------------------
  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) overflow <= 1'b0;
    else         overflow <= wr_en & full;
  end

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) underflow <= 1'b0;
    else         underflow <= rd_en & empty;
  end

endmodule
