#!/usr/bin/env python3

import serial
import sys
import time

ser = serial.Serial(sys.argv[1], baudrate=115200, rtscts=False)

ser.sendBreak()
ser.write(bytes('C', 'ascii'))
val = ser.read(8)
print(int(val, 16))
val = ser.read(2) # CR LF
