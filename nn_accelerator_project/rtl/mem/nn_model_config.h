#ifndef NN_MODEL_CONFIG_H
#define NN_MODEL_CONFIG_H

#define NN_NUM_LAYERS    4
#define NN_FRAC_BITS     11
#define NN_INPUT_SIZE    784
#define NN_OUTPUT_SIZE   10

static const int NN_LAYER_SIZES[] = {784, 16, 16, 10};

#endif
