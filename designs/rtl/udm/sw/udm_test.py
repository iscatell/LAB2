# -*- coding:utf-8 -*-
from __future__ import division
import math
import sys

import udm
from udm import *

# ============================================================
# CORDIC Golden Model in Python
# ============================================================
ITERATIONS = 32
ANGLE_FRAC = 29
ANGLE_SCALE = 1 << ANGLE_FRAC

PI      = int(round(math.pi       * ANGLE_SCALE))
TWO_PI  = int(round(2.0 * math.pi * ANGLE_SCALE))

ATAN_TABLE = [
    int(round(math.atan(2.0 ** -i) * ANGLE_SCALE))
    for i in range(ITERATIONS)
]

def atan2_cordic_hw(y, x):
    if x == 0 and y == 0:
        return 0

    if x < 0:
        x = -x
        y = -y
        angle = PI
    else:
        angle = 0

    for i in range(ITERATIONS):
        x_old = x
        y_old = y

        if y > 0:
            x = x_old + (y_old >> i)
            y = y_old - (x_old >> i)
            angle += ATAN_TABLE[i]
        else:
            x = x_old - (y_old >> i)
            y = y_old + (x_old >> i)
            angle -= ATAN_TABLE[i]

    if angle > PI:
        angle -= TWO_PI
    elif angle < -PI:
        angle += TWO_PI

    return angle & 0xFFFFFFFF


# ============================================================
# Hardware Validation via UDM
# ============================================================
COM_PORT = 'COM1'  # Update to your actual COM port (e.g. 'COM3', 'COM4')
BAUDRATE = 921600

print(f"Connecting to FPGA via UDM on {COM_PORT} at {BAUDRATE} baud...")
u = udm(COM_PORT, BAUDRATE)
print("Connected successfully!\n")

CSR_Y_ADDR     = 0x10000000
CSR_X_ADDR     = 0x10000004
CSR_ANGLE_ADDR = 0x20000000

test_vectors = [
    (100, 100),
    (100, -100),
    (-100, -100),
    (-100, 100),
    (0, 100),
    (100, 0),
    (-100, 0),
    (0, -100),
    (0, 0),
    (1000, 2000),
    (-1000, -2000),
]

all_passed = True
print("Starting Hardware Validation for CORDIC atan2:")
print("-" * 70)

for y, x in test_vectors:
    # 1. Write inputs to accelerator CSRs
    u.wr32(CSR_Y_ADDR, y & 0xFFFFFFFF)
    u.wr32(CSR_X_ADDR, x & 0xFFFFFFFF)

    # 2. Read output angle from accelerator CSR
    hw_angle = u.rd32(CSR_ANGLE_ADDR)

    # 3. Compute expected golden value
    expected_angle = atan2_cordic_hw(y, x)

    # 4. Compare
    passed = (hw_angle == expected_angle)
    if not passed:
        all_passed = False

    status = "OK" if passed else "MISMATCH!"
    print(f"y={y:6d}, x={x:6d} | HW: 0x{hw_angle:08x} | Exp: 0x{expected_angle:08x} | {status}")

print("-" * 70)
if all_passed:
    print("ALL TESTS PASSED! Bit-accurate match confirmed between FPGA and Python model.")
else:
    print("SOME TESTS FAILED! Please check signal routing and timing closure.")

u.disconnect()
