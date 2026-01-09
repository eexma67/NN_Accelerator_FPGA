#==============================================================================
# File: constraints.xdc
# Description: Timing and I/O constraints for NN Accelerator on Zynq
#==============================================================================

#------------------------------------------------------------------------------
# Clock Constraints
#------------------------------------------------------------------------------
# FCLK_CLK0 from Zynq PS (50 MHz default)
create_clock -period 20.000 -name clk_fpga_0 \
    [get_pins -hierarchical *processing_system7_0/FCLK_CLK0]

# Alternative: If using 100 MHz clock
# create_clock -period 10.000 -name clk_fpga_0 \
#     [get_pins -hierarchical *processing_system7_0/FCLK_CLK0]

#------------------------------------------------------------------------------
# Clock Uncertainty
#------------------------------------------------------------------------------
set_clock_uncertainty 0.500 [get_clocks clk_fpga_0]

#------------------------------------------------------------------------------
# False Paths
#------------------------------------------------------------------------------
# Async reset
set_false_path -from [get_ports *reset*] -to [all_registers]

# CDC paths (if any)
# set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]

#------------------------------------------------------------------------------
# Input Delays
#------------------------------------------------------------------------------
# AXI-Stream input
set_input_delay -clock clk_fpga_0 -max 2.0 [get_ports s_axis_*]
set_input_delay -clock clk_fpga_0 -min 0.5 [get_ports s_axis_*]

#------------------------------------------------------------------------------
# Output Delays
#------------------------------------------------------------------------------
# AXI-Stream output
set_output_delay -clock clk_fpga_0 -max 2.0 [get_ports m_axis_*]
set_output_delay -clock clk_fpga_0 -min 0.5 [get_ports m_axis_*]

# Interrupt
set_output_delay -clock clk_fpga_0 -max 2.0 [get_ports interrupt]
set_output_delay -clock clk_fpga_0 -min 0.5 [get_ports interrupt]

#------------------------------------------------------------------------------
# Max Delay Constraints
#------------------------------------------------------------------------------
# Limit combinational path delays
set_max_delay 15.0 -from [all_registers] -to [all_registers]

#------------------------------------------------------------------------------
# Physical Constraints (Board-Specific)
#------------------------------------------------------------------------------
# Uncomment and modify for your specific board (ZYBO, ZedBoard, etc.)

# ZYBO Board - LED indicators (optional debug)
# set_property PACKAGE_PIN M14 [get_ports {led[0]}]
# set_property PACKAGE_PIN M15 [get_ports {led[1]}]
# set_property PACKAGE_PIN G14 [get_ports {led[2]}]
# set_property PACKAGE_PIN D18 [get_ports {led[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
