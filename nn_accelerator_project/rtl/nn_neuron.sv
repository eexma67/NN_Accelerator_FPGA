//==============================================================================
// File: nn_neuron.sv
// Description: Single neuron with MAC and sigmoid activation
//
// Operation: output = sigmoid(sum(input[i] * weight[i]) + bias)
//==============================================================================

module nn_neuron
    import nn_pkg::*;
(
    input  logic    clk,
    input  logic    rst_n,
    
    //--------------------------------------------------------------------------
    // Control Interface
    //--------------------------------------------------------------------------
    input  logic    start,          // Start computation
    input  logic    clear,          // Clear state
    output logic    done,           // Computation complete
    output logic    busy,           // Neuron is busy
    
    //--------------------------------------------------------------------------
    // Data Interface
    //--------------------------------------------------------------------------
    input  fixed_t  input_val,      // Input value
    input  fixed_t  weight_val,     // Weight value
    input  fixed_t  bias_val,       // Bias value
    input  logic    load_bias,      // Load bias signal
    input  logic    mac_enable,     // MAC enable signal
    input  logic    use_activation, // Apply sigmoid activation
    
    //--------------------------------------------------------------------------
    // Sigmoid LUT Interface
    //--------------------------------------------------------------------------
    output logic [SIGMOID_ADDR_WIDTH-1:0] sigmoid_addr,
    input  fixed_t                        sigmoid_data,
    output logic                          sigmoid_en,
    
    //--------------------------------------------------------------------------
    // Output
    //--------------------------------------------------------------------------
    output fixed_t  output_val,
    output logic    output_valid
);

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    neuron_state_t state, next_state;
    fixed_t mac_result;
    fixed_t pre_activation;
    logic [2:0] wait_cnt;
    
    //--------------------------------------------------------------------------
    // MAC Unit Instance
    //--------------------------------------------------------------------------
    nn_mac u_mac (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (clear),
        .enable     (mac_enable),
        .load_bias  (load_bias),
        .input_val  (input_val),
        .weight_val (weight_val),
        .bias_val   (bias_val),
        .result     (mac_result),
        .accumulator(),
        .valid      ()
    );
    
    //--------------------------------------------------------------------------
    // Sigmoid Address Calculation
    // Map fixed-point value from [-8, +8] to LUT index [0, 1023]
    //--------------------------------------------------------------------------
    always_comb begin
        // Add 8.0 to shift range from [-8,+8] to [0,16]
        logic signed [DATA_WIDTH+4:0] shifted;
        shifted = $signed({pre_activation, 4'b0}) + (21'sd8 <<< (FRAC_BITS + 4));
        
        // Extract address bits (divide by 16/1024 = 1/64)
        if (shifted < 0) begin
            sigmoid_addr = '0;
        end
        else if (shifted >= (21'sd16 <<< (FRAC_BITS + 4))) begin
            sigmoid_addr = {SIGMOID_ADDR_WIDTH{1'b1}};
        end
        else begin
            // Take bits [FRAC_BITS+3 : FRAC_BITS-6] to get 10-bit address
            sigmoid_addr = shifted[FRAC_BITS+3:FRAC_BITS-6];
        end
    end
    
    //--------------------------------------------------------------------------
    // State Machine
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= N_IDLE;
            done           <= 1'b0;
            busy           <= 1'b0;
            output_valid   <= 1'b0;
            output_val     <= '0;
            pre_activation <= '0;
            wait_cnt       <= '0;
            sigmoid_en     <= 1'b0;
        end
        else begin
            // Default values
            done         <= 1'b0;
            output_valid <= 1'b0;
            sigmoid_en   <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                N_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        state <= N_MAC;
                        busy  <= 1'b1;
                    end
                end
                
                //--------------------------------------------------------------
                N_MAC: begin
                    // Wait for MAC operations (driven externally)
                    // Transition triggered by external signal
                    if (!mac_enable && !load_bias) begin
                        state    <= N_WAIT;
                        wait_cnt <= 3'd2; // Wait for pipeline
                    end
                end
                
                //--------------------------------------------------------------
                N_WAIT: begin
                    if (wait_cnt == 0) begin
                        pre_activation <= mac_result;
                        state          <= N_ACTIVATE;
                        sigmoid_en     <= 1'b1;
                    end
                    else begin
                        wait_cnt <= wait_cnt - 1;
                    end
                end
                
                //--------------------------------------------------------------
                N_ACTIVATE: begin
                    // Wait for sigmoid LUT read (1 cycle)
                    sigmoid_en <= 1'b1;
                    state      <= N_OUTPUT;
                end
                
                //--------------------------------------------------------------
                N_OUTPUT: begin
                    if (use_activation) begin
                        output_val <= sigmoid_data;
                    end
                    else begin
                        output_val <= pre_activation;
                    end
                    output_valid <= 1'b1;
                    done         <= 1'b1;
                    state        <= N_IDLE;
                end
                
                //--------------------------------------------------------------
                default: state <= N_IDLE;
            endcase
            
            // Clear handling
            if (clear) begin
                state <= N_IDLE;
                busy  <= 1'b0;
            end
        end
    end

endmodule
