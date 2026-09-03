import numpy as np
rows, cols = 32, 32

image = np.zeros((rows,cols))

# for r in range(rows):
#     for c in range(cols):
#         if c >= cols // 2:
#             image[r, c] = 64.0

for r in range(rows):
    for c in range(cols):
        if r + c > 31:
            image[r, c] = 64.0  # High intensity
        else:
            image[r, c] = 0.0   # Low intensity (Black)

# image[:, cols // 2:] = 64.0  # step edge

# for c in range(cols):
#     if c < cols // 2:
#         image[:, c] = c * 2.0 # ramp image

def to_hex(val):
    q_val = int(round(val * 256.0))
    # Saturate to the signed 16-bit Q8.8 range instead of wrapping, to match
    # the hardware's explicit overflow-saturation logic.
    if q_val > 32767:
        q_val = 32767
    elif q_val < -32768:
        q_val = -32768
    if q_val < 0:
        q_val = (1 << 16) + q_val
    return f"{q_val & 0xFFFF:04X}"

if __name__ == "__main__":
    with open("rom.mem", "w") as f:
        for r in range(rows):
            for c in range(cols):
                f.write(f"{to_hex(image[r, c])}")
                if not (r == rows - 1 and c == cols - 1):
                    f.write("\n")