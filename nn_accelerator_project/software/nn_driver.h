/**
 * @file nn_driver.h
 * @brief Neural Network Accelerator Driver Header
 *
 * This driver provides functions to control the NN accelerator IP
 * on Xilinx Zynq FPGA.
 */

#ifndef NN_DRIVER_H
#define NN_DRIVER_H

#include "xil_types.h"
#include "xil_io.h"

/*==============================================================================
 * Base Address
 * NOTE: Update this based on your Vivado Address Editor settings
 *============================================================================*/
#ifndef NN_BASEADDR
#define NN_BASEADDR     0x43C00000
#endif

/*==============================================================================
 * Register Offsets
 *============================================================================*/
#define NN_REG_CTRL     0x00    /* Control register */
#define NN_REG_STATUS   0x04    /* Status register (read-only) */
#define NN_REG_NUM_IN   0x08    /* Number of inputs */
#define NN_REG_NUM_H1   0x0C    /* Hidden layer 1 size */
#define NN_REG_NUM_H2   0x10    /* Hidden layer 2 size */
#define NN_REG_NUM_OUT  0x14    /* Number of outputs */

/*==============================================================================
 * Control Register Bits
 *============================================================================*/
#define NN_CTRL_ENABLE      (1 << 0)    /* Enable accelerator */
#define NN_CTRL_START       (1 << 1)    /* Start inference (auto-clear) */
#define NN_CTRL_SOFT_RESET  (1 << 2)    /* Soft reset */

/*==============================================================================
 * Status Register Bits
 *============================================================================*/
#define NN_STAT_BUSY        (1 << 0)    /* Accelerator busy */
#define NN_STAT_DONE        (1 << 1)    /* Inference complete */
#define NN_STAT_STATE_MASK  (0xF << 4)  /* Current state */
#define NN_STAT_STATE_SHIFT 4

/*==============================================================================
 * Fixed-Point Conversion (S.4.11 format)
 *============================================================================*/
#define NN_FRAC_BITS    11
#define NN_SCALE        (1 << NN_FRAC_BITS)

#define FLOAT_TO_FIXED(x)   ((s16)((x) * NN_SCALE))
#define FIXED_TO_FLOAT(x)   ((float)(x) / NN_SCALE)

/*==============================================================================
 * Network Configuration
 *============================================================================*/
#define NN_DEFAULT_NUM_IN   784
#define NN_DEFAULT_NUM_H1   16
#define NN_DEFAULT_NUM_H2   16
#define NN_DEFAULT_NUM_OUT  10

/*==============================================================================
 * Data Types
 *============================================================================*/
typedef struct {
    u32 base_addr;
    u16 num_inputs;
    u16 num_hidden1;
    u16 num_hidden2;
    u16 num_outputs;
    u8  initialized;
} NN_Config;

typedef struct {
    u8  busy;
    u8  done;
    u8  state;
} NN_Status;

/*==============================================================================
 * Function Prototypes
 *============================================================================*/

/**
 * @brief Initialize the NN accelerator
 * @param config Pointer to configuration structure (can be NULL for defaults)
 * @return 0 on success, -1 on failure
 */
int NN_Init(NN_Config *config);

/**
 * @brief Reset the NN accelerator
 */
void NN_Reset(void);

/**
 * @brief Configure network topology
 * @param num_in Number of input nodes
 * @param num_h1 Hidden layer 1 size
 * @param num_h2 Hidden layer 2 size
 * @param num_out Number of output nodes
 */
void NN_Configure(u16 num_in, u16 num_h1, u16 num_h2, u16 num_out);

/**
 * @brief Check if accelerator is busy
 * @return 1 if busy, 0 if idle
 */
int NN_IsBusy(void);

/**
 * @brief Check if inference is complete
 * @return 1 if done, 0 otherwise
 */
int NN_IsDone(void);

/**
 * @brief Get accelerator status
 * @param status Pointer to status structure
 */
void NN_GetStatus(NN_Status *status);

/**
 * @brief Start inference
 */
void NN_Start(void);

/**
 * @brief Wait for inference to complete
 * @param timeout_us Timeout in microseconds (0 = infinite)
 * @return 0 on success, -1 on timeout
 */
int NN_WaitDone(u32 timeout_us);

/**
 * @brief Run complete inference
 * @param inputs Input data array (fixed-point)
 * @param num_inputs Number of inputs
 * @param outputs Output data array (fixed-point)
 * @param num_outputs Number of outputs
 * @return 0 on success, -1 on failure
 */
int NN_RunInference(const s16 *inputs, u16 num_inputs,
                    s16 *outputs, u16 num_outputs);

/**
 * @brief Classify output (find max index)
 * @param outputs Output array
 * @param num_outputs Number of outputs
 * @return Index of maximum value
 */
int NN_Classify(const s16 *outputs, u16 num_outputs);

/**
 * @brief Get confidence of classification
 * @param outputs Output array
 * @param num_outputs Number of outputs
 * @param class_idx Index of class
 * @return Confidence as float (0.0 to 1.0)
 */
float NN_GetConfidence(const s16 *outputs, u16 num_outputs, int class_idx);

/*==============================================================================
 * Low-Level Register Access Macros
 *============================================================================*/
#define NN_READ(offset)         Xil_In32(NN_BASEADDR + (offset))
#define NN_WRITE(offset, val)   Xil_Out32(NN_BASEADDR + (offset), (val))

#endif /* NN_DRIVER_H */
