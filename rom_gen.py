import numpy as np
rows, cols = 32, 32

image = np.zeros((rows,cols))
for r in range(rows):
    for c in range(cols):
        if c >= cols // 2:
            image[r, c] = 64.0

def to_hex(val):
    q_val = int(round(val * 256.0))
    if q_val < 0:
        q_val = (1 << 16) + q_val
    return f"{q_val & 0xFFFF:04X}"

if __name__ == "__main__":
    with open("rom.hex", "w") as f:
        for r in range(rows):
            for c in range(cols):
                f.write(f"{to_hex(image[r, c])}")
                if not (r == rows - 1 and c == cols - 1):
                    f.write("\n")