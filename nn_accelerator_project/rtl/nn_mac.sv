//==============================================================================
// File: nn_mac.sv
// Description: Multiply-Accumulate unit for neural network computation
//
// Performs: accumulator += input * weight
// Supports bias loading and accumulator clearing
//==============================================================================

module nn_mac
    import nn_pkg::*;
(
    input  logic    clk,
    input  logic    rst_n,
    
    // Control
    input  logic    clear,          // Clear accumulator
    input  logic    enable,         // Enable MAC operation
    input  logic    load_bias,      // Load bias into accumulator
    
    // Data inputs
    input  fixed_t  input_val,      // Input activation
    input  fixed_t  weight_val,     // Weight value
    input  fixed_t  bias_val,       // Bias value
    
    // Output
    output fixed_t  result,         // Saturated result
    output accum_t  accumulator,    // Raw accumulator (for debugging)
    output logic    valid           // Result valid (one cycle after last MAC)
);

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    accum_t accum_reg;
    accum_t product;
    logic   enable_d1;
    
    //--------------------------------------------------------------------------
    // Multiply (combinational)
    //--------------------------------------------------------------------------
    assign product = fixed_mult(input_val, weight_val);
    
    //--------------------------------------------------------------------------
    // Accumulate (sequential)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_reg <= '0;
            enable_d1 <= 1'b0;
        end
        else begin
            enable_d1 <= enable;
            
            if (clear) begin
                accum_reg <= '0;
            end
            else if (load_bias) begin
                // Load bias (already in fixed-point, shift to accumulator scale)
                accum_reg <= accum_t'(bias_val) <<< FRAC_BITS;
            end
            else if (enable) begin
                // Accumulate product
                accum_reg <= accum_reg + product;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Output
    //--------------------------------------------------------------------------
    // Shift right by FRAC_BITS and saturate to 16-bit
    assign result = saturate(accum_reg >>> FRAC_BITS);
    assign accumulator = accum_reg;
    
    // Valid pulse after enable goes low
    assign valid = enable_d1 && !enable;

endmodule
