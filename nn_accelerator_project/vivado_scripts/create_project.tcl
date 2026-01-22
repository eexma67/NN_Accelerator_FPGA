# ============================================
# Corrected NN Accelerator Zynq Project Script
# ============================================

set project_name "nn_accelerator_zynq"
set project_dir  "./vivado_project"
set part_name    "xc7z020clg400-1"  

set script_dir [file dirname [info script]]
set rtl_dir    [file normalize "$script_dir/../rtl"]
set mem_dir    [file normalize "$script_dir/../rtl/mem"]
set constr_dir [file normalize "$script_dir/../constraints"]

puts "============================================"
puts "Creating NN Accelerator Vivado Project"
puts "============================================"

# Create project
create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]

# Add RTL source files
puts "Adding RTL source files..."
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/*.sv]
set_property file_type {SystemVerilog} [get_files *.sv]
set_property used_in_synthesis false [get_files *tb_*.sv]

# Add memory initialization files if they exist
if {[file exists $mem_dir]} {
    add_files -fileset sources_1 [glob -nocomplain $mem_dir/*.mem]
}

# Add constraint files
puts "Adding constraint files..."
if {[file exists "$constr_dir/constraints.xdc"]} {
    add_files -fileset constrs_1 "$constr_dir/constraints.xdc"
}

# Add simulation files
puts "Adding simulation files..."
add_files -fileset sim_1 [glob -nocomplain $rtl_dir/tb_*.sv]
set_property top tb_nn_accelerator [get_filesets sim_1]
set_property top nn_accelerator [current_fileset]

update_compile_order -fileset sources_1

puts "Creating block design..."
create_bd_design "system"

# ============================================
# Create Processing System
# ============================================
puts "Creating PS7 block..."
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Apply board automation if available (otherwise manual config)
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} \
    [get_bd_cells processing_system7_0]

# Configure PS7
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
] [get_bd_cells processing_system7_0]

# ============================================
# Create AXI Interconnect for Control
# ============================================
puts "Creating AXI Interconnect..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
] [get_bd_cells axi_interconnect_0]

# ============================================
# Create Clock and Reset Infrastructure
# ============================================
puts "Setting up clocks and resets..."

# Create Processor System Reset for FCLK_CLK0 (100 MHz)
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M

# Connect PS7 FCLK_CLK0 to reset module
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins rst_ps7_0_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_100M/ext_reset_in]

# Connect clocks to AXI Interconnect
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/M00_ACLK]

# Connect clocks to PS7 AXI interfaces
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

# Connect resets to AXI Interconnect
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN]

# ============================================
# Connect AXI Interfaces
# ============================================
puts "Connecting AXI interfaces..."

# Connect PS7 M_AXI_GP0 to Interconnect S00_AXI
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                    [get_bd_intf_pins axi_interconnect_0/S00_AXI]

# ============================================
# Create AXI BRAM Controller (placeholder for NN accelerator)
# ============================================
puts "Creating placeholder AXI BRAM Controller..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0
set_property -dict [list \
    CONFIG.SINGLE_PORT_BRAM {1} \
    CONFIG.DATA_WIDTH {32} \
] [get_bd_cells axi_bram_ctrl_0]

# Create Block Memory Generator
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_0
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_32bit_Address {false} \
] [get_bd_cells blk_mem_gen_0]

# Connect BRAM Controller to BRAM
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] \
                    [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTB] \
                    [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTB]

# Connect AXI Interconnect M00 to BRAM Controller
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]

# Connect clock and reset to BRAM Controller
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_bram_ctrl_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn]

# ============================================
# Address Assignment
# ============================================
puts "Assigning addresses..."
assign_bd_address [get_bd_addr_segs {axi_bram_ctrl_0/S_AXI/Mem0}]
set_property offset 0x40000000 [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_0_Mem0}]
set_property range 64K [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_0_Mem0}]

# ============================================
# Create HDL Wrapper
# ============================================
puts "Validating and saving design..."
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "Creating HDL wrapper..."
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $project_dir/$project_name.gen/sources_1/bd/system/hdl/system_wrapper.v
set_property top system_wrapper [current_fileset]

puts ""
puts "============================================"
puts "Project Created Successfully!"
puts "============================================"
puts ""
puts "NEXT STEPS:"
puts "1. Package your nn_accelerator RTL as AXI IP:"
puts "   - Tools -> Create and Package New IP"
puts "   - Select 'Create a new AXI4 peripheral'"
puts "   - Add your nn_accelerator logic to the IP"
puts ""
puts "2. Add the custom IP to block design:"
puts "   - Replace axi_bram_ctrl_0 with your NN accelerator IP"
puts "   - Or add it as additional M01 on interconnect"
puts ""
puts "3. Connect your NN accelerator:"
puts "   - S_AXI to M01_AXI (control/status registers)"
puts "   - S_AXI_HP0 for high-bandwidth data transfer"
puts "   - Optional: Add interrupt signal to IRQ_F2P"
puts ""
puts "4. Synthesis and Implementation:"
puts "   - Run Synthesis: launch_runs synth_1 -jobs 4"
puts "   - Run Implementation: launch_runs impl_1 -jobs 4"
puts "   - Generate Bitstream: launch_runs impl_1 -to_step write_bitstream"
puts ""
puts "============================================"

update_compile_order -fileset sources_1
