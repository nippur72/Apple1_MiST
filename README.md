# Apple1_MIST

Apple1 implementation for the MiST FPGA.

This was forked from [Gehstock's project](https://github.com/Gehstock/Mist_FPGA).

## How to use

- F1 clears the Apple-1 display
- F12 open the MiST menu for loading .PRG files

.PRG files are plain binary files with two byte load address
as the first two bytes of the file

## CHANGELOG

2021-12-28

- 15 kHz video output (NTSC) and use of MiST scandoubler/video pipeline
- more accurate 7x8 character matrix (5x7 + hardware spacing)
- clock is now derived from 14.31818 instead of 25 MHz (more accurate)
- serial port communication feature is disabled/removed

