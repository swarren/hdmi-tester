#!/usr/bin/env python3

import serial
import sys
import time

app = sys.argv.pop(0)
sport = sys.argv.pop(0)
edidfn = sys.argv.pop(0)

f = open(edidfn, 'rb')
edid = f.read()
f.close()

ser = serial.Serial(sport, baudrate=115200, rtscts=False)

ser.sendBreak()
ser.write(bytes('H0', 'ascii'))
val = ser.read(3) # 0 CR LF
ser.write(bytes('E', 'ascii'))
ser.write(edid)
ser.sendBreak()
ser.write(bytes('H1', 'ascii'))
val = ser.read(3) # 0 CR LF
