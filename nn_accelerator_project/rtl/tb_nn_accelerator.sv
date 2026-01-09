//==============================================================================
// File: tb_nn_accelerator.sv
// Description: Testbench for neural network accelerator
//==============================================================================

`timescale 1ns / 1ps

module tb_nn_accelerator;

    import nn_pkg::*;
    
    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    parameter CLK_PERIOD = 20;  // 50 MHz
    
    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    
    // AXI-Lite
    logic [5:0]  s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [5:0]  s_axi_araddr;
    logic [2:0]  s_axi_arprot;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;
    
    // AXI-Stream Slave
    logic [31:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;
    
    // AXI-Stream Master
    logic [31:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;
    
    // Interrupt
    logic        interrupt;
    
    //--------------------------------------------------------------------------
    // DUT Instance
    //--------------------------------------------------------------------------
    nn_accelerator #(
        .C_S_AXI_ADDR_WIDTH(6),
        .C_S_AXI_DATA_WIDTH(32),
        .C_AXIS_DATA_WIDTH(32)
    ) dut (
        .aclk           (clk),
        .aresetn        (rst_n),
        
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),
        
        .interrupt      (interrupt)
    );
    
    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //--------------------------------------------------------------------------
    // AXI-Lite Write Task
    //--------------------------------------------------------------------------
    task axi_write(input [5:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            
            // Wait for write to complete
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            @(posedge clk);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // AXI-Lite Read Task
    //--------------------------------------------------------------------------
    task axi_read(input [5:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;
            
            // Wait for read to complete
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_arvalid <= 1'b0;
            @(posedge clk);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // AXI-Stream Send Task
    //--------------------------------------------------------------------------
    task axis_send(input [15:0] data, input last);
        begin
            s_axis_tdata  <= {16'd0, data};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= last;
            
            wait(s_axis_tready);
            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Test Stimulus
    //--------------------------------------------------------------------------
    logic [31:0] read_data;
    integer i;
    
    initial begin
        $display("========================================");
        $display("NN Accelerator Testbench");
        $display("========================================");
        
        // Initialize signals
        rst_n         = 1'b0;
        s_axi_awaddr  = '0;
        s_axi_awprot  = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = '0;
        s_axi_arprot  = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);
        
        $display("Reset complete");
        
        // Configure network topology
        $display("Configuring network...");
        axi_write(6'h08, 32'd784);  // NUM_IN
        axi_write(6'h0C, 32'd16);   // NUM_H1
        axi_write(6'h10, 32'd16);   // NUM_H2
        axi_write(6'h14, 32'd10);   // NUM_OUT
        
        // Read back configuration
        axi_read(6'h08, read_data);
        $display("  NUM_IN  = %d", read_data);
        axi_read(6'h0C, read_data);
        $display("  NUM_H1  = %d", read_data);
        axi_read(6'h10, read_data);
        $display("  NUM_H2  = %d", read_data);
        axi_read(6'h14, read_data);
        $display("  NUM_OUT = %d", read_data);
        
        // Enable and start
        $display("Starting inference...");
        axi_write(6'h00, 32'h03);  // Enable + Start
        
        // Send test input data (784 values)
        $display("Sending input data...");
        for (i = 0; i < 784; i++) begin
            axis_send(16'h0100, (i == 783));  // Simple test pattern
        end
        
        // Wait for completion
        $display("Waiting for completion...");
        wait(interrupt);
        
        $display("Inference complete!");
        
        // Read status
        axi_read(6'h04, read_data);
        $display("Status = 0x%08X (Busy=%b, Done=%b)", 
                 read_data, read_data[0], read_data[1]);
        
        // Receive output data
        $display("Output results:");
        for (i = 0; i < 10; i++) begin
            wait(m_axis_tvalid);
            $display("  Output[%d] = 0x%04X", i, m_axis_tdata[15:0]);
            @(posedge clk);
        end
        
        // Done
        repeat(10) @(posedge clk);
        $display("========================================");
        $display("Test Complete");
        $display("========================================");
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Timeout
    //--------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
