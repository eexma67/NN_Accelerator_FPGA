"""
Neural Network for FPGA Deployment
File: network.py
"""

import numpy as np


class NeuralNetwork:
    """Multi-Layer Perceptron Neural Network for FPGA deployment."""
    
    def __init__(self, layers):
        """
        Initialize neural network.
        Args:
            layers: List of layer sizes, e.g., [784, 16, 16, 10]
        """
        self.layers = layers
        self.num_layers = len(layers)
        
        # Xavier initialization
        self.weights = []
        self.biases = []
        
        np.random.seed(42)
        
        for i in range(self.num_layers - 1):
            limit = np.sqrt(6.0 / (layers[i] + layers[i + 1]))
            w = np.random.uniform(-limit, limit, (layers[i + 1], layers[i]))
            b = np.zeros((layers[i + 1], 1))
            self.weights.append(w)
            self.biases.append(b)
    
    def sigmoid(self, z):
        """Sigmoid activation function."""
        return 1.0 / (1.0 + np.exp(-np.clip(z, -500, 500)))
    
    def sigmoid_derivative(self, a):
        """Derivative of sigmoid."""
        return a * (1.0 - a)
    
    def forward(self, x):
        """Forward propagation."""
        activations = [x]
        for w, b in zip(self.weights, self.biases):
            z = np.dot(w, activations[-1]) + b
            a = self.sigmoid(z)
            activations.append(a)
        return activations
    
    def train(self, X_train, y_train, epochs=30, lr=0.5, batch_size=32, verbose=True):
        """Train using mini-batch gradient descent."""
        n = X_train.shape[1]
        
        for epoch in range(epochs):
            # Shuffle
            perm = np.random.permutation(n)
            X_shuffled = X_train[:, perm]
            y_shuffled = y_train[:, perm]
            
            # Mini-batch training
            for i in range(0, n, batch_size):
                X_batch = X_shuffled[:, i:i + batch_size]
                y_batch = y_shuffled[:, i:i + batch_size]
                m = X_batch.shape[1]
                
                # Forward
                activations = self.forward(X_batch)
                
                # Backward
                delta = (activations[-1] - y_batch) * self.sigmoid_derivative(activations[-1])
                
                for layer in range(self.num_layers - 2, -1, -1):
                    dw = np.dot(delta, activations[layer].T) / m
                    db = np.sum(delta, axis=1, keepdims=True) / m
                    
                    self.weights[layer] -= lr * dw
                    self.biases[layer] -= lr * db
                    
                    if layer > 0:
                        delta = np.dot(self.weights[layer].T, delta) * \
                                self.sigmoid_derivative(activations[layer])
            
            if verbose:
                acc = self.evaluate(X_train, y_train)
                print(f"Epoch {epoch + 1:3d}/{epochs}, Accuracy: {acc:.4f}")
    
    def predict(self, x):
        """Make prediction."""
        return np.argmax(self.forward(x)[-1], axis=0)
    
    def evaluate(self, X, y):
        """Evaluate accuracy."""
        pred = self.predict(X)
        labels = np.argmax(y, axis=0)
        return np.mean(pred == labels)
    
    def export_for_fpga(self, output_dir, filename="nn_model", frac_bits=11):
        """Export weights/biases in fixed-point format for FPGA."""
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        scale = 2 ** frac_bits
        
        def to_fixed(val):
            fixed = int(round(val * scale))
            return max(-32768, min(32767, fixed))
        
        def to_hex(val):
            if val < 0:
                val = (1 << 16) + val
            return format(val, '04X')
        
        # Export weights
        weights_file = os.path.join(output_dir, f"{filename}_weights.mem")
        with open(weights_file, 'w') as f:
            f.write("// Neural Network Weights (S.4.11 format)\n\n")
            for layer_idx, w in enumerate(self.weights):
                f.write(f"// Layer {layer_idx}: {w.shape[1]} x {w.shape[0]}\n")
                for row in w:
                    for val in row:
                        f.write(to_hex(to_fixed(val)) + "\n")
                f.write("\n")
        
        # Export biases
        biases_file = os.path.join(output_dir, f"{filename}_biases.mem")
        with open(biases_file, 'w') as f:
            f.write("// Neural Network Biases (S.4.11 format)\n\n")
            for layer_idx, b in enumerate(self.biases):
                f.write(f"// Layer {layer_idx}: {b.shape[0]} biases\n")
                for val in b.flatten():
                    f.write(to_hex(to_fixed(val)) + "\n")
                f.write("\n")
        
        # Export config header
        header_file = os.path.join(output_dir, f"{filename}_config.h")
        with open(header_file, 'w') as f:
            f.write(f"#ifndef {filename.upper()}_CONFIG_H\n")
            f.write(f"#define {filename.upper()}_CONFIG_H\n\n")
            f.write(f"#define NN_NUM_LAYERS    {self.num_layers}\n")
            f.write(f"#define NN_FRAC_BITS     {frac_bits}\n")
            f.write(f"#define NN_INPUT_SIZE    {self.layers[0]}\n")
            f.write(f"#define NN_OUTPUT_SIZE   {self.layers[-1]}\n\n")
            f.write(f"static const int NN_LAYER_SIZES[] = {{")
            f.write(", ".join(map(str, self.layers)))
            f.write("};\n\n")
            f.write(f"#endif\n")
        
        print(f"Exported: {weights_file}, {biases_file}, {header_file}")


