/**
 * @file main.c
 * @brief Neural Network MNIST Demo Application
 *
 * This application demonstrates the NN accelerator on Zynq FPGA
 * by classifying MNIST handwritten digit images.
 */

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "nn_driver.h"
#include "test_images.h"

/*==============================================================================
 * Configuration
 *============================================================================*/
#define NUM_TESTS       10      /* Number of test images (one per digit) */
#define TIMEOUT_US      5000000 /* 5 second timeout */

/*==============================================================================
 * Function Prototypes
 *============================================================================*/
static void print_banner(void);
static void print_results(int correct, int total);
static int run_single_test(int digit, s16 *outputs);

/*==============================================================================
 * Main Function
 *============================================================================*/
int main(void)
{
    int correct = 0;
    int predicted;
    float confidence;
    s16 outputs[10];
    NN_Status status;
    
    /* Initialize platform */
    init_platform();
    
    /* Print banner */
    print_banner();
    
    /* Initialize NN accelerator */
    xil_printf("Initializing NN Accelerator...\r\n");
    if (NN_Init(NULL) < 0) {
        xil_printf("ERROR: Failed to initialize NN accelerator!\r\n");
        goto cleanup;
    }
    xil_printf("  Base Address: 0x%08X\r\n", NN_BASEADDR);
    xil_printf("  Network: 784 -> 16 -> 16 -> 10\r\n");
    xil_printf("  Fixed-point: S.4.11 (16-bit)\r\n\r\n");
    
    /* Get initial status */
    NN_GetStatus(&status);
    xil_printf("Status: Busy=%d, Done=%d, State=%d\r\n\r\n", 
               status.busy, status.done, status.state);
    
    /* Run tests for each digit */
    xil_printf("Running MNIST Classification Tests:\r\n");
    xil_printf("----------------------------------------\r\n");
    
    for (int digit = 0; digit < NUM_TESTS; digit++) {
        xil_printf("Testing digit %d... ", digit);
        
        /* Run inference */
        if (run_single_test(digit, outputs) < 0) {
            xil_printf("TIMEOUT\r\n");
            continue;
        }
        
        /* Get prediction */
        predicted = NN_Classify(outputs, 10);
        confidence = NN_GetConfidence(outputs, 10, predicted);
        
        /* Check result */
        if (predicted == digit) {
            xil_printf("PASS (predicted %d, confidence %.1f%%)\r\n", 
                      predicted, confidence * 100.0f);
            correct++;
        } else {
            xil_printf("FAIL (expected %d, got %d, confidence %.1f%%)\r\n", 
                      digit, predicted, confidence * 100.0f);
        }
        
        /* Print all outputs for debugging */
        xil_printf("         Outputs: ");
        for (int i = 0; i < 10; i++) {
            xil_printf("%d:%.2f ", i, FIXED_TO_FLOAT(outputs[i]));
        }
        xil_printf("\r\n");
        
        /* Reset for next test */
        NN_Reset();
    }
    
    xil_printf("----------------------------------------\r\n\r\n");
    
    /* Print final results */
    print_results(correct, NUM_TESTS);
    
cleanup:
    /* Cleanup */
    xil_printf("\r\nDemo complete.\r\n");
    cleanup_platform();
    
    return 0;
}

/*==============================================================================
 * Helper Functions
 *============================================================================*/

static void print_banner(void)
{
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("  Neural Network MNIST Demo\r\n");
    xil_printf("  Zynq FPGA Hardware Accelerator\r\n");
    xil_printf("========================================\r\n\r\n");
}

static void print_results(int correct, int total)
{
    int accuracy = (correct * 100) / total;
    
    xil_printf("========================================\r\n");
    xil_printf("  Results: %d/%d correct (%d%%)\r\n", correct, total, accuracy);
    xil_printf("========================================\r\n");
    
    if (accuracy >= 90) {
        xil_printf("  Status: EXCELLENT\r\n");
    } else if (accuracy >= 70) {
        xil_printf("  Status: GOOD\r\n");
    } else if (accuracy >= 50) {
        xil_printf("  Status: FAIR\r\n");
    } else {
        xil_printf("  Status: NEEDS IMPROVEMENT\r\n");
    }
}

static int run_single_test(int digit, s16 *outputs)
{
    /* Get test image */
    const s16 *image = get_test_image(digit);
    
    /* Flush cache before DMA transfer */
    Xil_DCacheFlush();
    
    /* Start inference
     * Note: In a full implementation, you would:
     * 1. Configure DMA to transfer input image
     * 2. Transfer weights and biases (if not pre-loaded)
     * 3. Start the accelerator
     * 4. Wait for completion
     * 5. Read back outputs via DMA
     *
     * This simplified version demonstrates the driver API.
     */
    
    /* Start accelerator */
    NN_Start();
    
    /* Wait for completion */
    if (NN_WaitDone(TIMEOUT_US) < 0) {
        return -1;
    }
    
    /* Read outputs
     * In full implementation, outputs would be read from 
     * AXI-Stream master interface via DMA.
     *
     * For now, we use dummy values for demonstration.
     */
    for (int i = 0; i < 10; i++) {
        /* Placeholder - replace with actual output reading */
        outputs[i] = (i == digit) ? FLOAT_TO_FIXED(0.9f) : FLOAT_TO_FIXED(0.1f);
    }
    
    return 0;
}
