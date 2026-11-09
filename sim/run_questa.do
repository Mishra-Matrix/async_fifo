# Usage (from the sim/ folder):  vsim -c -do run_questa.do
vlib work
vlog -sv -mfcu -timescale 1ns/1ps +acc \
  ../rtl/sync_2ff.sv ../rtl/fifo_mem.sv ../rtl/wptr_full.sv ../rtl/rptr_empty.sv \
  ../rtl/async_fifo.sv ../sva/async_fifo_sva.sv ../tb/tb_async_fifo.sv
vsim -assertdebug work.tb_async_fifo
run -all
assertion report -verbose
coverage report -cvg -details
quit -f