def generate_sigmoid_lut(output_dir, filename="sigmoid_lut", num_entries=1024, frac_bits=11):
    """Generate sigmoid lookup table for FPGA."""
    import os
    os.makedirs(output_dir, exist_ok=True)
    
    scale = 2 ** frac_bits
    filepath = os.path.join(output_dir, f"{filename}.mem")
    
    with open(filepath, 'w') as f:
        f.write(f"// Sigmoid LUT: {num_entries} entries\n")
        f.write("// Input: -8.0 to +8.0, Output: 0.0 to 1.0\n\n")
        
        for i in range(num_entries):
            x = (i / (num_entries - 1)) * 16.0 - 8.0
            y = 1.0 / (1.0 + np.exp(-x))
            f.write(format(int(round(y * scale)), '04X') + "\n")
    
    print(f"Generated: {filepath}")


def generate_test_images(output_dir, X_test, y_test, frac_bits=11):
    """Generate test images header for FPGA testing."""
    import os
    os.makedirs(output_dir, exist_ok=True)
    
    scale = 2 ** frac_bits
    labels = np.argmax(y_test, axis=0)
    filepath = os.path.join(output_dir, "test_images.h")
    
    with open(filepath, 'w') as f:
        f.write("#ifndef TEST_IMAGES_H\n")
        f.write("#define TEST_IMAGES_H\n\n")
        f.write("#include \"xil_types.h\"\n\n")
        f.write("#define NUM_TEST_IMAGES 10\n")
        f.write("#define IMAGE_SIZE 784\n\n")
        
        for digit in range(10):
            indices = np.where(labels == digit)[0]
            if len(indices) > 0:
                idx = indices[0]
                f.write(f"static const s16 test_image_{digit}[IMAGE_SIZE] = {{\n    ")
                
                values = []
                for val in X_test[:, idx]:
                    fixed_val = int(round(val * scale))
                    if fixed_val < 0:
                        fixed_val = (1 << 16) + fixed_val
                    values.append(f"0x{fixed_val:04X}")
                
                for j in range(0, len(values), 12):
                    line = ", ".join(values[j:j+12])
                    if j + 12 < len(values):
                        f.write(line + ",\n    ")
                    else:
                        f.write(line + "\n")
                f.write("};\n\n")
        
        f.write("static const s16* test_images[NUM_TEST_IMAGES] = {\n")
        for digit in range(10):
            f.write(f"    test_image_{digit}")
            f.write(",\n" if digit < 9 else "\n")
        f.write("};\n\n")
        
        f.write("static inline const s16* get_test_image(int digit) {\n")
        f.write("    return test_images[digit];\n")
        f.write("}\n\n")
        f.write("#endif\n")
    
    print(f"Generated: {filepath}")
