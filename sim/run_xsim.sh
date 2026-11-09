#!/bin/sh
# Vivado simulator. Usage (from the sim/ folder):  sh run_xsim.sh
xvlog -sv ../rtl/sync_2ff.sv ../rtl/fifo_mem.sv ../rtl/wptr_full.sv ../rtl/rptr_empty.sv \
          ../rtl/async_fifo.sv ../sva/async_fifo_sva.sv ../tb/tb_async_fifo.sv
xelab -debug typical tb_async_fifo -s async_fifo_sim
xsim async_fifo_sim -runall
