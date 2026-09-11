#!/usr/bin/env python3
"""Scoped foreground input for live QS tests after AT-SPI failed on Wayland.
No text injection. Only SUPER+C, Escape, and left click are supported.
"""
import fcntl, os, struct, sys, time
fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
try:
    fcntl.ioctl(fd, 0x40045564, 1)  # UI_SET_EVBIT EV_KEY
    for key in (125, 46, 1, 272):
        fcntl.ioctl(fd, 0x40045565, key)
    # Relative capability ensures libinput classifies the button device.
    fcntl.ioctl(fd, 0x40045564, 2)
    for axis in (0, 1): fcntl.ioctl(fd, 0x40045566, axis)
    os.write(fd, struct.pack('80sHHHHI', b'QS lifecycle verification', 3, 1, 1, 1, 0) + bytes(64 * 4 * 4))
    fcntl.ioctl(fd, 0x5501)  # UI_DEV_CREATE
    time.sleep(.3)
    def event(code, value):
        os.write(fd, struct.pack('llHHi', 0, 0, 1, code, value))
        os.write(fd, struct.pack('llHHi', 0, 0, 0, 0, 0))
    keys = {'super+c': [125, 46], 'escape': [1], 'click': [272]}[sys.argv[1]]
    for key in keys: event(key, 1)
    time.sleep(.06)
    for key in reversed(keys): event(key, 0)
    time.sleep(.15)
finally:
    fcntl.ioctl(fd, 0x5502)
    os.close(fd)
