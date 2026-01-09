//==============================================================================
// File: nn_pkg.sv
// Description: Package containing types and parameters for NN accelerator
//==============================================================================

package nn_pkg;

    //--------------------------------------------------------------------------
    // Fixed-Point Format: S.4.11 (16 bits total)
    //   - 1 sign bit
    //   - 4 integer bits
    //   - 11 fractional bits
    //   - Range: -16.0 to +15.9995
    //   - Resolution: 1/2048 ≈ 0.000488
    //--------------------------------------------------------------------------
    parameter int DATA_WIDTH = 16;
    parameter int FRAC_BITS  = 11;
    parameter int INT_BITS   = 4;
    
    //--------------------------------------------------------------------------
    // Network Parameters
    //--------------------------------------------------------------------------
    parameter int MAX_LAYER_SIZE    = 784;   // Maximum neurons in a layer
    parameter int NUM_PARALLEL      = 2;     // Parallel compute units
    parameter int MAX_LAYERS        = 4;     // Maximum number of layers
    
    //--------------------------------------------------------------------------
    // Memory Parameters
    //--------------------------------------------------------------------------
    parameter int WEIGHT_MEM_DEPTH  = 16384; // Total weight storage
    parameter int BIAS_MEM_DEPTH    = 64;    // Total bias storage
    parameter int SIGMOID_LUT_SIZE  = 1024;  // Sigmoid LUT entries
    parameter int SIGMOID_ADDR_WIDTH = 10;   // log2(1024)
    
    //--------------------------------------------------------------------------
    // Data Types
    //--------------------------------------------------------------------------
    typedef logic signed [DATA_WIDTH-1:0]     fixed_t;    // Fixed-point data
    typedef logic signed [2*DATA_WIDTH-1:0]   accum_t;    // Accumulator (32-bit)
    typedef logic [SIGMOID_ADDR_WIDTH-1:0]    sig_addr_t; // Sigmoid address
    
    //--------------------------------------------------------------------------
    // FSM States
    //--------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE       = 4'd0,
        S_LOAD_CFG   = 4'd1,
        S_LOAD_IN    = 4'd2,
        S_LOAD_W     = 4'd3,
        S_LOAD_B     = 4'd4,
        S_COMPUTE    = 4'd5,
        S_ACTIVATE   = 4'd6,
        S_STORE      = 4'd7,
        S_NEXT_LAYER = 4'd8,
        S_OUTPUT     = 4'd9,
        S_DONE       = 4'd10
    } state_t;
    
    //--------------------------------------------------------------------------
    // Neuron States
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] {
        N_IDLE       = 3'd0,
        N_LOAD_BIAS  = 3'd1,
        N_MAC        = 3'd2,
        N_WAIT       = 3'd3,
        N_ACTIVATE   = 3'd4,
        N_OUTPUT     = 3'd5
    } neuron_state_t;
    
    //--------------------------------------------------------------------------
    // Functions
    //--------------------------------------------------------------------------
    
    // Saturate 32-bit accumulator to 16-bit fixed-point
    function automatic fixed_t saturate(accum_t value);
        if (value > 32'sd32767)
            return 16'sd32767;
        else if (value < -32'sd32768)
            return -16'sd32768;
        else
            return fixed_t'(value);
    endfunction
    
    // Fixed-point multiply with proper scaling
    function automatic accum_t fixed_mult(fixed_t a, fixed_t b);
        return accum_t'(a) * accum_t'(b);
    endfunction

endpackage
