# Neural Network Hardware Accelerator for Zynq FPGA

A complete implementation of a Multi-Layer Perceptron (MLP) neural network accelerator for MNIST digit recognition on Xilinx Zynq FPGA.

## Features

- **Network Architecture**: 784 → 16 → 16 → 10 (configurable)
- **Fixed-Point**: S.4.11 format (16-bit signed)
- **Interfaces**: AXI4-Lite (config), AXI4-Stream (data)
- **Parallel Processing**: 2 neurons compute simultaneously
- **Target Platform**: Zynq-7000 (ZYBO, ZedBoard, etc.)

## Directory Structure

```
nn_accelerator_project/
├── python/                 # Training and export scripts
│   ├── network.py          # Neural network class
│   └── train.py            # Training script
├── rtl/                    # SystemVerilog source files
│   ├── nn_pkg.sv           # Package with types/parameters
│   ├── sigmoid_lut.sv      # Sigmoid lookup table
│   ├── nn_mac.sv           # Multiply-accumulate unit
│   ├── nn_neuron.sv        # Single neuron module
│   ├── nn_accelerator.sv   # Top-level accelerator
│   ├── tb_nn_accelerator.sv # Testbench
│   └── mem/                # Memory initialization files
│       ├── nn_model_weights.mem
│       ├── nn_model_biases.mem
│       └── sigmoid_lut.mem
├── constraints/            # Timing constraints
│   └── constraints.xdc
├── software/               # Vitis software
│   ├── nn_driver.h         # Driver header
│   ├── nn_driver.c         # Driver implementation
│   ├── main.c              # Demo application
│   └── test_images.h       # Test data
├── vivado_scripts/         # TCL automation scripts
│   └── create_project.tcl
└── README.md
```

## Quick Start

### Step 1: Train the Neural Network (Python)

```bash
cd python
pip install numpy tensorflow
python train.py
```

This will:
- Load MNIST dataset
- Train the network for 30 epochs
- Export weights/biases to `rtl/mem/`
- Generate sigmoid LUT and test images

### Step 2: Create Vivado Project

**Option A: Using TCL Script**
```bash
cd vivado_scripts
vivado -mode batch -source create_project.tcl
```

**Option B: Manual Creation**
1. Open Vivado
2. Create new project (RTL)
3. Add all `.sv` files from `rtl/`
4. Add `.mem` files from `rtl/mem/`
5. Add `constraints.xdc`
6. Select your Zynq part (e.g., xc7z020clg400-1)

### Step 3: Package as IP

1. Tools → Create and Package New IP
2. Select "Package your current project"
3. Configure AXI interfaces
4. Package IP

### Step 4: Create Block Design

1. Create Block Design named "system"
2. Add ZYNQ7 Processing System
3. Run Block Automation
4. Configure Zynq PS:
   - Enable M_AXI_GP0
   - Enable S_AXI_HP0 (optional for DMA)
   - Enable FCLK_CLK0 (50MHz)
   - Enable IRQ_F2P
5. Add your NN Accelerator IP
6. Add AXI Interconnect
7. Connect all interfaces
8. Validate Design

### Step 5: Generate Bitstream

1. Create HDL Wrapper
2. Run Synthesis
3. Run Implementation
4. Generate Bitstream
5. Export Hardware (include bitstream)

### Step 6: Create Vitis Application

1. Launch Vitis IDE
2. Create Application Project
3. Select exported XSA file
4. Add software files from `software/`
5. Build project

### Step 7: Run on Hardware

1. Connect FPGA board
2. Program device
3. Run application
4. View results on serial terminal (115200 baud)

## Register Map

| Offset | Name       | R/W | Description                           |
|--------|------------|-----|---------------------------------------|
| 0x00   | CTRL       | R/W | [2]=Reset, [1]=Start, [0]=Enable      |
| 0x04   | STATUS     | R   | [7:4]=State, [1]=Done, [0]=Busy       |
| 0x08   | NUM_IN     | R/W | Number of inputs (default: 784)       |
| 0x0C   | NUM_H1     | R/W | Hidden layer 1 size (default: 16)     |
| 0x10   | NUM_H2     | R/W | Hidden layer 2 size (default: 16)     |
| 0x14   | NUM_OUT    | R/W | Number of outputs (default: 10)       |

## Fixed-Point Format

**S.4.11** - 16-bit signed fixed-point:
- 1 sign bit
- 4 integer bits
- 11 fractional bits
- Range: -16.0 to +15.9995
- Resolution: ~0.0005

**Conversion:**
```c
// Float to Fixed
s16 fixed = (s16)(float_val * 2048);

// Fixed to Float
float float_val = (float)fixed / 2048.0f;
```

## Resource Utilization (Zynq-7020)

| Resource | Used    | Available | Utilization |
|----------|---------|-----------|-------------|
| LUT      | ~12,000 | 53,200    | ~23%        |
| FF       | ~8,000  | 106,400   | ~8%         |
| BRAM     | ~45     | 140       | ~32%        |
| DSP      | ~8      | 220       | ~4%         |

## Performance

- Clock Frequency: 50-100 MHz
- Inference Latency: ~15,000 cycles (~300 µs @ 50MHz)
- Throughput: ~3,000 inferences/second
- Power: ~0.5W (PL fabric only)

## Simulation

Run testbench in Vivado:
1. Set `tb_nn_accelerator` as top module in sim_1 fileset
2. Run Behavioral Simulation
3. Observe waveforms

## Customization

### Changing Network Size
1. Modify `train.py`: `nn = NeuralNetwork([784, 32, 32, 10])`
2. Re-train and export
3. Update register values in software

### Increasing Parallelism
1. Modify `nn_pkg.sv`: `NUM_PARALLEL = 4`
2. Update neuron instantiation in `nn_accelerator.sv`
3. Add more sigmoid LUT ports

### Different Activation Functions
1. Modify `sigmoid_lut.sv` or add new LUT
2. Update Python export function
3. Regenerate `.mem` file

## Troubleshooting

**Timing Failures:**
- Reduce clock frequency
- Enable physical optimization
- Check critical paths in timing report

**Incorrect Results:**
- Verify memory files are loaded correctly
- Check fixed-point conversion
- Use ILA to debug AXI transactions

**DMA Issues:**
- Ensure cache coherency (Xil_DCacheFlush)
- Check AXI-Stream handshaking
- Verify buffer addresses are aligned

## License

This project is provided for educational purposes.

## References

- Xilinx Zynq-7000 TRM (UG585)
- Vivado Design Suite User Guide (UG892)
- Vitis Unified Software Platform (UG1393)
- AXI Reference Guide (UG1037)
