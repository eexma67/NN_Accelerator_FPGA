#==============================================================================
# File: create_project.tcl
# Description: Vivado TCL script to create NN Accelerator project
#
# Usage:
#   1. Open Vivado
#   2. In TCL Console: source create_project.tcl
#   Or from command line: vivado -mode batch -source create_project.tcl
#==============================================================================

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
set project_name "nn_accelerator_zynq"
set project_dir  "./vivado_project"
set part_name    "xc7z020clg400-1"  ;# ZYBO / ZedBoard / Cora Z7-10

# Get script directory
set script_dir [file dirname [info script]]
set rtl_dir    [file normalize "$script_dir/../rtl"]
set mem_dir    [file normalize "$script_dir/../rtl/mem"]
set constr_dir [file normalize "$script_dir/../constraints"]

#------------------------------------------------------------------------------
# Create Project
#------------------------------------------------------------------------------
puts "============================================"
puts "Creating NN Accelerator Vivado Project"
puts "============================================"

# Create project
create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]

#------------------------------------------------------------------------------
# Add Source Files
#------------------------------------------------------------------------------
puts "Adding RTL source files..."

# Add SystemVerilog files
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/*.sv]

# Exclude testbench from synthesis
set_property file_type {SystemVerilog} [get_files *.sv]
set_property used_in_synthesis false [get_files *tb_*.sv]

# Add memory initialization files
if {[file exists $mem_dir]} {
    add_files -fileset sources_1 [glob -nocomplain $mem_dir/*.mem]
}

#------------------------------------------------------------------------------
# Add Constraints
#------------------------------------------------------------------------------
puts "Adding constraint files..."

if {[file exists "$constr_dir/constraints.xdc"]} {
    add_files -fileset constrs_1 "$constr_dir/constraints.xdc"
}

#------------------------------------------------------------------------------
# Add Simulation Files
#------------------------------------------------------------------------------
puts "Adding simulation files..."

# Add testbench to simulation fileset
add_files -fileset sim_1 [glob -nocomplain $rtl_dir/tb_*.sv]
set_property top tb_nn_accelerator [get_filesets sim_1]

#------------------------------------------------------------------------------
# Set Top Module
#------------------------------------------------------------------------------
set_property top nn_accelerator [current_fileset]
update_compile_order -fileset sources_1

#------------------------------------------------------------------------------
# Create Block Design (Optional)
#------------------------------------------------------------------------------
puts "Creating block design..."

# Create block design
create_bd_design "system"

# Add Zynq PS
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Apply board preset (if available)
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} \
    [get_bd_cells processing_system7_0]

# Configure Zynq PS
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
] [get_bd_cells processing_system7_0]

# Add AXI Interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_interconnect_0]

# Add NN Accelerator (as RTL module reference)
# Note: For IP Integrator, you need to package the design as IP first
# This creates a placeholder - package the IP manually

puts ""
puts "============================================"
puts "Block Design Notes:"
puts "============================================"
puts "1. Package nn_accelerator as IP:"
puts "   Tools -> Create and Package New IP"
puts ""
puts "2. Add the packaged IP to block design"
puts ""
puts "3. Connect:"
puts "   - s_axi to AXI Interconnect"
puts "   - s_axis/m_axis to DMA or direct"
puts "   - interrupt to IRQ_F2P"
puts "============================================"

# Save and validate
save_bd_design
validate_bd_design

# Create wrapper
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $project_dir/$project_name.gen/sources_1/bd/system/hdl/system_wrapper.v

#------------------------------------------------------------------------------
# Synthesis Settings
#------------------------------------------------------------------------------
puts "Configuring synthesis settings..."

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION one_hot [get_runs synth_1]

#------------------------------------------------------------------------------
# Implementation Settings
#------------------------------------------------------------------------------
puts "Configuring implementation settings..."

set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]

#------------------------------------------------------------------------------
# Done
#------------------------------------------------------------------------------
puts ""
puts "============================================"
puts "Project created successfully!"
puts "============================================"
puts ""
puts "Project location: $project_dir/$project_name.xpr"
puts ""
puts "Next steps:"
puts "1. Open project in Vivado GUI"
puts "2. Package nn_accelerator as IP"
puts "3. Complete block design connections"
puts "4. Run synthesis and implementation"
puts "5. Generate bitstream"
puts "6. Export hardware to Vitis"
puts ""
