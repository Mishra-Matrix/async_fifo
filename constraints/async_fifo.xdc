## Clocks for out-of-context synthesis of async_fifo
## wclk = 100 MHz, rclk = 80 MHz (unrelated clocks)
create_clock -period 10.000 -name wclk [get_ports wclk]
create_clock -period 12.500 -name rclk [get_ports rclk]

## Clock domain crossings.
## Only Gray-code pointers (into 2-flop synchronizers) and the memory read path
## cross between the clocks. Instead of ignoring these paths with a false path,
## bound their delay so all bits of a Gray pointer arrive within one clock
## period of each other (keeps the "one bit changes at a time" guarantee).
set_max_delay -datapath_only -from [get_clocks wclk] -to [get_clocks rclk] 10.000
set_max_delay -datapath_only -from [get_clocks rclk] -to [get_clocks wclk] 10.000
