#==============================================================================
# File: create_project.tcl
# Description: Vivado TCL script to create NN Accelerator project
#
# Usage:
#   vivado -mode batch -source create_project.tcl
#   OR
#   In Vivado TCL console: source create_project.tcl
#==============================================================================

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
set project_name "nn_accelerator"
set project_dir  "./vivado_project"
set part_number  "xc7z020clg400-1"  ;# ZYBO/ZedBoard - change for your board

# Source directories (relative to this script)
set script_dir [file dirname [info script]]
set rtl_dir    [file join $script_dir "../rtl"]
set mem_dir    [file join $script_dir "../mem"]
set xdc_dir    [file join $script_dir "../constraints"]

#------------------------------------------------------------------------------
# Create Project
#------------------------------------------------------------------------------
puts "=============================================="
puts " Creating Vivado Project: $project_name"
puts "=============================================="

# Create project
create_project $project_name $project_dir -part $part_number -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

#------------------------------------------------------------------------------
# Add RTL Sources
#------------------------------------------------------------------------------
puts "\nAdding RTL sources..."

set rtl_files [list \
    [file join $rtl_dir "nn_pkg.sv"] \
    [file join $rtl_dir "sigmoid_lut.sv"] \
    [file join $rtl_dir "nn_mac.sv"] \
    [file join $rtl_dir "nn_neuron.sv"] \
    [file join $rtl_dir "nn_accelerator.sv"] \
]

foreach f $rtl_files {
    if {[file exists $f]} {
        add_files -norecurse $f
        puts "  Added: $f"
    } else {
        puts "  WARNING: File not found: $f"
    }
}

#------------------------------------------------------------------------------
# Add Memory Initialization Files
#------------------------------------------------------------------------------
puts "\nAdding memory files..."

set mem_files [list \
    [file join $mem_dir "weights.mem"] \
    [file join $mem_dir "biases.mem"] \
    [file join $mem_dir "sigmoid_lut.mem"] \
]

foreach f $mem_files {
    if {[file exists $f]} {
        add_files -norecurse $f
        set_property file_type {Memory Initialization Files} [get_files $f]
        puts "  Added: $f"
    } else {
        puts "  WARNING: Memory file not found: $f"
        puts "  Run Python training first: python python/train.py"
    }
}

#------------------------------------------------------------------------------
# Add Constraints
#------------------------------------------------------------------------------
puts "\nAdding constraints..."

set xdc_file [file join $xdc_dir "constraints.xdc"]
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "  Added: $xdc_file"
} else {
    puts "  WARNING: Constraints file not found: $xdc_file"
}

#------------------------------------------------------------------------------
# Create Block Design
#------------------------------------------------------------------------------
puts "\nCreating block design..."

create_bd_design "system"

# Add Zynq Processing System
puts "  Adding Zynq PS..."
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Apply board preset if available
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

# Configure Zynq PS
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
] [get_bd_cells processing_system7_0]

# Add NN Accelerator (RTL module)
puts "  Adding NN Accelerator..."
create_bd_cell -type module -reference nn_accelerator nn_accelerator_0

# Add AXI Interconnect
puts "  Adding AXI Interconnect..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {1}] [get_bd_cells axi_interconnect_0]

# Add AXI DMA (optional, for AXI-Stream data)
puts "  Adding AXI DMA..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s2mm_burst_size {16} \
] [get_bd_cells axi_dma_0]

# Connect clocks
puts "  Connecting clocks..."
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins nn_accelerator_0/aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]

# Connect resets
puts "  Connecting resets..."
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins nn_accelerator_0/aresetn]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_dma_0/axi_resetn]

# Connect AXI interfaces
puts "  Connecting AXI interfaces..."
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
    [get_bd_intf_pins nn_accelerator_0/s_axi]

# Connect DMA to NN Accelerator AXI-Stream
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins nn_accelerator_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins nn_accelerator_0/m_axis] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# Connect interrupt
puts "  Connecting interrupt..."
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {2}] [get_bd_cells xlconcat_0]
connect_bd_net [get_bd_pins nn_accelerator_0/interrupt] \
    [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] \
    [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins xlconcat_0/dout] \
    [get_bd_pins processing_system7_0/IRQ_F2P]

# Assign addresses
puts "  Assigning addresses..."
assign_bd_address

# Validate design
puts "\nValidating block design..."
validate_bd_design

# Save block design
save_bd_design

#------------------------------------------------------------------------------
# Create HDL Wrapper
#------------------------------------------------------------------------------
puts "\nCreating HDL wrapper..."
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $project_dir/$project_name.gen/sources_1/bd/system/hdl/system_wrapper.v
set_property top system_wrapper [current_fileset]

#------------------------------------------------------------------------------
# Generate Output Products
#------------------------------------------------------------------------------
puts "\nGenerating block design output products..."
generate_target all [get_files $project_dir/$project_name.srcs/sources_1/bd/system/system.bd]

#------------------------------------------------------------------------------
# Synthesis Settings
#------------------------------------------------------------------------------
puts "\nConfiguring synthesis..."
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

#------------------------------------------------------------------------------
# Implementation Settings
#------------------------------------------------------------------------------
puts "\nConfiguring implementation..."
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]

#------------------------------------------------------------------------------
# Done
#------------------------------------------------------------------------------
puts "\n=============================================="
puts " Project created successfully!"
puts "=============================================="
puts "\nNext steps:"
puts "  1. Open project in Vivado GUI"
puts "  2. Run Synthesis"
puts "  3. Run Implementation"
puts "  4. Generate Bitstream"
puts "  5. Export Hardware (File -> Export -> Export Hardware)"
puts "  6. Launch Vitis IDE"
puts ""
puts "Project location: $project_dir/$project_name.xpr"
puts "=============================================="
