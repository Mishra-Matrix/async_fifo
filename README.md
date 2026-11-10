# Asynchronous (Dual-Clock) FIFO with CDC and SystemVerilog Assertions

A parameterized asynchronous FIFO in SystemVerilog that safely passes data
between two **unrelated clock domains**. Clock domain crossing (CDC) is handled
with **Gray-code pointers** and **2-flop synchronizers** (Cummings-style
architecture). It is verified with a self-checking testbench running three
different clock ratios, a reference-model scoreboard, per-domain functional
coverage and 22 SVA properties attached through `bind`.

## Features

- Independent write clock (`wclk`) and read clock (`rclk`) with separate resets
- Parameterized `DATA_WIDTH` and `DEPTH` (power of 2, >= 4)
- Gray-code pointers + 2-flop synchronizers for CDC (`ASYNC_REG` attribute for Vivado)
- Registered `full` / `empty`, computed from next-state pointers (no extra latency)
- Fill level visible on each side: `wr_count` (writer's view) and `rd_count` (reader's view)
- `overflow` / `underflow` pulses for illegal accesses (safely ignored)
- Registered read data (1 `rclk` latency); memory has no reset, so it maps to FPGA RAM
- CDC timing constraints (`set_max_delay -datapath_only`) instead of blanket false paths

## Block Diagram

```
   WRITE CLOCK DOMAIN (wclk)                      READ CLOCK DOMAIN (rclk)

 wr_en ─►┌───────────────┐  wr_data  ┌───────────┐  rd_data  ┌───────────────┐◄─ rd_en
         │   wptr_full   │──────────►│ fifo_mem  │──────────►│  rptr_empty   │
 full ◄──│ bin + Gray ptr│  waddr    │ dual-port │  raddr    │ bin + Gray ptr│──► empty
         │   full logic  │──────────►│  memory   │◄──────────│  empty logic  │
         └──────┬────────┘           └───────────┘           └───────┬───────┘
                │ wptr (Gray)                                rptr (Gray) │
                │          ┌──────────────────────┐                     │
                └─────────►│ sync_2ff (into rclk) │── rq2_wptr ────────►│
                           └──────────────────────┘                     │
                ◄── wq2_rptr ┌──────────────────────┐                   │
                             │ sync_2ff (into wclk) │◄──────────────────┘
                             └──────────────────────┘
```

## File Structure

```
async_fifo/
├── rtl/
│   ├── async_fifo.sv      # Top level
│   ├── fifo_mem.sv        # Dual-port memory
│   ├── sync_2ff.sv        # 2-flop synchronizer
│   ├── wptr_full.sv       # Write pointer + full flag (wclk)
│   └── rptr_empty.sv      # Read pointer + empty flag (rclk)
├── sva/async_fifo_sva.sv  # Assertions + bind
├── tb/tb_async_fifo.sv    # Self-checking testbench
├── constraints/async_fifo.xdc  # Clocks + CDC constraints for Vivado
├── sim/run_questa.do      # Questa/ModelSim script
├── sim/run_xsim.sh        # Vivado xsim script
└── README.md
```

## Interface

| Signal      | Dir | Domain | Width         | Description                                        |
|-------------|-----|--------|---------------|----------------------------------------------------|
| `wclk`      | in  | write  | 1             | Write clock                                        |
| `wrst_n`    | in  | write  | 1             | Async active-low reset (write side)                |
| `wr_en`     | in  | write  | 1             | Write request                                      |
| `wr_data`   | in  | write  | DATA_WIDTH    | Write data                                         |
| `full`      | out | write  | 1             | No free space (may be pessimistic, never optimistic) |
| `wr_count`  | out | write  | log2(DEPTH)+1 | Fill level seen by writer (>= true level)          |
| `overflow`  | out | write  | 1             | 1-cycle pulse: write attempted while full          |
| `rclk`      | in  | read   | 1             | Read clock                                         |
| `rrst_n`    | in  | read   | 1             | Async active-low reset (read side)                 |
| `rd_en`     | in  | read   | 1             | Read request                                       |
| `rd_data`   | out | read   | DATA_WIDTH    | Read data, valid 1 `rclk` after an accepted read   |
| `empty`     | out | read   | 1             | No data (may be pessimistic, never optimistic)     |
| `rd_count`  | out | read   | log2(DEPTH)+1 | Fill level seen by reader (<= true level)          |
| `underflow` | out | read   | 1             | 1-cycle pulse: read attempted while empty          |

## Design Notes

- **Pointers:** read and write pointers are one bit wider than the address. The
  binary pointer addresses the memory; a Gray-coded copy crosses to the other
  domain so only one bit changes per increment.
