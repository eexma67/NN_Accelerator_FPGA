`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// AXI4-Lite Wrapper for NN Accelerator
// This module provides memory-mapped register interface for control/status
//////////////////////////////////////////////////////////////////////////////////

module nn_accelerator_axi #(
    // Parameters for AXI-Lite interface
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 8,
    
    // NN Accelerator parameters
    parameter INPUT_SIZE = 784,      // 28x28 MNIST
    parameter HIDDEN_SIZE = 128,
    parameter OUTPUT_SIZE = 10,
    parameter DATA_WIDTH = 16
)(
    // AXI4-Lite Slave Interface
    input  wire                             S_AXI_ACLK,
    input  wire                             S_AXI_ARESETN,
    
    // Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]                       S_AXI_AWPROT,
    input  wire                             S_AXI_AWVALID,
    output wire                             S_AXI_AWREADY,
    
    // Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                             S_AXI_WVALID,
    output wire                             S_AXI_WREADY,
    
    // Write Response Channel
    output wire [1:0]                       S_AXI_BRESP,
    output wire                             S_AXI_BVALID,
    input  wire                             S_AXI_BREADY,
    
    // Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]                       S_AXI_ARPROT,
    input  wire                             S_AXI_ARVALID,
    output wire                             S_AXI_ARREADY,
    
    // Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]                       S_AXI_RRESP,
    output wire                             S_AXI_RVALID,
    input  wire                             S_AXI_RREADY,
    
    // Interrupt
    output wire                             interrupt
);

    //----------------------------------------------
    // Register Map
    //----------------------------------------------
    // 0x00: CONTROL    - [0]: start, [1]: reset, [31]: busy
    // 0x04: STATUS     - [7:0]: predicted digit, [31]: done
    // 0x08: INPUT_ADDR - Base address for input data
    // 0x0C: CONFIG     - Configuration register
    // 0x10-0x1F: Reserved
    //----------------------------------------------
    
    localparam ADDR_CONTROL    = 8'h00;
    localparam ADDR_STATUS     = 8'h04;
    localparam ADDR_INPUT_ADDR = 8'h08;
    localparam ADDR_CONFIG     = 8'h0C;
    
    // Internal Registers
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_control;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_status;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_input_addr;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_config;
    
    // AXI Write State Machine
    reg [1:0] axi_awstate, axi_wstate;
    reg axi_awready_reg, axi_wready_reg, axi_bvalid_reg;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr_reg;
    
    // AXI Read State Machine  
    reg [1:0] axi_arstate;
    reg axi_arready_reg, axi_rvalid_reg;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr_reg;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata_reg;
    
    // NN Accelerator signals
    wire nn_start;
    wire nn_reset;
    wire nn_busy;
    wire nn_done;
    wire [3:0] predicted_digit;
    
    assign nn_start = reg_control[0];
    assign nn_reset = reg_control[1] | ~S_AXI_ARESETN;
    
    // Update status register
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            reg_status <= 0;
        end else begin
            reg_status <= {nn_busy, 23'd0, nn_done, 3'd0, predicted_digit};
        end
    end
    
    //----------------------------------------------
    // AXI Write Logic
    //----------------------------------------------
    assign S_AXI_AWREADY = axi_awready_reg;
    assign S_AXI_WREADY  = axi_wready_reg;
    assign S_AXI_BVALID  = axi_bvalid_reg;
    assign S_AXI_BRESP   = 2'b00; // OKAY response
    
    // Write Address Channel
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            axi_awready_reg <= 1'b0;
            axi_awstate <= 2'd0;
            axi_awaddr_reg <= 0;
        end else begin
            case (axi_awstate)
                2'd0: begin // IDLE
                    axi_awready_reg <= 1'b1;
                    if (S_AXI_AWVALID && axi_awready_reg) begin
                        axi_awaddr_reg <= S_AXI_AWADDR;
                        axi_awready_reg <= 1'b0;
                        axi_awstate <= 2'd1;
                    end
                end
                2'd1: begin // Wait for write data
                    if (S_AXI_WVALID && axi_wready_reg) begin
                        axi_awstate <= 2'd0;
                    end
                end
            endcase
        end
    end
    
    // Write Data Channel
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            axi_wready_reg <= 1'b0;
            axi_wstate <= 2'd0;
            reg_control <= 0;
            reg_input_addr <= 0;
            reg_config <= 0;
        end else begin
            case (axi_wstate)
                2'd0: begin // IDLE
                    axi_wready_reg <= 1'b1;
                    if (S_AXI_WVALID && axi_wready_reg) begin
                        // Write to register based on address
                        case (axi_awaddr_reg)
                            ADDR_CONTROL:    reg_control <= S_AXI_WDATA;
                            ADDR_INPUT_ADDR: reg_input_addr <= S_AXI_WDATA;
                            ADDR_CONFIG:     reg_config <= S_AXI_WDATA;
                            default: ; // Ignore writes to other addresses
                        endcase
                        axi_wready_reg <= 1'b0;
                        axi_wstate <= 2'd1;
                    end
                end
                2'd1: begin // Send response
                    axi_wstate <= 2'd0;
                end
            endcase
        end
    end
    
    // Write Response Channel
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            axi_bvalid_reg <= 1'b0;
        end else begin
            if (~axi_bvalid_reg && axi_wstate == 2'd1) begin
                axi_bvalid_reg <= 1'b1;
            end else if (S_AXI_BREADY && axi_bvalid_reg) begin
                axi_bvalid_reg <= 1'b0;
            end
        end
    end
    
    //----------------------------------------------
    // AXI Read Logic
    //----------------------------------------------
    assign S_AXI_ARREADY = axi_arready_reg;
    assign S_AXI_RVALID  = axi_rvalid_reg;
    assign S_AXI_RDATA   = axi_rdata_reg;
    assign S_AXI_RRESP   = 2'b00; // OKAY response
    
    // Read Address Channel
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            axi_arready_reg <= 1'b0;
            axi_arstate <= 2'd0;
            axi_araddr_reg <= 0;
        end else begin
            case (axi_arstate)
                2'd0: begin // IDLE
                    axi_arready_reg <= 1'b1;
                    if (S_AXI_ARVALID && axi_arready_reg) begin
                        axi_araddr_reg <= S_AXI_ARADDR;
                        axi_arready_reg <= 1'b0;
                        axi_arstate <= 2'd1;
                    end
                end
                2'd1: begin // Read data
                    axi_arstate <= 2'd0;
                end
            endcase
        end
    end
    
    // Read Data Channel
    always @(posedge S_AXI_ACLK) begin
        if (~S_AXI_ARESETN) begin
            axi_rvalid_reg <= 1'b0;
            axi_rdata_reg <= 0;
        end else begin
            if (~axi_rvalid_reg && axi_arstate == 2'd1) begin
                axi_rvalid_reg <= 1'b1;
                // Read from register based on address
                case (axi_araddr_reg)
                    ADDR_CONTROL:    axi_rdata_reg <= reg_control;
                    ADDR_STATUS:     axi_rdata_reg <= reg_status;
                    ADDR_INPUT_ADDR: axi_rdata_reg <= reg_input_addr;
                    ADDR_CONFIG:     axi_rdata_reg <= reg_config;
                    default:         axi_rdata_reg <= 32'hDEADBEEF;
                endcase
            end else if (S_AXI_RREADY && axi_rvalid_reg) begin
                axi_rvalid_reg <= 1'b0;
            end
        end
    end
    
    //----------------------------------------------
    // Interrupt Generation
    //----------------------------------------------
    assign interrupt = nn_done;
    
    //----------------------------------------------
    // Instantiate NN Accelerator Core
    //----------------------------------------------
    nn_accelerator_core #(
        .INPUT_SIZE(INPUT_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .OUTPUT_SIZE(OUTPUT_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) nn_core (
        .clk(S_AXI_ACLK),
        .rst(nn_reset),
        .start(nn_start),
        .busy(nn_busy),
        .done(nn_done),
        .predicted_digit(predicted_digit),
        // Add your actual NN accelerator ports here
        // e.g., input data interface, weight memory interface, etc.
        .input_base_addr(reg_input_addr)
    );

endmodule
