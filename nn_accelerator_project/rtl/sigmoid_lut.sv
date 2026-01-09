//==============================================================================
// File: sigmoid_lut.sv
// Description: Dual-port ROM for sigmoid activation function
//
// The sigmoid function is approximated using a 1024-entry lookup table.
// Input range: -8.0 to +8.0 (mapped to indices 0-1023)
// Output range: 0.0 to 1.0
//==============================================================================

module sigmoid_lut
    import nn_pkg::*;
(
    input  logic                          clk,
    input  logic                          rst_n,
    
    // Port A
    input  logic [SIGMOID_ADDR_WIDTH-1:0] addr_a,
    input  logic                          en_a,
    output fixed_t                        data_a,
    
    // Port B
    input  logic [SIGMOID_ADDR_WIDTH-1:0] addr_b,
    input  logic                          en_b,
    output fixed_t                        data_b
);

    //--------------------------------------------------------------------------
    // ROM Storage
    //--------------------------------------------------------------------------
    (* rom_style = "block" *)
    logic [DATA_WIDTH-1:0] rom [0:SIGMOID_LUT_SIZE-1];
    
    //--------------------------------------------------------------------------
    // Initialize from file
    //--------------------------------------------------------------------------
    initial begin
        $readmemh("sigmoid_lut.mem", rom);
    end
    
    //--------------------------------------------------------------------------
    // Port A Read (registered output)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (en_a) begin
            data_a <= rom[addr_a];
        end
    end
    
    //--------------------------------------------------------------------------
    // Port B Read (registered output)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (en_b) begin
            data_b <= rom[addr_b];
        end
    end

endmodule
