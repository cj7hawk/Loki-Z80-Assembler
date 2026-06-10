# Loki Z80 Assembler - With compatible Cross Assembler for PC Windows 10/11, DOS and Linux. 

A z80 assembler for CP/M. Assembles z80 source code and includes both extended and undocumented instructions.
Also includes a PC based Cross Assembler written to take the same source code, now allowing ASM files to be assembled under Windows 10 or 11 CLI.

Both are synchronised to produce the same binaries from the same ASM files, so should be usable for people developing on either platform.

Still in ALPHA. The .BIN file is a functional Binary, and can assemble itself. Contains most of the intended Version 1 code, except Macro's and some cleaning up and bounds checking. Small and Fast. Runs under CP/M. z80 machines only. 

Just rename the BIN file as a COM file - eg, PIP ASSEMBLE.COM=ASSEMBLE.BIN or use REN ASSEMBLE.BIN ASSEMBLE.COM to make executable. 

The BASIC file LokiCross.BAS can be compiled under FREEBASIC for Windows and Linux platforms. 

If you find any significant differences between the PC and z80 CP/M versions, please let me know. 