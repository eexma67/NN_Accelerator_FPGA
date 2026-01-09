/**
 * @file nn_driver.c
 * @brief Neural Network Accelerator Driver Implementation
 */

#include "nn_driver.h"
#include "sleep.h"
#include <string.h>

/*==============================================================================
 * Module Variables
 *============================================================================*/
static NN_Config g_config = {
    .base_addr = NN_BASEADDR,
    .num_inputs = NN_DEFAULT_NUM_IN,
    .num_hidden1 = NN_DEFAULT_NUM_H1,
    .num_hidden2 = NN_DEFAULT_NUM_H2,
    .num_outputs = NN_DEFAULT_NUM_OUT,
    .initialized = 0
};

/*==============================================================================
 * Function Implementations
 *============================================================================*/

int NN_Init(NN_Config *config)
{
    /* Use provided config or defaults */
    if (config != NULL) {
        memcpy(&g_config, config, sizeof(NN_Config));
    }
    
    /* Soft reset */
    NN_Reset();
    
    /* Configure network topology */
    NN_Configure(g_config.num_inputs, 
                 g_config.num_hidden1,
                 g_config.num_hidden2, 
                 g_config.num_outputs);
    
    /* Mark as initialized */
    g_config.initialized = 1;
    
    return 0;
}

void NN_Reset(void)
{
    /* Assert soft reset */
    NN_WRITE(NN_REG_CTRL, NN_CTRL_SOFT_RESET);
    usleep(10);
    
    /* De-assert soft reset */
    NN_WRITE(NN_REG_CTRL, 0);
    usleep(10);
}

void NN_Configure(u16 num_in, u16 num_h1, u16 num_h2, u16 num_out)
{
    NN_WRITE(NN_REG_NUM_IN,  num_in);
    NN_WRITE(NN_REG_NUM_H1,  num_h1);
    NN_WRITE(NN_REG_NUM_H2,  num_h2);
    NN_WRITE(NN_REG_NUM_OUT, num_out);
    
    /* Update local config */
    g_config.num_inputs  = num_in;
    g_config.num_hidden1 = num_h1;
    g_config.num_hidden2 = num_h2;
    g_config.num_outputs = num_out;
}

int NN_IsBusy(void)
{
    u32 status = NN_READ(NN_REG_STATUS);
    return (status & NN_STAT_BUSY) ? 1 : 0;
}

int NN_IsDone(void)
{
    u32 status = NN_READ(NN_REG_STATUS);
    return (status & NN_STAT_DONE) ? 1 : 0;
}

void NN_GetStatus(NN_Status *status)
{
    u32 reg = NN_READ(NN_REG_STATUS);
    
    status->busy  = (reg & NN_STAT_BUSY) ? 1 : 0;
    status->done  = (reg & NN_STAT_DONE) ? 1 : 0;
    status->state = (reg & NN_STAT_STATE_MASK) >> NN_STAT_STATE_SHIFT;
}

void NN_Start(void)
{
    u32 ctrl = NN_READ(NN_REG_CTRL);
    ctrl |= NN_CTRL_ENABLE | NN_CTRL_START;
    NN_WRITE(NN_REG_CTRL, ctrl);
}

int NN_WaitDone(u32 timeout_us)
{
    u32 elapsed = 0;
    const u32 poll_interval = 100;  /* Poll every 100 us */
    
    while (!NN_IsDone()) {
        if (timeout_us > 0 && elapsed >= timeout_us) {
            return -1;  /* Timeout */
        }
        usleep(poll_interval);
        elapsed += poll_interval;
    }
    
    return 0;
}

int NN_RunInference(const s16 *inputs, u16 num_inputs,
                    s16 *outputs, u16 num_outputs)
{
    /* Check initialization */
    if (!g_config.initialized) {
        NN_Init(NULL);
    }
    
    /* Start inference */
    NN_Start();
    
    /* Note: In a full implementation, you would:
     * 1. Send input data via AXI-Stream or DMA
     * 2. Send weights/biases if not pre-loaded
     * 3. Wait for completion
     * 4. Read output data
     *
     * This simplified version assumes data transfer
     * is handled separately.
     */
    
    /* Wait for completion (10 second timeout) */
    if (NN_WaitDone(10000000) < 0) {
        return -1;  /* Timeout */
    }
    
    /* In full implementation, read outputs here */
    
    return 0;
}

int NN_Classify(const s16 *outputs, u16 num_outputs)
{
    int max_idx = 0;
    s16 max_val = outputs[0];
    
    for (u16 i = 1; i < num_outputs; i++) {
        if (outputs[i] > max_val) {
            max_val = outputs[i];
            max_idx = i;
        }
    }
    
    return max_idx;
}

float NN_GetConfidence(const s16 *outputs, u16 num_outputs, int class_idx)
{
    /* Convert fixed-point output to float */
    float value = FIXED_TO_FLOAT(outputs[class_idx]);
    
    /* Output is already sigmoid-activated, so it's in [0, 1] range */
    /* But we can normalize across all outputs for better interpretation */
    
    float sum = 0.0f;
    for (u16 i = 0; i < num_outputs; i++) {
        sum += FIXED_TO_FLOAT(outputs[i]);
    }
    
    if (sum > 0.0f) {
        return value / sum;
    }
    
    return value;
}