- **Synchronizers:** each Gray pointer passes through a two-flop synchronizer
  (`ASYNC_REG`), giving the first stage a full destination-clock period to
  resolve metastability.
- **Full / empty:** empty is computed in the read domain (next read pointer equals
  the synchronized write pointer); full in the write domain (next write pointer
  equals the synchronized read pointer with its two MSBs inverted). Both flags
  are registered.
- **Flag latency:** each side sees the other pointer about two cycles late, so
  `full` / `empty` can clear a few cycles after space or data is available. This
  costs throughput, not correctness; `wr_count` / `rd_count` are conservative in
  the same way.
- **Depth:** must be a power of 2 so the Gray sequence wraps with a single-bit change.
- **Reset:** `wrst_n` and `rrst_n` are asserted together and released synchronously
  to their own clocks.
- **CDC constraints:** `set_max_delay -datapath_only` limits the pointer and memory
  crossings to one clock period, keeping Gray-code bit skew below a cycle.

## Verification

### Testbench (`tb/tb_async_fifo.sv`)

- **Scoreboard:** a SystemVerilog queue models the FIFO. Every read is checked
  for correct data and order. The checkers also confirm that `wr_count` never
  under-reports and `rd_count` never over-reports the real fill level.
- **Two independent clocks**, with the clock ratio changed between phases.

| Test | Scenario                                                              |
|------|-----------------------------------------------------------------------|
| T1   | Reset state                                                           |
| T2   | Fill to full with no reads: exactly DEPTH writes accepted, then overflow attempts |
| T3   | Reader sees all DEPTH entries, drains to empty, then underflow attempts |
| T4   | Random traffic, fast write (100 MHz) / slow read (~43 MHz)            |
| T5   | Random traffic, slow write (~37 MHz) / fast read (125 MHz)            |
| T6   | Random traffic, near-equal clocks with drifting phase (100 / ~93 MHz) |
| T7   | Reset while the FIFO holds data (checked non-empty), then more traffic |

- **Functional coverage:** one covergroup per clock domain (request × flag,
  and fill-level bins empty / low / high / full).
- **Seed control:** `+SEED=<n>`.

### Assertions (`sva/async_fifo_sva.sv`)

| Category                 | Properties checked                                                  |
|--------------------------|---------------------------------------------------------------------|
| Reset                    | Pointers zero, `full`=0, `empty`=1, no error pulses during reset    |
| Gray-code correctness    | Each Gray pointer changes at most one bit per clock                 |
| Pointer behaviour        | Pointers advance only on accepted operations, hold when full/empty  |
| Overflow / underflow     | Pulses set exactly when an illegal access is attempted              |
| Fill levels              | `wr_count` / `rd_count` never exceed DEPTH                          |
| X-checks                 | No X/Z on outputs, or on `rd_data` after a read                     |
| **Cross-domain safety**  | Using the real pointers: no write is accepted when truly full, no read when truly empty |
| Cover properties         | full, write-when-full, full released, read-when-empty, empty released, reader sees full |

## How to Run

Simulation (Questa / ModelSim):

    cd sim
    vsim -c -do run_questa.do

Verified with Questa 2025.2.

Synthesis: Vivado, out-of-context mode, using the files in `rtl/` and
`constraints/async_fifo.xdc`.

## Results

| Metric                         | Value |
|--------------------------------|-------|
| Simulator                      | Questa 2025.2 (EDA Playground) |
| Clock ratios tested            | 3 (fast write, fast read, near-equal drifting) |
| Writes / reads checked         | 4,045 / 4,029 (16 flushed by mid-traffic reset) |
| Scoreboard errors              | 0 |
| Assertion failures             | 0 (22 assertions, 6 cover properties) |
| Functional coverage            | 100 % write domain / 100 % read domain |
| FPGA part                      | xc7a100tcsg324-1 (Arty A7-100T) |
| Synthesis tool                 | Vivado (post-synthesis, out-of-context) |
| Slice LUTs / FFs               | 48 / 50 |
| Timing (wclk 10 ns, rclk 12.5 ns) | WNS +7.195 ns, WHS +0.164 ns, all constraints met |
| Report CDC                     | 18 crossing endpoints, all Safe (0 unsafe, 0 missing ASYNC_REG) |

![Waveform](docs/waveform_fill_full_drain.png)
![Utilization](docs/vivado_utilization.png)
![Timing](docs/vivado_timing.png)
![Report CDC](docs/vivado_cdc.png)

Full simulation log: [sim/sim_log.txt](sim/sim_log.txt)

## Reference

C. E. Cummings, *"Simulation and Synthesis Techniques for Asynchronous FIFO
Design"*, SNUG 2002.
