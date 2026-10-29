# -*- coding:utf-8 -*-
from __future__ import division
import math
import sys
import matplotlib.pyplot as plt

import udm
from udm import *

# ============================================================
# CORDIC Golden Model (из файла преподавателя 10-atan2_cordic.py)
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
    """Эталонный расчет алгоритма CORDIC на ПК."""
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

    return angle


# ============================================================
# Подключение к FPGA плате
# ============================================================
COM_PORT = 'COM3'  # Укажите актуальный COM-порт из Диспетчера устройств
BAUDRATE = 115200  # Стандартная надежная скорость для Windows / FTDI (UDM поддерживает auto-baud)

print(f"Connecting to FPGA via UDM on {COM_PORT} at {BAUDRATE} baud...")
try:
    u = udm(COM_PORT, BAUDRATE)
    print("Connection established successfully!\n")
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

CSR_Y_ADDR      = 0x10000000
CSR_X_ADDR      = 0x10000004
CSR_START_ADDR  = 0x10000008
CSR_ANGLE_ADDR  = 0x20000000
CSR_STATUS_ADDR = 0x20000004


# ============================================================
# 1. Точечные тесты по квадрантам
# ============================================================
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
]

print("1. Running Quadrant Spot Tests (Multicycle CORDIC, ~34 cycles/op):")
print("-" * 80)
for y, x in test_vectors:
    u.wr32(CSR_Y_ADDR, y & 0xFFFFFFFF)
    u.wr32(CSR_X_ADDR, x & 0xFFFFFFFF)
    u.wr32(CSR_START_ADDR, 1)  # Запуск вычислений

    status_raw = u.rd32(CSR_STATUS_ADDR)
    ready_flag = status_raw & 0x1

    hw_raw = u.rd32(CSR_ANGLE_ADDR)
    hw_val = hw_raw if hw_raw < 0x80000000 else hw_raw - 0x100000000
    exp_val = atan2_cordic_hw(y, x)

    status = "OK" if hw_val == exp_val else "MISMATCH!"
    print(f"y={y:5d}, x={x:5d} | HW: {hw_val:11d} (0x{hw_raw:08x}) | Exp: {exp_val:11d} | Ready={ready_flag} | {status}")
print("-" * 80 + "\n")


# ============================================================
# 2. Полноразмерный прогон тестового стимула (как в файле препода)
# ============================================================
print("2. Generating stimulus and comparing with Python Model across 200 points...")
y_arr = []
hw_atan_arr = []
exp_atan_arr = []
diff_arr = []

FIXED_X = 100

for y in range(-1000, 1000, 10):
    # Запись аргументов и запуск
    u.wr32(CSR_Y_ADDR, y & 0xFFFFFFFF)
    u.wr32(CSR_X_ADDR, FIXED_X & 0xFFFFFFFF)
    u.wr32(CSR_START_ADDR, 1)

    # Чтение ответа с платы и перевод в знаковый формат
    hw_raw = u.rd32(CSR_ANGLE_ADDR)
    hw_angle = hw_raw if hw_raw < 0x80000000 else hw_raw - 0x100000000

    # Расчет эталонной модели
    exp_angle = atan2_cordic_hw(y, FIXED_X)

    y_arr.append(y)
    hw_atan_arr.append(hw_angle)
    exp_atan_arr.append(exp_angle)
    diff_arr.append(abs(hw_angle - exp_angle))

u.disconnect()

max_diff = max(diff_arr)
print(f"Stimulus test completed! Maximum absolute difference: {max_diff}")
if max_diff == 0:
    print(">>> SUCCESS: 100% BIT-ACCURATE MATCH ACROSS ALL POINTS! <<<\n")
else:
    print(">>> WARNING: Mismatches detected! <<<\n")


# ============================================================
# 3. Построение сравнительного графика
# ============================================================
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

# Верхний график: Наложение вычислений FPGA и модели
ax1.plot(y_arr, hw_atan_arr, 'b-', linewidth=2, label="FPGA Hardware (UDM)")
ax1.plot(y_arr, exp_atan_arr, 'r--', linewidth=1.5, label="Teacher's Model (10-atan2_cordic.py)")
ax1.set_title(f"CORDIC atan2(y, x={FIXED_X}): FPGA Hardware vs Python Reference Model", fontsize=12)
ax1.set_ylabel("Angle (Q3.29 integer)", fontsize=10)
ax1.grid(True, linestyle="--", alpha=0.6)
ax1.legend(loc="upper left")

# Нижний график: Побитовая разница (должна быть строго нулем)
ax2.plot(y_arr, diff_arr, 'g-', linewidth=1.5, label="Bit Error (|HW - Model|)")
ax2.set_title("Bit-Accurate Difference (|HW - Model|)", fontsize=11)
ax2.set_xlabel("Argument y (with x = 100)", fontsize=10)
ax2.set_ylabel("Error (bits)", fontsize=10)
ax2.set_ylim(-1, 2)
ax2.grid(True, linestyle="--", alpha=0.6)
ax2.legend(loc="upper left")

plt.tight_layout()
print("Displaying comparison plot...")
plt.show()
