//-----------------------------------------------------------------------------
// Module      : fifo_mem
// Description : Simple dual-port memory for the asynchronous FIFO.
//               - Write port is clocked by wclk, read port by rclk.
//               - Registered read data (1 rclk cycle latency).
//               - No reset on the array or read register so the tools can
//                 map it onto distributed RAM / block RAM.
//-----------------------------------------------------------------------------
module fifo_mem #(
  parameter int DATA_WIDTH = 8,
  parameter int AW         = 4            // address width, DEPTH = 2**AW
) (
  // Write port (wclk domain)
  input  logic                  wclk,
  input  logic                  wen,
  input  logic [AW-1:0]         waddr,
  input  logic [DATA_WIDTH-1:0] wdata,

  // Read port (rclk domain)
  input  logic                  rclk,
  input  logic                  ren,
  input  logic [AW-1:0]         raddr,
  output logic [DATA_WIDTH-1:0] rdata
);

  logic [DATA_WIDTH-1:0] mem [2**AW];

  always_ff @(posedge wclk) begin
    if (wen) mem[waddr] <= wdata;
  end

  always_ff @(posedge rclk) begin
    if (ren) rdata <= mem[raddr];
  end

endmodule
