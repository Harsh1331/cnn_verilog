import numpy as np
from scipy.signal import correlate2d
from rom_gen import image, to_hex 

kernel_ch1 = np.array([
    [-1,  0,  1],
    [-2,  0,  2],
    [-1,  0,  1]
])

kernel_ch2 = np.array([
    [-1, -2, -1],
    [ 0,  0,  0],
    [ 1,  2,  1]
])

pool_shape = (15, 2, 15, 2)

# Channel 1
conv_result_ch1 = correlate2d(image, kernel_ch1, mode='valid')
relu_result_ch1 = np.maximum(0, conv_result_ch1)
pooled_result_ch1 = relu_result_ch1.reshape(pool_shape).max(axis=(1, 3))
expected_hex_ch1 = [to_hex(val) for val in pooled_result_ch1.flatten()]

# Channel 2
conv_result_ch2 = correlate2d(image, kernel_ch2, mode='valid')
relu_result_ch2 = np.maximum(0, conv_result_ch2)
pooled_result_ch2 = relu_result_ch2.reshape(pool_shape).max(axis=(1, 3))
expected_hex_ch2 = [to_hex(val) for val in pooled_result_ch2.flatten()]

try:
    with open("ann_vivado/ann_vivado.sim/sim_1/behav/xsim/hw_output_ch1.txt", "r") as f1, open("ann_vivado/ann_vivado.sim/sim_1/behav/xsim/hw_output_ch2.txt", "r") as f2:
        hw_hex_ch1 = [line.strip() for line in f1.readlines()]
        hw_hex_ch2 = [line.strip() for line in f2.readlines()]
except FileNotFoundError:
    print("Error: Hardware output files not found.")
    exit()

if len(hw_hex_ch1) != len(expected_hex_ch1) or len(hw_hex_ch2) != len(expected_hex_ch2):
    print("Error: Length mismatch. Hardware output is incomplete.")
    exit()

mismatches_ch1 = 0
mismatches_ch2 = 0

# The .lower() formatting ensures capital and small letters are treated as non-unique
for i in range(len(expected_hex_ch1)):
    if hw_hex_ch1[i].lower() != expected_hex_ch1[i].lower():
        row, col = divmod(i, 15)
        print(f"CH1 Mismatch at 0-indexed pos ({row}, {col}): Expected {expected_hex_ch1[i]}, Got {hw_hex_ch1[i]}")
        mismatches_ch1 += 1

for i in range(len(expected_hex_ch2)):
    if hw_hex_ch2[i].lower() != expected_hex_ch2[i].lower():
        row, col = divmod(i, 15)
        print(f"CH2 Mismatch at 0-indexed pos ({row}, {col}): Expected {expected_hex_ch2[i]}, Got {hw_hex_ch2[i]}")
        mismatches_ch2 += 1

if mismatches_ch1 == 0 and mismatches_ch2 == 0:
    print("Verification Passed: Hardware perfectly matches the Python reference model.")
else:
    print(f"Verification Failed: {mismatches_ch1} mismatches in CH1, {mismatches_ch2} mismatches in CH2.")