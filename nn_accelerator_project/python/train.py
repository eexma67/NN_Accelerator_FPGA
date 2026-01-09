#!/usr/bin/env python3
"""
MNIST Training Script
File: train.py

Usage: python train.py

This script:
1. Loads MNIST dataset
2. Trains a neural network
3. Exports weights for FPGA deployment
4. Generates sigmoid LUT and test images
"""

import numpy as np
import os
from network import NeuralNetwork, generate_sigmoid_lut, generate_test_images


def load_mnist():
    """Load MNIST dataset using TensorFlow/Keras."""
    try:
        from tensorflow.keras.datasets import mnist
    except ImportError:
        print("TensorFlow not found. Installing...")
        os.system("pip install tensorflow")
        from tensorflow.keras.datasets import mnist
    
    print("Loading MNIST dataset...")
    (X_train, y_train), (X_test, y_test) = mnist.load_data()
    
    # Flatten: (N, 28, 28) -> (784, N) and normalize to [0, 1]
    X_train = X_train.reshape(-1, 784).T / 255.0
    X_test = X_test.reshape(-1, 784).T / 255.0
    
    # One-hot encode labels
    def one_hot(y, num_classes=10):
        oh = np.zeros((num_classes, len(y)))
        oh[y, np.arange(len(y))] = 1
        return oh
    
    y_train_oh = one_hot(y_train)
    y_test_oh = one_hot(y_test)
    
    print(f"  Training samples: {X_train.shape[1]}")
    print(f"  Test samples: {X_test.shape[1]}")
    
    return X_train, y_train_oh, X_test, y_test_oh


def main():
    print("=" * 60)
    print("Neural Network Training for FPGA Deployment")
    print("=" * 60)
    
    # Output directory (relative to this script)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "..", "rtl", "mem")
    sw_output_dir = os.path.join(script_dir, "..", "software")
    
    # Load data
    X_train, y_train, X_test, y_test = load_mnist()
    
    # Create network: 784 -> 16 -> 16 -> 10
    print("\nCreating neural network [784, 16, 16, 10]...")
    nn = NeuralNetwork([784, 16, 16, 10])
    
    # Train
    print("\nTraining (30 epochs)...")
    print("-" * 40)
    nn.train(X_train, y_train, epochs=30, lr=0.5, batch_size=32)
    print("-" * 40)
    
    # Evaluate on test set
    test_acc = nn.evaluate(X_test, y_test)
    print(f"\nTest Accuracy: {test_acc:.4f} ({test_acc*100:.2f}%)")
    
    # Export for FPGA
    print("\nExporting for FPGA...")
    print("-" * 40)
    
    nn.export_for_fpga(output_dir, "nn_model", frac_bits=11)
    generate_sigmoid_lut(output_dir, "sigmoid_lut", num_entries=1024, frac_bits=11)
    generate_test_images(sw_output_dir, X_test, y_test, frac_bits=11)
    
    print("-" * 40)
    print("\nDone! Generated files:")
    print(f"  RTL memory files: {output_dir}")
    print(f"    - nn_model_weights.mem")
    print(f"    - nn_model_biases.mem")
    print(f"    - nn_model_config.h")
    print(f"    - sigmoid_lut.mem")
    print(f"  Software files: {sw_output_dir}")
    print(f"    - test_images.h")
    print("=" * 60)


if __name__ == "__main__":
    main()
