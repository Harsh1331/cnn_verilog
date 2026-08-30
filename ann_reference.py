import numpy as np
from scipy.signal import convolve2d
from ann_reference import image, to_hex

# Standard 3x3 Sobel kernel for vertical edge detection (Channel 1)
kernel_ch1 = np.array([
    [-1,  0,  1],
    [-2,  0,  2],
    [-1,  0,  1]
])

# Perform 2D convolution
# mode='same' retains the 32x32 boundaries
conv_result = convolve2d(image, kernel_ch1, mode='same', boundary='fill')

# Apply standard ReLU activation function: max(0, z)
relu_result = np.maximum(0, conv_result)

# Convert a known edge pixel to Q8.8 to verify against your hardware output
test_row, test_col = 15, 16
hex_check = to_hex(relu_result[test_row, test_col])
print(f"Expected ReLU output at 0-index ({test_row}, {test_col}) in Q8.8 Hex: {hex_check}")