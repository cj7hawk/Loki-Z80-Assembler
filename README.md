# Loki Z80 Assembler - With compatible Cross Assembler for PC Windows 10/11, DOS and Linux. 

A z80 assembler for CP/M. Assembles z80 source code and includes both extended and undocumented instructions.
Also includes a PC based Cross Assembler written to take the same source code, now allowing ASM files to be assembled under Windows 10 or 11 CLI.

Both are synchronised to produce the same binaries from the same ASM files, so should be usable for people developing on either platform.

While 0.92 was Still in ALPHA, Version 0.94 moves it to BETA. There's still elements I want to address, but it's close to having everything I wanted in there complete, and now it's time to write the manual. 

The .BIN file is a functional Binary, and can assemble itself. It contains most of the intended Version 1 code, including Macros and Groups and is still small and fast, both assembling and linking in under 12Kb even when loaded at offset $0100. Runs under CP/M. z80 machines only. 

Just rename the BIN file as a COM file - eg, PIP ASSEMBLE.COM=ASSEMBLE.BIN or use REN ASSEMBLE.BIN ASSEMBLE.COM to make executable. 

The BASIC file LokiCross.BAS can be compiled under FREEBASIC for Windows and Linux platforms. It is the same version - You can use the system variable XVERSION to see the version now - It's four BCD packed digits. Two version numbers, two sub-version numbers. 

If you find any significant differences between the PC and z80 CP/M versions, please let me know. 

Next I'll complete the manual so you can use it's full functionality, but in the mean time, you can use the example of assemble.asm as a guide.

Outside of normal z80, EX AF,AF is the only exception as I never use the ' (single quote) character in the opcodes. All extended undocumented instructions are supported. 
