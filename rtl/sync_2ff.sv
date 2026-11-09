//-----------------------------------------------------------------------------
// Module      : sync_2ff
// Description : Two-flip-flop synchronizer for crossing a signal into the
//               clock domain of `clk`.
//               - First flop may go metastable; it gets a full clock period
//                 to resolve before the second flop samples it.
//               - Only safe for single-bit signals or multi-bit buses where
//                 at most ONE bit changes at a time (e.g. Gray-code pointers).
//               - ASYNC_REG tells Vivado to place both flops close together
//                 (better MTBF) and to treat them as a synchronizer.
//-----------------------------------------------------------------------------
module sync_2ff #(
  parameter int WIDTH = 1
) (
  input  logic             clk,
  input  logic             rst_n,     // async active-low reset (destination domain)
  input  logic [WIDTH-1:0] d,         // signal from the other clock domain
  output logic [WIDTH-1:0] q          // synchronized signal
);

  (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_ff1;
  (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_ff2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync_ff1 <= '0;
      sync_ff2 <= '0;
    end else begin
      sync_ff1 <= d;
      sync_ff2 <= sync_ff1;
    end
  end

  assign q = sync_ff2;

endmodule
