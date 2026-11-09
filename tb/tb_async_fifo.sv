//-----------------------------------------------------------------------------
// Testbench   : tb_async_fifo
// Description : Self-checking testbench for async_fifo.
//               - Two independent clocks whose periods are changed between
//                 test phases (fast-write/slow-read, slow-write/fast-read,
//                 near-equal drifting clocks)
//               - Reference model (SystemVerilog queue) as scoreboard:
//                 checks data order, error pulses, and that the
//                 pessimistic fill levels never under/over-report
//               - Directed corner-case tests + concurrent random traffic
//               - Functional coverage per clock domain
//               Run with +SEED=<n> to change the random seed.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_async_fifo;

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int DATA_WIDTH = 8;
  localparam int DEPTH      = 16;
  localparam int AW         = $clog2(DEPTH);

  //---------------------------------------------------------------------------
  // Clocks (periods can be changed while the FIFO is idle)
  //---------------------------------------------------------------------------
  real  wclk_period = 10.0;
  real  rclk_period = 23.0;
  logic wclk = 1'b0;
  logic rclk = 1'b0;

  always #(wclk_period / 2.0) wclk = ~wclk;
  always #(rclk_period / 2.0) rclk = ~rclk;

  //---------------------------------------------------------------------------
  // Signals
  //---------------------------------------------------------------------------
  logic                  wrst_n, rrst_n;
  logic                  wr_en, rd_en;
  logic [DATA_WIDTH-1:0] wr_data, rd_data;
  logic                  full, empty, overflow, underflow;
  logic [AW:0]           wr_count, rd_count;

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  async_fifo #(
    .DATA_WIDTH (DATA_WIDTH),
    .DEPTH      (DEPTH)
  ) dut (
    .wclk      (wclk),
    .wrst_n    (wrst_n),
    .wr_en     (wr_en),
    .wr_data   (wr_data),
    .full      (full),
    .wr_count  (wr_count),
    .overflow  (overflow),
    .rclk      (rclk),
    .rrst_n    (rrst_n),
    .rd_en     (rd_en),
    .rd_data   (rd_data),
    .empty     (empty),
    .rd_count  (rd_count),
    .underflow (underflow)
  );

  //---------------------------------------------------------------------------
  // Scoreboard / reference model
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] model[$];
  logic [DATA_WIDTH-1:0] exp_data;
  logic                  chk_pending;
  logic                  exp_ovf, exp_udf;

  int unsigned n_writes, n_reads, n_ovf, n_udf, n_checks, n_errors;

  function automatic void report_error(string msg);
    n_errors++;
    $error("[%0t] %s", $time, msg);
  endfunction

  // Write-side monitor (samples at wclk edge; driver changes on negedge)
  always @(posedge wclk) begin
    if (!wrst_n) begin
      model.delete();
      exp_ovf <= 1'b0;
    end else begin
      exp_ovf <= wr_en && full;
      if (wr_en && !full) begin
        model.push_back(wr_data);
        n_writes++;
        if (model.size() > DEPTH)
          report_error("OVERFLOW: DUT accepted a write while truly full");
      end
      if (wr_en && full) n_ovf++;
    end
  end

  // Read-side monitor
  always @(posedge rclk) begin
    if (!rrst_n) begin
      chk_pending <= 1'b0;
      exp_udf     <= 1'b0;
    end else begin
      chk_pending <= 1'b0;
      exp_udf     <= rd_en && empty;
      if (rd_en && !empty) begin
        if (model.size() == 0) begin
          report_error("UNDERFLOW: DUT accepted a read but nothing was written");
        end else begin
          exp_data    <= model.pop_front();
          chk_pending <= 1'b1;
          n_reads++;
        end
      end
      if (rd_en && empty) n_udf++;
    end
  end

  // Write-side checker (mid wclk cycle)
  always @(negedge wclk) begin
    if (wrst_n && rrst_n) begin
      n_checks++;
      if (overflow !== exp_ovf)
        report_error("OVERFLOW pulse wrong");
      if ($isunknown({full, wr_count, overflow}))
        report_error("X/Z on write-side outputs");
      // Writer's view must never claim more free space than really exists
      if (wr_count < model.size())
        report_error($sformatf("wr_count %0d below true level %0d", wr_count, model.size()));
    end
  end

  // Read-side checker (mid rclk cycle)
  always @(negedge rclk) begin
    if (wrst_n && rrst_n) begin
      n_checks++;
      if (chk_pending && rd_data !== exp_data)
        report_error($sformatf("DATA MISMATCH: got 0x%0h, expected 0x%0h", rd_data, exp_data));
      if (underflow !== exp_udf)
        report_error("UNDERFLOW pulse wrong");
      if ($isunknown({empty, rd_count, underflow}))
        report_error("X/Z on read-side outputs");
      // Reader's view must never claim more data than really exists
      if (rd_count > model.size())
        report_error($sformatf("rd_count %0d above true level %0d", rd_count, model.size()));
    end
  end

  //---------------------------------------------------------------------------
  // Functional coverage (one covergroup per clock domain)
  //---------------------------------------------------------------------------
  covergroup cg_write @(posedge wclk iff (wrst_n && rrst_n));
    cp_wr_en: coverpoint wr_en;
    cp_full:  coverpoint full;
    x_wr_full: cross cp_wr_en, cp_full;          // includes write-while-full
    cp_wr_level: coverpoint wr_count {
      bins empty = {0};
      bins low   = {[1 : DEPTH/2 - 1]};
      bins high  = {[DEPTH/2 : DEPTH - 1]};
      bins full  = {DEPTH};
    }
  endgroup

  covergroup cg_read @(posedge rclk iff (wrst_n && rrst_n));
    cp_rd_en:  coverpoint rd_en;
    cp_empty:  coverpoint empty;
    x_rd_empty: cross cp_rd_en, cp_empty;        // includes read-while-empty
    cp_rd_level: coverpoint rd_count {
      bins empty = {0};
      bins low   = {[1 : DEPTH/2 - 1]};
      bins high  = {[DEPTH/2 : DEPTH - 1]};
      bins full  = {DEPTH};
    }
  endgroup

  cg_write cg_w = new();
  cg_read  cg_r = new();

  //---------------------------------------------------------------------------
  // Driver tasks
  //---------------------------------------------------------------------------
  task automatic wr_cycle(input bit en);
    @(negedge wclk);
    wr_en   = en;
    wr_data = $urandom();
  endtask

  task automatic rd_cycle(input bit en);
    @(negedge rclk);
    rd_en = en;
  endtask

  task automatic apply_reset();
    wr_en  = 1'b0;
    rd_en  = 1'b0;
    wrst_n = 1'b0;
    rrst_n = 1'b0;
    // Release each reset synchronously to its own clock
    fork
      begin repeat (3) @(posedge wclk); @(negedge wclk); wrst_n = 1'b1; end
      begin repeat (3) @(posedge rclk); @(negedge rclk); rrst_n = 1'b1; end
    join
    repeat (3) @(negedge wclk);
    repeat (3) @(negedge rclk);
  endtask

  // Concurrent random traffic on both sides
  task automatic random_traffic(input int wr_cycles, input int rd_cycles,
                                input int wr_pct,    input int rd_pct);
    fork
      begin
        repeat (wr_cycles) wr_cycle($urandom_range(99) < wr_pct);
        wr_cycle(0);
      end
      begin
        repeat (rd_cycles) rd_cycle($urandom_range(99) < rd_pct);
        rd_cycle(0);
      end
    join
  endtask

  // Read everything that is left, then let both sides settle
  task automatic drain(input string name);
    int guard = 0;
    @(negedge wclk) wr_en = 1'b0;
    while (model.size() != 0 && guard < 5000) begin
      @(negedge rclk);
      rd_en = !empty;
      guard++;
    end
    @(negedge rclk) rd_en = 1'b0;
    repeat (5) @(negedge wclk);
    repeat (5) @(negedge rclk);
    if (model.size() != 0 || !empty || full || wr_count != 0 || rd_count != 0)
      report_error($sformatf("%s: FIFO not cleanly drained (model=%0d empty=%0b full=%0b wr_count=%0d rd_count=%0d)",
                             name, model.size(), empty, full, wr_count, rd_count));
    else
      $display("[%0t] PASS: %s", $time, name);
  endtask

  task automatic set_clocks(input real wper, input real rper);
    wclk_period = wper;
    rclk_period = rper;
    repeat (2) @(negedge wclk);
    repeat (2) @(negedge rclk);
    $display("[%0t] Clocks: wclk = %0.1f ns, rclk = %0.1f ns", $time, wper, rper);
  endtask

  //---------------------------------------------------------------------------
  // Test sequence
  //---------------------------------------------------------------------------
  int unsigned seed;
  int unsigned start_cnt;
  int unsigned n_flushed;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_async_fifo);

    if ($value$plusargs("SEED=%d", seed)) void'($urandom(seed));
    $display("Running async_fifo test, DEPTH=%0d, DATA_WIDTH=%0d", DEPTH, DATA_WIDTH);

    wrst_n  = 1'b0;
    rrst_n  = 1'b0;
    wr_en   = 1'b0;
    rd_en   = 1'b0;
    wr_data = '0;
    apply_reset();

    // T1: reset state
    if (full !== 1'b0 || empty !== 1'b1)
      report_error("T1: wrong flags after reset");
    else
      $display("[%0t] PASS: T1 reset state", $time);

    // T2: fill until full (no reads) -> exactly DEPTH writes accepted
    start_cnt = n_writes;
    while (!full) wr_cycle(1);
    repeat (3) wr_cycle(1);                 // writes while full -> overflow
    wr_cycle(0);
    if (n_writes - start_cnt != DEPTH || !full)
      report_error($sformatf("T2: accepted %0d writes before full (expected %0d)",
                             n_writes - start_cnt, DEPTH));
    else
      $display("[%0t] PASS: T2 fill to full (%0d writes) + overflow attempts", $time, DEPTH);

    // T3: let the write pointer cross over, then drain until empty
    repeat (5) rd_cycle(0);
    if (rd_count !== DEPTH)
      report_error($sformatf("T3: reader sees %0d entries (expected %0d)", rd_count, DEPTH));
    start_cnt = n_reads;
    while (!empty) rd_cycle(1);
    repeat (3) rd_cycle(1);                 // reads while empty -> underflow
    rd_cycle(0);
    repeat (5) wr_cycle(0);                 // let the read pointer cross over
    if (n_reads - start_cnt != DEPTH || !empty || full || wr_count != 0)
      report_error($sformatf("T3: read %0d entries (expected %0d)", n_reads - start_cnt, DEPTH));
    else
      $display("[%0t] PASS: T3 drain to empty (%0d reads) + underflow attempts", $time, DEPTH);

    // T4: fast write / slow read -> FIFO spends time full
    set_clocks(10.0, 23.0);
    random_traffic(3000, 1300, 70, 80);
    drain("T4 fast write (100 MHz) / slow read (~43 MHz)");

    // T5: slow write / fast read -> FIFO spends time empty
    set_clocks(27.0, 8.0);
    random_traffic(1200, 4000, 80, 60);
    drain("T5 slow write (~37 MHz) / fast read (125 MHz)");

    // T6: near-equal clocks with drifting phase
    set_clocks(10.0, 10.7);
    random_traffic(3000, 2800, 50, 50);
    drain("T6 near-equal drifting clocks (100 / ~93 MHz)");

    // T7: reset in the middle of traffic, with data still inside the FIFO
    // (writer runs longer than reader so the FIFO is full at the reset)
    random_traffic(400, 300, 70, 30);
    n_flushed = model.size();
    if (n_flushed == 0)
      report_error("T7: FIFO was empty before reset, test not meaningful");
    else
      $display("[%0t] T7: applying reset with %0d entries inside the FIFO", $time, n_flushed);
    apply_reset();
    if (full !== 1'b0 || empty !== 1'b1 || wr_count != 0 || rd_count != 0)
      report_error("T7: wrong state after reset during traffic");
    else
      $display("[%0t] PASS: T7 reset during traffic", $time);
    random_traffic(1000, 1000, 50, 50);
    drain("T7 traffic after reset");

    //-------------------------------------------------------------------------
    // Summary
    //-------------------------------------------------------------------------
    $display("");
    $display("================ ASYNC FIFO TEST SUMMARY ================");
    $display(" Writes accepted         : %0d", n_writes);
    $display(" Reads accepted          : %0d", n_reads);
    $display(" Entries flushed by reset: %0d", n_flushed);
    $display(" Overflow attempts       : %0d", n_ovf);
    $display(" Underflow attempts      : %0d", n_udf);
    $display(" Cycle checks            : %0d", n_checks);
    $display(" Write-domain coverage   : %0.2f %%", cg_w.get_coverage());
    $display(" Read-domain coverage    : %0.2f %%", cg_r.get_coverage());
    $display(" Errors                  : %0d", n_errors);
    if (n_errors == 0 && model.size() == 0)
      $display(" RESULT                  : *** TEST PASSED ***");
    else
      $display(" RESULT                  : *** TEST FAILED ***");
    $display("=========================================================");
    $finish;
  end

  // Watchdog (2 ms of simulated time)
  initial begin
    #2_000_000;
    $fatal(1, "Simulation timeout");
  end

endmodule
