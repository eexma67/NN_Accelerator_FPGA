//==============================================================================
// File: nn_accelerator.sv
// Description: Top-level neural network accelerator with AXI interfaces
//
// Features:
//   - AXI4-Lite slave for configuration registers
//   - AXI4-Stream slave for input data
//   - AXI4-Stream master for output results
//   - Configurable network topology
//   - Interrupt on completion
//==============================================================================

module nn_accelerator
    import nn_pkg::*;
#(
    parameter int C_S_AXI_ADDR_WIDTH = 6,
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_AXIS_DATA_WIDTH  = 32
)(
    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    input  logic        aclk,
    input  logic        aresetn,
    
    //--------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Configuration Registers)
    //--------------------------------------------------------------------------
    // Write address channel
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [2:0]                    s_axi_awprot,
    input  logic                          s_axi_awvalid,
    output logic                          s_axi_awready,
    
    // Write data channel
    input  logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                    s_axi_wstrb,
    input  logic                          s_axi_wvalid,
    output logic                          s_axi_wready,
    
    // Write response channel
    output logic [1:0]                    s_axi_bresp,
    output logic                          s_axi_bvalid,
    input  logic                          s_axi_bready,
    
    // Read address channel
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [2:0]                    s_axi_arprot,
    input  logic                          s_axi_arvalid,
    output logic                          s_axi_arready,
    
    // Read data channel
    output logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                    s_axi_rresp,
    output logic                          s_axi_rvalid,
    input  logic                          s_axi_rready,
    
    //--------------------------------------------------------------------------
    // AXI4-Stream Slave Interface (Input Data)
    //--------------------------------------------------------------------------
    input  logic [C_AXIS_DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                          s_axis_tvalid,
    output logic                          s_axis_tready,
    input  logic                          s_axis_tlast,
    
    //--------------------------------------------------------------------------
    // AXI4-Stream Master Interface (Output Results)
    //--------------------------------------------------------------------------
    output logic [C_AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                          m_axis_tvalid,
    input  logic                          m_axis_tready,
    output logic                          m_axis_tlast,
    
    //--------------------------------------------------------------------------
    // Interrupt
    //--------------------------------------------------------------------------
    output logic                          interrupt
);

    //==========================================================================
    // Register Map
    //==========================================================================
    // Offset  Name           Description
    // 0x00    REG_CTRL       Control register
    //                        [0]  = Enable
    //                        [1]  = Start (auto-clear)
    //                        [2]  = Soft reset
    // 0x04    REG_STATUS     Status register (read-only)
    //                        [0]  = Busy
    //                        [1]  = Done
    //                        [7:4]= Current state
    // 0x08    REG_NUM_IN     Number of inputs (default: 784)
    // 0x0C    REG_NUM_H1     Hidden layer 1 size (default: 16)
    // 0x10    REG_NUM_H2     Hidden layer 2 size (default: 16)
    // 0x14    REG_NUM_OUT    Number of outputs (default: 10)
    //==========================================================================
    
    localparam ADDR_CTRL    = 6'h00;
    localparam ADDR_STATUS  = 6'h04;
    localparam ADDR_NUM_IN  = 6'h08;
    localparam ADDR_NUM_H1  = 6'h0C;
    localparam ADDR_NUM_H2  = 6'h10;
    localparam ADDR_NUM_OUT = 6'h14;
    
    //--------------------------------------------------------------------------
    // Registers
    //--------------------------------------------------------------------------
    logic [31:0] reg_ctrl;
    logic [31:0] reg_status;
    logic [15:0] reg_num_in;
    logic [15:0] reg_num_h1;
    logic [15:0] reg_num_h2;
    logic [15:0] reg_num_out;
    
    // Control bits
    wire nn_enable     = reg_ctrl[0];
    wire nn_start      = reg_ctrl[1];
    wire nn_soft_reset = reg_ctrl[2];
    
    // Status bits
    logic nn_busy;
    logic nn_done;
    
    //--------------------------------------------------------------------------
    // State Machine
    //--------------------------------------------------------------------------
    state_t state;
    
    //--------------------------------------------------------------------------
    // Counters
    //--------------------------------------------------------------------------
    logic [15:0] input_cnt;
    logic [15:0] weight_cnt;
    logic [15:0] neuron_cnt;
    logic [2:0]  layer_cnt;
    logic [15:0] output_cnt;
    
    //--------------------------------------------------------------------------
    // Layer size lookup
    //--------------------------------------------------------------------------
    logic [15:0] layer_sizes [0:3];
    logic [15:0] current_layer_size;
    logic [15:0] prev_layer_size;
    
    always_comb begin
        layer_sizes[0] = reg_num_in;
        layer_sizes[1] = reg_num_h1;
        layer_sizes[2] = reg_num_h2;
        layer_sizes[3] = reg_num_out;
        
        current_layer_size = layer_sizes[layer_cnt];
        prev_layer_size    = (layer_cnt == 0) ? reg_num_in : layer_sizes[layer_cnt - 1];
    end
    
    //--------------------------------------------------------------------------
    // Data Buffers
    //--------------------------------------------------------------------------
    fixed_t input_buffer  [0:MAX_LAYER_SIZE-1];
    fixed_t output_buffer [0:MAX_LAYER_SIZE-1];
    fixed_t weight_buffer [0:MAX_LAYER_SIZE-1];
    fixed_t bias_buffer   [0:63];
    
    //--------------------------------------------------------------------------
    // Neuron Signals
    //--------------------------------------------------------------------------
    logic  [NUM_PARALLEL-1:0] neuron_start;
    logic  [NUM_PARALLEL-1:0] neuron_done;
    logic  [NUM_PARALLEL-1:0] neuron_busy;
    fixed_t                   neuron_output [NUM_PARALLEL];
    logic  [NUM_PARALLEL-1:0] neuron_output_valid;
    
    // Shared signals
    fixed_t current_input;
    fixed_t current_weight [NUM_PARALLEL];
    fixed_t current_bias   [NUM_PARALLEL];
    logic   mac_enable;
    logic   load_bias;
    
    // Sigmoid LUT signals
    logic [SIGMOID_ADDR_WIDTH-1:0] sig_addr [NUM_PARALLEL];
    fixed_t                        sig_data [NUM_PARALLEL];
    logic  [NUM_PARALLEL-1:0]      sig_en;
    
    //--------------------------------------------------------------------------
    // Sigmoid LUT Instance
    //--------------------------------------------------------------------------
    sigmoid_lut u_sigmoid_lut (
        .clk    (aclk),
        .rst_n  (aresetn),
        .addr_a (sig_addr[0]),
        .en_a   (sig_en[0]),
        .data_a (sig_data[0]),
        .addr_b (sig_addr[1]),
        .en_b   (sig_en[1]),
        .data_b (sig_data[1])
    );
    
    //--------------------------------------------------------------------------
    // Neuron Instances
    //--------------------------------------------------------------------------
    genvar g;
    generate
        for (g = 0; g < NUM_PARALLEL; g++) begin : gen_neurons
            nn_neuron u_neuron (
                .clk            (aclk),
                .rst_n          (aresetn && !nn_soft_reset),
                .start          (neuron_start[g]),
                .clear          (state == S_IDLE || nn_soft_reset),
                .done           (neuron_done[g]),
                .busy           (neuron_busy[g]),
                .input_val      (current_input),
                .weight_val     (current_weight[g]),
                .bias_val       (current_bias[g]),
                .load_bias      (load_bias),
                .mac_enable     (mac_enable),
                .use_activation (1'b1),
                .sigmoid_addr   (sig_addr[g]),
                .sigmoid_data   (sig_data[g]),
                .sigmoid_en     (sig_en[g]),
                .output_val     (neuron_output[g]),
                .output_valid   (neuron_output_valid[g])
            );
        end
    endgenerate
    
    //==========================================================================
    // AXI4-Lite Write Logic
    //==========================================================================
    logic aw_en;
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_en         <= 1'b1;
            
            // Default register values
            reg_ctrl    <= 32'd0;
            reg_num_in  <= 16'd784;
            reg_num_h1  <= 16'd16;
            reg_num_h2  <= 16'd16;
            reg_num_out <= 16'd10;
        end
        else begin
            // Write address ready
            if (!s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end
            else begin
                s_axi_awready <= 1'b0;
            end
            
            // Write data ready
            if (!s_axi_wready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_wready <= 1'b1;
            end
            else begin
                s_axi_wready <= 1'b0;
            end
            
            // Write response
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end
            else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
                aw_en <= 1'b1;
            end
            
            // Register writes
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
                case (s_axi_awaddr)
                    ADDR_CTRL:    reg_ctrl    <= s_axi_wdata;
                    ADDR_NUM_IN:  reg_num_in  <= s_axi_wdata[15:0];
                    ADDR_NUM_H1:  reg_num_h1  <= s_axi_wdata[15:0];
                    ADDR_NUM_H2:  reg_num_h2  <= s_axi_wdata[15:0];
                    ADDR_NUM_OUT: reg_num_out <= s_axi_wdata[15:0];
                endcase
            end
            
            // Auto-clear start bit
            if (state != S_IDLE) begin
                reg_ctrl[1] <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // AXI4-Lite Read Logic
    //==========================================================================
    logic ar_en;
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
            ar_en         <= 1'b1;
        end
        else begin
            // Read address ready
            if (!s_axi_arready && s_axi_arvalid && ar_en) begin
                s_axi_arready <= 1'b1;
                ar_en <= 1'b0;
            end
            else begin
                s_axi_arready <= 1'b0;
            end
            
            // Read data valid
            if (s_axi_arready && s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                
                case (s_axi_araddr)
                    ADDR_CTRL:    s_axi_rdata <= reg_ctrl;
                    ADDR_STATUS:  s_axi_rdata <= {16'd0, 4'd0, state, 6'd0, nn_done, nn_busy};
                    ADDR_NUM_IN:  s_axi_rdata <= {16'd0, reg_num_in};
                    ADDR_NUM_H1:  s_axi_rdata <= {16'd0, reg_num_h1};
                    ADDR_NUM_H2:  s_axi_rdata <= {16'd0, reg_num_h2};
                    ADDR_NUM_OUT: s_axi_rdata <= {16'd0, reg_num_out};
                    default:      s_axi_rdata <= 32'd0;
                endcase
            end
            else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid <= 1'b0;
                ar_en <= 1'b1;
            end
        end
    end
    
    //==========================================================================
    // Main Control FSM
    //==========================================================================
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            nn_busy      <= 1'b0;
            nn_done      <= 1'b0;
            interrupt    <= 1'b0;
            input_cnt    <= '0;
            weight_cnt   <= '0;
            neuron_cnt   <= '0;
            layer_cnt    <= '0;
            output_cnt   <= '0;
            neuron_start <= '0;
            mac_enable   <= 1'b0;
            load_bias    <= 1'b0;
        end
        else if (nn_soft_reset) begin
            state        <= S_IDLE;
            nn_busy      <= 1'b0;
            nn_done      <= 1'b0;
            interrupt    <= 1'b0;
        end
        else begin
            // Default assignments
            neuron_start <= '0;
            mac_enable   <= 1'b0;
            load_bias    <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                S_IDLE: begin
                    nn_busy   <= 1'b0;
                    nn_done   <= 1'b0;
                    interrupt <= 1'b0;
                    
                    if (nn_enable && nn_start) begin
                        state      <= S_LOAD_IN;
                        nn_busy    <= 1'b1;
                        input_cnt  <= '0;
                        layer_cnt  <= '0;
                        neuron_cnt <= '0;
                    end
                end
                
                //--------------------------------------------------------------
                S_LOAD_IN: begin
                    // Load input data via AXI-Stream
                    if (s_axis_tvalid && s_axis_tready) begin
                        input_buffer[input_cnt] <= fixed_t'(s_axis_tdata[15:0]);
                        
                        if (s_axis_tlast || input_cnt == reg_num_in - 1) begin
                            state      <= S_LOAD_B;
                            input_cnt  <= '0;
                            layer_cnt  <= 3'd1; // Start with first hidden layer
                            neuron_cnt <= '0;
                        end
                        else begin
                            input_cnt <= input_cnt + 1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                S_LOAD_B: begin
                    // Load biases for current neuron(s)
                    if (s_axis_tvalid && s_axis_tready) begin
                        bias_buffer[neuron_cnt] <= fixed_t'(s_axis_tdata[15:0]);
                        
                        if (neuron_cnt == current_layer_size - 1) begin
                            state      <= S_LOAD_W;
                            neuron_cnt <= '0;
                            weight_cnt <= '0;
                        end
                        else begin
                            neuron_cnt <= neuron_cnt + 1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                S_LOAD_W: begin
                    // Load weights for current neuron
                    if (s_axis_tvalid && s_axis_tready) begin
                        weight_buffer[weight_cnt] <= fixed_t'(s_axis_tdata[15:0]);
                        
                        if (weight_cnt == prev_layer_size - 1) begin
                            state      <= S_COMPUTE;
                            weight_cnt <= '0;
                            input_cnt  <= '0;
                        end
                        else begin
                            weight_cnt <= weight_cnt + 1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                S_COMPUTE: begin
                    // Start neurons
                    neuron_start <= '1;
                    load_bias    <= (input_cnt == 0);
                    
                    // Feed inputs and weights
                    current_input <= input_buffer[input_cnt];
                    for (int i = 0; i < NUM_PARALLEL; i++) begin
                        current_weight[i] <= weight_buffer[input_cnt];
                        current_bias[i]   <= bias_buffer[neuron_cnt + i];
                    end
                    
                    if (input_cnt == 0) begin
                        load_bias <= 1'b1;
                    end
                    else begin
                        mac_enable <= 1'b1;
                    end
                    
                    if (input_cnt == prev_layer_size - 1) begin
                        state <= S_ACTIVATE;
                    end
                    else begin
                        input_cnt <= input_cnt + 1;
                    end
                end
                
                //--------------------------------------------------------------
                S_ACTIVATE: begin
                    // Wait for neurons to complete activation
                    if (&neuron_done) begin
                        state <= S_STORE;
                    end
                end
                
                //--------------------------------------------------------------
                S_STORE: begin
                    // Store neuron outputs
                    for (int i = 0; i < NUM_PARALLEL; i++) begin
                        if (neuron_cnt + i < current_layer_size) begin
                            output_buffer[neuron_cnt + i] <= neuron_output[i];
                        end
                    end
                    
                    neuron_cnt <= neuron_cnt + NUM_PARALLEL;
                    
                    if (neuron_cnt + NUM_PARALLEL >= current_layer_size) begin
                        state <= S_NEXT_LAYER;
                    end
                    else begin
                        state      <= S_LOAD_W;
                        weight_cnt <= '0;
                        input_cnt  <= '0;
                    end
                end
                
                //--------------------------------------------------------------
                S_NEXT_LAYER: begin
                    // Copy output to input for next layer
                    for (int i = 0; i < MAX_LAYER_SIZE; i++) begin
                        input_buffer[i] <= output_buffer[i];
                    end
                    
                    if (layer_cnt == 3) begin
                        // All layers done
                        state      <= S_OUTPUT;
                        output_cnt <= '0;
                    end
                    else begin
                        layer_cnt  <= layer_cnt + 1;
                        neuron_cnt <= '0;
                        state      <= S_LOAD_B;
                    end
                end
                
                //--------------------------------------------------------------
                S_OUTPUT: begin
                    // Send results via AXI-Stream
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (output_cnt == reg_num_out - 1) begin
                            state <= S_DONE;
                        end
                        else begin
                            output_cnt <= output_cnt + 1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                S_DONE: begin
                    nn_done   <= 1'b1;
                    interrupt <= 1'b1;
                    
                    if (!nn_enable) begin
                        state <= S_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                default: state <= S_IDLE;
                
            endcase
        end
    end
    
    //==========================================================================
    // AXI-Stream Signals
    //==========================================================================
    assign s_axis_tready = (state == S_LOAD_IN) || 
                           (state == S_LOAD_B)  || 
                           (state == S_LOAD_W);
    
    assign m_axis_tdata  = {16'd0, output_buffer[output_cnt]};
    assign m_axis_tvalid = (state == S_OUTPUT);
    assign m_axis_tlast  = (state == S_OUTPUT) && (output_cnt == reg_num_out - 1);

endmodule
