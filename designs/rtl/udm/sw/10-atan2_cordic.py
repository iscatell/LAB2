# -*- coding: utf-8 -*-
import matplotlib.pyplot as plt

import math


# ============================================================
# Configuration
# ============================================================

ITERATIONS = 32

# Angle format: Q3.29
#   3 integer bits including sign
#   29 fractional bits
ANGLE_FRAC = 29
ANGLE_SCALE = 1 << ANGLE_FRAC

PI      = int(round(math.pi       * ANGLE_SCALE))
TWO_PI  = int(round(2.0 * math.pi * ANGLE_SCALE))
HALF_PI = int(round((math.pi / 2) * ANGLE_SCALE))


# atan(2^-i), represented as Q3.29
ATAN_TABLE = [
    int(round(math.atan(2.0 ** -i) * ANGLE_SCALE))
    for i in range(ITERATIONS)
]

# hw model - synthesizable operations only

# ============================================================
# CORDIC atan2
# ============================================================

def atan2_cordic_hw(y, x):
    """
    Fixed-point CORDIC atan2.

    Input:
        x, y : signed integers

    Output:
        angle : signed Q3.29 radians

    Range:
        approximately [-pi, +pi]
    """

    # Undefined for (0,0)
    if x == 0 and y == 0:
        return 0

    # --------------------------------------------------------
    # Move vector into right half-plane.
    #
    # atan2(y,x) = atan2(-y,-x) +/- pi
    # --------------------------------------------------------

    if x < 0:
        x = -x
        y = -y
        angle = PI
    else:
        angle = 0

    # --------------------------------------------------------
    # CORDIC vectoring mode
    # --------------------------------------------------------

    # HW stages
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

    # --------------------------------------------------------
    # Normalize to [-pi, pi]
    # --------------------------------------------------------

    if angle > PI:
        angle -= TWO_PI

    elif angle < -PI:
        angle += TWO_PI

    return angle


# ============================================================
# Test
# ============================================================

# generating test stimulus
x_arr = []
y_arr = []
atan_arr = []
for y in range(-1000, 1000, 10):
    y_arr.append(y)
    atan_arr.append(atan2_cordic_hw(y, 100))

plt.plot(y_arr, atan_arr)
plt.show()