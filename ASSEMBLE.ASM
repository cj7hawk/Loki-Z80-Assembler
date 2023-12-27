;z80 Assembler - To work and assemble z80 code within the LOKI environment. 
;
; Note currently trying to evaluate - And process multiple same operators - eg, 123<<<<
;
;
; Stuff to do 
; If pass=2 and a label does not exist, ERROR OUT. - eg, JP (UU) will look like a 4 character label, and is valid, but if no (UU): or EQU (UU) then it's NOT valid even though it eval's to nothing. 
; Next up, how to deal with the closing backet in eval.... 
;  - Eval Filter when closing bracket is present. Turn on a switch. 
; Also  is it IX+ and IX- ??? 

; Note in emulator, RST 20 turns on debug. RST 28 turns debug back off. 
								
; Note: Other constants appear at the end - Usually stuff like BDOS call expressions for different functions. 

; Code begins here. 
; STUFF TO REMEMBER. If EVAL is called with an operator ( eg, a COMMA ) it will do another read.... So remove commas before we call EVAL. Especially single values. 

;
; CALL format. LASM INFILE.ASM OUTFILE.COM /A/B/C/d/e/f/g/ etc. 
; /D debug
; /H Hex format
; 
;
; Synopsis - This routine reads the source a byte at a time, and loads the next "symbol" to be decoded into the buffer at BUFFER. Buffer is a 256 byte space with the first digit being the character count
; The Buffer is loaded by routines GETWORD_TO_WS and GETWORD_TO_END. The difference is;
;   GETWORD_TO_WS reads through whitespace until it hits a character. Then it reads the characters into buffer until it hits an operator or whitespace. or EOL or EOF. 
;   GETWORD_TO_END is as GETWORD_TO_WS but will also ignore whitespace after characters until it hits an operator or EOL or EOF
; Any listed operators it encounters ( it won't encounter more than 1 ) are loaded into the Variable "OPERATOR" except for special operators, which are not recorded or remembered.
; Once the buffer is filled it can be compared to a pre-existing string pointed to by DE via TESTLOOP which will return a Z if the string matches. 

; To Add
; 1. Warnings - Set "End Of PC" alert.
; 2. Set Notices to print to console.
; 3. Add simple macros.
; 4. Write external routine to show all labels.... ( Debug Toolkit ). Can be run post-assembly. 
; 5. Hex output option. ( Binary or Hex. ).
; 6. Show all errors DEBUG
; 7. SERIOUS ISSUE - Need to modify ADD_LABEL to set an upper limit on the label table. 

;
; Conditional Switches... MUST be before code if conditional assembly used.
EQU	DEBUG,$00



;System Constants.
.EQU	BDOS,$0005
.EQU	FCB1,$005C
;.EQU	LABEL_TABLE,$2000		; I need to add something that fails if PC goes over $1FFF..... As a switch. 

;Configuration Constants.
.EQU	BUFFERSIZE,256			; Note what the buffer size is. 256 bytes in this case. Can be strings, Equations or anything. 
								; Does not include comments ( anything following a ; ) or whitespace ( ALL characters below $20 )
								

.ORG $0100		; Standard CP/M entry point. 

OPEN_ASSEMBLY:
				LD		HL,$0000
				LD		(LABEL_TABLE),HL	; Clear Label table just this once... And since HL is alrady 0000 for the next opcode... 
				ADD		HL,SP			; Move the SP location to HL.
				LD		(STACK_SAVE),HL	; Store the stack location at present.


				LD		DE,WELCOME_MESSAGE
				CALL	PRINTSTRING
				
				LD		HL,$006C		; Second filename in default FCB.
				LD		DE,OUTPUT_FCB	; Move to the Output FCB
				LD		BC,$10			; Filename and Drive number. 
				LDIR				
				CALL	OPEN_DEST		; Open the output file - don't write it.
				
				CALL	INIT_VARS
				CALL	OPEN_SOURCE		; Open the source code file - And read the first sector. 

				CALL	OUTPUT_RESET	; Reset(SET) the counters for the output file. 
				CALL	SWITCHES		; Examine Switches				

				CALL	PASS1			; Build table of labels. 

;LD		HL,LABEL_TABLE
;HALT			; Initiate debug here. 



				CALL	INIT_VARS
				CALL	OPEN_SOURCE				
				CALL	PASS2	

				CALL	CLOSE_DEST

				LD		DE,NOERRORS
				CALL	PRINTSTRING

				CALL	SHOW_STATS
				
				LD		HL,$0400
				LD		DE,$0800
				LD		BC,$AA55				; Signal to emulator to display hex from HL to DE
	;			HALT							; Force an exit for debugging purposes. 
				

				RET



OPEN_SOURCE:
				LD      DE,FCB1         ; We want to use the first FCB populated by the CCP. 
				LD      C,Open_File     ; Open File.
				CALL    BDOS			; 			Get the first matching file.
				
				AND		$FC
				JP		NZ,OPEN_ERROR
				
				CALL	READ_SOURCE		; Read in the first sector. 
				
				RET
				
OPEN_DEST:
				LD      DE,OUTPUT_FCB         ; We want to use the first FCB populated by the CCP. 
				LD      C,Make_File     ; Open File.
				CALL    BDOS			; 			Get the first matching file.

				AND		$FC					; Any errors?
				JP		NZ,OPENDEST_ERROR				

				LD		A,(OUTPUT_FCB+1)
				CP		$20
				JP		Z,OPENDEST_ERROR	; Make sure we got a filename.... 

				RET	

	
READ_SOURCE:			
				LD		DE,$0080
				LD		C,Set_DMA_Address
				CALL	BDOS
				
				LD      DE,FCB1         	; Make sure DE still holds the correct FCB handle. 
				LD      C,Read_Sequential   ; read next record
    			CALL    BDOS				; 					
				
				RET

WRITE_DEST:			
				LD		DE,OUTPUT_BUFFER
				LD		C,Set_DMA_Address
				CALL	BDOS
				
				LD      DE,OUTPUT_FCB         	; Make sure DE still holds the correct FCB handle. 
				LD      C,Write_Sequential   ; read next record
				CALL    BDOS				; 	

				RET

CLOSE_DEST:
				LD		A,(OUTPUT_COUNT)
				OR		A
				JR		Z,CLOSE_DEST_NOWRITE	; No need to close the file. We already saved with the last Write Dest.
				CALL	WRITE_DEST			; Write it if anything remains unsaved. 
CLOSE_DEST_NOWRITE:
				LD		DE,OUTPUT_FCB
				LD		C,Close_File

 CALL	BDOS

				RET

BYTE_TO_FILE:								;Sequential Byte by Byte.
				LD		HL,(OUTPUT_PTR)
				LD		(HL),A
				INC		HL
				LD		(OUTPUT_PTR),HL
				LD		A,(OUTPUT_COUNT)
				INC		A
				LD		(OUTPUT_COUNT),A
				CP 		$80					; Check if we've written 128 bytes (record) to the buffer yet?
				RET		NZ					; Return if not full.
				CALL	WRITE_DEST			; Write a record. 
OUTPUT_RESET:
				LD		HL,OUTPUT_BUFFER
				LD		(OUTPUT_PTR),HL
				XOR		A
				LD		(OUTPUT_COUNT),A
				RET

INIT_VARS:									; Initialise System Variable - Especially since we make 2 passes they will change.
				LD		HL,$0068			; Clear out the old FCB so we can start reading it again.
				LD		B,$18				; 24 bytes to clear.
PASS2_CLEAR_FCB:	
				LD		(HL),$00
				INC		HL
				DJNZ	PASS2_CLEAR_FCB		; Clear the file FCB. 

				LD		HL,$0000
				XOR		A				
				LD 		(LINE_NUMBER),HL
				LD		(LINES),HL
				LD		(LABELS),HL
				LD		(EOF),A
				LD		(CHARPOS),A
				LD		(CHAR_RECORD),HL
				LD		(CONDITIONAL),A		; Clear any conditional blocks to assembly. 
				DEC		A			; Make A FF
				LD		(EOL),A		; Set for EOL since we want to trigger a line change from 0 to 1 on first read. 
				RET


SHOW_STATS:
				CALL	CRLF			;Show the PC
				LD		HL,(PC)
				LD		DE,END_PC
				CALL	PRINTHEXVAL

				CALL	CRLF			; Show the final line number
				LD		HL,(LINE_NUMBER)
				LD		DE,END_LINES
				CALL 	PRINTDECVAL

				CALL	CRLF			; Show the number of opcodes
				LD		HL,(OPCODES)
				LD		DE,END_CODES
				CALL	PRINTDECVAL
				
				CALL	CRLF			; Show the table size.
				LD		HL,(LABEL_LAST)
				LD		DE,(LABEL_TABLE)
				OR		A
				SBC		HL,DE
				LD		DE,END_TABLESIZE
				CALL	PRINTDECVAL
				RET

END_LINES:	DB	' Lines$'
END_PC:		DB	' Final PC$'
END_CODES:	DB	' Opcodes$'
END_TABLESIZE:	DB	' bytes Table size$'

PASS_1_COMPLETE: DB 'Pass 1 complete$'

PRINTHEXVAL:
			PUSH	DE
			CALL	PRINTHEX16
			POP		DE
			JR		PRINTSTRING

PRINTDECVAL:
			PUSH	DE				; First print the decimal value in HL...
			CALL	PRINTDEC16
			POP		DE				; Then drop through and print the string pointed to by DE
			
PRINTSTRING:
			LD	C,Print_String
			CALL	BDOS
			ret
				
SWITCHES:
				LD		HL,$0080		; WHere the command line exists.
				LD		A,(HL)
				CP		2				; We need at least 2 characters... More if a filename is present.
				RET		C				; Return if it's less than 2. 
				LD		B,(HL)			; How many characters we can scan through.
				DEC		B				; Because the last character is NOT going to be a switch. Reduce by one ( so we ignore a switch without a character )
SWITCHLOOP:		INC		HL
				LD		A,(HL)
				CP 		'/'				; Switch 
				CALL	Z,SWITCH_TEST	; See if it's valid?
				DJNZ	SWITCHLOOP
				RET
				
SWITCH_TEST:	INC		HL
				LD		A,B
				CP		$01
				JR		Z,SWITCH_NODECB		; If it's already going to time out, don't make it go to 256.
				DEC		B
SWITCH_NODECB:	LD		A,(HL)	
				CP		'D'					; 
				JR		Z,DEBUG_ON
				RET
				
DEBUG_ON:
;				LD		A,$FF
;				LD		(DEBUG),A
				RET

;################ A lot of standard errors below. Anything to ERROR_OUT will dump the stack, restore pre-run
; state and exit the system.

MISSING_COMMA:
				LD		DE,ERR_COMMA_MISSING
				JP		ERROR_OUT

OPEN_ERROR:				
				LD		DE,ERR_NOT_FOUND
				JP		ERROR_OUT

OPENDEST_ERROR:
				LD		DE,ERR_NO_DEST
				JP		ERROR_OUT
				
OUTPUT_ERROR:
				LD		DE,ERR_OPEN_FAIL
				JP		ERROR_OUT

ERROR_OUT:
nop				; Turn off any debug - Don't take it back to the OS.
nop
nop
nop
RST $28
				
				PUSH	DE
				CALL	CRLF
				POP		DE
				CALL 	PRINTSTRING


CALL CRLF
CALL PRINTLINE
CALL PRINTPC
CALL PRINTBUFFER
CALL PRINTSPACE

LD		HL,(PC)
CALL PRINTHEX16

CALL PRINTSPACE


LD		HL,(VALUE)
CALL	PRINTHEX16

CALL PRINTSPACE




LD		HL,(LABEL_LAST)
CALL PRINTHEX16

CALL SHOW_STATS

				LD		HL,(STACK_SAVE)
				LD		SP,HL


LD HL,OUTPUT_FCB
LD DE,OUTPUT_BUFFER+127
LD BC,$AA55
HALT				
				RET								; And just return out... 


;System Variables.
STACK_SAVE:		DW		$0000					; Out stack on entry. Save it in case of error. 
PC: 			DW		$0000					; Program Counter.
PC_OFFSET:		DW		$0000					; Offset to write code. (eg, PC=$0000 PC_OFFSET=$8000 will assemble code for use at 0000 at 8000 for relocation )
RELATIVE:		DB		$00						; Relative jump vector.

LINE_NUMBER:	DW		$0000						; Current line number. Starts at 1. 
LINES:			DW		$0000					; Code line.
LABELS:			DW		$0000					; Number of labels. 
EOL:			DB		$FF						; If set to FF, notes we just hit an EOL during the operation, so line count will be incremented next cycle. 
EOF:			DB		$00						; Set to zero if current source file is not at EOF. So we can record when there's nothing else to read. 
											;	Non Zero means we've hit the current EOF. 
CHARPOS:		DB		$00				; Where we are in the current record of the source file ( within 128 byte record ). Pointer. 
CHAR_RECORD:	DB		$00,$00			; Three bytes means a 16Mb file maximum for the input source... More than the directory size. Is sufficient. 
										; These are zeroed in the file, so we don't need to initialise them. The first one we'll use a 128 count, so 
										; that makes it 8Mb which is the size of a max disk.  The record number is up to 16 bits. 
LIVE:			DB		$FF				; If 0, no live writing. If FF, then actually write to memory in real time. Will later set up to write to a different page. 

BUFFER:			BLOCK	BUFFERSIZE		; Allows for short words, and long evaluated expressions. 
										; Mathematical expressions will be evaluated in a single piece.
										; Strings are also evaluated in a single piece.
										; Block size can be changed.
										; First byte is the number of characters.
										; Last byte after characters should be zero. Ignores whitespace. 
BUFFER_PTR:		DW	BUFFER+1			; What part of the buffer we are in. It's a 16 bit location, directly for buffer. 


PREFIX:			DB		$00				; Are we adding a prefix?
POSTFIX:		DB		$00				; And is there a postfix?
ADDPOST:		DB		$00				; We may need a flag to tell us to add a postfix. 

OPCODES:			DW		$0000			; How many opcodes did we write?			

CONDITIONAL:		DB		$00				; While this is $00, process instructions. Don't change this until we get the directive IFEND							

IN_MACRO:			DB		$00				; Flag - When I'm in a MACRO, this should be non-zero. It 

OUTPUT_PTR:		DW		$0000
OUTPUT_COUNT:	DB		$0000



	
;DR F1 F2 F3 F4 F5 F6 F7 F8 T1 T2 T3 EX S1 S2 RC  .FILENAMETYP...
;AL AL AL AL AL AL AL AL AL AL AL AL AL AL AL AL  ...............
;CR R0 R1 R2                                      ....		
OUTPUT_FCB:			DB	$00				; Current drive default. 		
OUTPUT_FILENAME:	DB	'z80labeltmp'		; default label file name. 
OUTPUT_FILENAME_CNT:	DB $00,$00,$00,$00
OUTPUT_FILENAME_ALL:	DB $00,$00,$00,$00, $00,$00,$00,$00, $00,$00,$00,$00, $00,$00,$00,$00
OUTPUT_FILENAME_HND:	DB $00,$00,$00,$00

OUTPUT_BUFFER:
BLOCK $80				; 128 byte buffer for output DMA. 

; Assembler Architecture.
; Labels are stored in a "Disk Array " which ideally should be in Main Memory not on a disk. 
; 32 bytes per label. This allows up to 28 bytes for the label, which includes;
; Offset	Function
; 0			Count of characters in Label.
; 1 - 27	Label. (27 characters max, 28 including :).
;28 - 31	Value.	4 byte value. Most should be 1 or 2 bytes. Supports up to 4 bytes. 
;
; At 32 bytes per label, that means 1000 labels would be 32K of space. There is no upper limit. That is 256 records. Not a lot with a fair bit of memory.
; This is referenced on M:




										; When we get here, there's an open file and we can read it from the data area. The first
										; record is already in place at 0080. FCB1 ( 005C ) holds the FCB for the input file. 
										; Also theres a FCB at LABEL_FCB that holds the file handle for the label data. Labels are slow
										; so it opens up on the M: RAMDRIVE for better speed.
										; This pass collects all the labels.
PASS:	DB	$00
																		
PASS1:
				LD		A,$01
				LD		(PASS),A			; Record we're on PASS 1. Unknown labels can be ignored here. 
				CALL	MAKE_PASS			; Make a pass.

				CALL	CRLF					; Note it was completed. 
				LD		DE,PASS_1_COMPLETE
				CALL	PRINTSTRING
				
				RET


PASS2:								; Now make a serious pass.
		LD		A,$02
		LD		(PASS),A			; Record we're on PASS 2. Unknown labels can be ignored here. 
		
		CALL	MAKE_PASS			; Make a pass.
		RET


MAKE_PASS:							; Where the actual pass is made. 
									; Anything I need here. 
PASS_LOOP:	
				LD		A,(EOL)			; See if we got an EOL from the previous read.... So we can increment line numbers.
				OR		A
				JR		Z,PASS1_SAMELINE	; If we didn't get an EOL at the end, we're on the same line, or will encounter it, or didn't read to EOL. 
				LD		HL,(LINE_NUMBER)	; If we're on a new line, note it, then clear the EOL marker. 
				INC		HL
				LD		(LINE_NUMBER),HL	; Only increment the line number when we're on a new line so we know what line the next actions occur on. 
				XOR		A
				LD		(EOL),A				; And clear the marker. 
				LD		A,$31				; Set the term counter for 1 so we can see it in DEBUG under PRINTWORD:
				LD		(ENTRYNUMBER),A		; Counter for entries in PRINTWORD. (Debugging assist ) DEBUG
				
PASS1_SAMELINE:

LD	E,$FF
LD	C,Direct_Console_IO
CALL	BDOS
CP	$03
JP	Z,CTRL_C								; Break point. Once per pass.
;OR		A
;CALL	NZ,KEYPRESS

IFNZ	DEBUG
CALL	CRLF
CALL 	PRINTLINE							;Print the line number
ENDIF
							; Next we prepare to write a new instruction... So we clear the Prefix, Postfix and Addpost-flag. 
		XOR A				; Clear out the prefix and postfix for index and textended instructions. 
		LD	(PREFIX),A
		LD	(POSTFIX),A
		LD	(ADDPOST),A

		CALL	GETWORD_TO_WS	; Get a character from the input file but only up to when new whitespace is encountered. 	
		LD		A,(BUFFER)
		LD		HL,OPERATOR
		OR		(HL)
		JR		Z,PASS_NOTHINGTODO	; Just bypass testing for nothing... Obviously... 
				
		CALL	TEST_INSTRUCTIONS	; Tests and executes Directives, Operations and set Labels. 
				
PASS_NOTHINGTODO:
		LD		A,(EOF)
		OR		A
		JR		Z,PASS_LOOP 			; And continue intil EOL is found.			; We're done for the moment once we hit the EOF. Later we'll go onto phase 2. 

		RET							; Or return from the pass call here. 

		
KEYPRESS:
		CP		$03
		JR		Z,CTRL_C
		LD		C,1
		CALL	BDOS
		CP		$03
		JR		Z,CTRL_C
		RET
		
CTRL_C:
		LD		DE,ERR_BREAK
		JP		ERROR_OUT			; Break out - Restore stack, exit. 




EQU:	DB	3,'EQU'		; EQUates label,value
DB:		DB	2,'DB'		; Define Byte(s)
DW:		DB	2,'DW'		; Define Word
BLOCK:	DB	5,'BLOCK'	; Block of code
ORG:	DB	3,'ORG'		; Origin
OFFSET:	DB	6,'OFFSET'	; Offset to add to PC when writing code.
END:	DB	3,'END'		; End of source.
MSG:	DB	3,'MSG'		; Show Message to console. 
SHEX:	DB	4,'SHEX'	; Show HEX value to console.
SDEC:	DB	4,'SDEC'	; Show DEC value to console.
SBIN:	DB	4,'SBIN'	; Show BIN value to console.
IFZ:	DB	3,'IFZ'		; If Zero, compile as per below.
IFNZ:	DB	4,'IFNZ'	; If Not Zero, Compile as per below.
ENDIF:	DB	5,'ENDIF'	; Compile ALL following instructions (end of conditional)
MACRO:	DB	5,'MACRO'	; Define a macro. MACRO MACRO-NAME CODE MEND defines the Macro. MACLD MACRO-NAME inserts it into code. 
MEND:	DB	4,'MEND'	; Macro End. 
MACLD:	DB	5,'MACLD'	; Macro Load. 


; Opcodes;

LD:		DB	2,'LD'
PUSH:	DB	4,'PUSH'
POP:	DB	3,'POP'

EX:		DB	2,'EX'
EXX:	DB	3,'EXX'
LDI:	DB	3,'LDI'
LDIR:	DB	4,'LDIR'
LDD:	DB	3,'LDD'
LDDR:	DB	4,'LDDR'
CPI:	DB	3,'CPI'
CPIR:	DB	4,'CPIR'
CPD:	DB	3,'CPD'
CPDR:	DB	4,'CPDR'

ADD:	DB	3,'ADD'
ADC:	DB	3,'ADC'
SUB:	DB	3,'SUB'
SBC:	DB	3,'SBC'
AND:	DB	3,'AND'
OR:		DB	2,'OR'
XOR:	DB	3,'XOR'
CP:		DB	2,'CP'
INC:	DB	3,'INC'
DEC:	DB	3,'DEC'

DAA:	DB	3,'DAA'
CPL:	DB	3,'CPL'
NEG:	DB	3,'NEG'
CCF:	DB	3,'CCF'
SCF:	DB	3,'SCF'
NOP:	DB	3,'NOP'
HALT:	DB	4,'HALT'
DI:		DB	2,'DI'
EI:		DB	2,'EI'
IM:		DB	2,'IM'


RLCA:	DB	4,'RLCA'
RLA:	DB	3,'RLA'
RRCA:	DB 	4,'RRCA'
RRA:	DB	3,'RRA'
RLC:	DB	3,'RLC'
RL:		DB	2,'RL'
RRC:	DB	3,'RRC'
RR:		DB	2,'RR'
SLA:	DB	3,'SLA'
SRA:	DB	3,'SRA'
SLL:	DB	3,'SLL'	; Not a documente code. Included anyway since it resolves. 
SRL:	DB	3,'SRL'
RLD:	DB	3,'RLD'
RRD:	DB	3,'RRD'


BIT:	DB	3,'BIT'
SET:	DB	3,'SET'
RES:	DB	3,'RES'

JP:		DB	2,'JP'
JR:		DB	2,'JR'
DJNZ:	DB	4,'DJNZ'

CALL:	DB	4,'CALL'
RET:	DB	3,'RET'
RETI:	DB	4,'RETI'
RETN:	DB	4,'RETN'
RST:	DB	3,'RST'

IN:		DB	2,'IN'
INI:	DB	3,'INI'
INIR:	DB	4,'INIR'
IND:	DB	3,'IND'
INDR:	DB	4,'INDR'
OUT:	DB	3,'OUT'
OUTI:	DB	4,'OUTI'
OTIR:	DB	4,'OTIR'
OUTD:	DB	4,'OUTD'
OTDR:	DB	4,'OTDR'

; Assembler Directives. 

TEST_IF:
		LD		DE,ENDIF		; Test end of IF first,
		CALL	TESTLOOP
		JR		Z,ENDIF_DO_ALL
	
		LD		DE,IFZ
		CALL	TESTLOOP
		JR		Z,IFZ_DO	
		
		LD		DE,IFNZ
		CALL	TESTLOOP
		JR		Z,IFNZ_DO

		LD		A,(CONDITIONAL)	; Test for BAD conditional
		OR		A
		RET		Z				; If we're not in a condition, just exit.
TEST_IF_BLOCK:
		POP		HL				; Just force to ignore EVERYTHING until we get a new state.
		RET						

ENDIF_DO_ALL:						; Clear IF based conditional assembly. Just assemble everything. 
		XOR		A
		LD		(CONDITIONAL),A
		POP		HL
		RET
		
IFZ_DO:
		CALL	IF_TEST_VALUE
		JR		Z,ENDIF_DO_ALL		; If condition is met, Do execute Permit if Z.
IF_DONT_DO_ALL:
		LD		A,$FF				; Block if value NZ. 
		LD		(CONDITIONAL),A
		POP		HL
		RET
		
IFNZ_DO:
		CALL	IF_TEST_VALUE
		JR		NZ,ENDIF_DO_ALL		; Permit if NZ	
		JR		IF_DONT_DO_ALL			; Block if value  zero.

IF_TEST_VALUE:						; Test the value. 
		CALL	GETWORD_TO_END
		CALL	EVAL
		LD		HL,(VALUE)
		LD		A,L
		OR		H					; H and L both checked then OR to see if zero or not zero. 
		RET							; And return the value of Z or NZ. 


TEST_EQU:
		LD	DE,EQU
		CALL	TESTLOOP
		JP	Z,SET_EQU			; Set the EQU. 	
		RET

TEST_DB:
		LD	DE,DB
		CALL	TESTLOOP
		JP	Z,SET_DB
		RET

TEST_DW:
		LD	DE,DW
		CALL	TESTLOOP
		JP	Z,SET_DW
		RET

TEST_BLOCK:
		LD		DE,BLOCK
		CALL	TESTLOOP
		JP		Z,SET_BLOCK
		RET

TEST_ORG:
		LD		DE,ORG
		CALL	TESTLOOP
		JP		Z,SET_ORG
		RET

TEST_OFFSET:
		LD		DE,OFFSET
		CALL	TESTLOOP
		RET		NZ
		
		CALL	GETWORD_TO_END
		CALL	EVAL
		LD		HL,(VALUE)
		LD		(PC_OFFSET),HL
		POP		HL
		RET	

TEST_END:
		LD		DE,END
		CALL	TESTLOOP
		JP		Z,SET_END
		RET
			

TEST_MSG:								; Send the remainder of the line to the console,
		LD		DE,MSG
		CALL	TESTLOOP
		RET		NZ						; 

		CALL	GETWORD_TO_END
		LD		A,'$'
		LD		HL,(BUFFER_PTR)
		LD		(HL),A
		LD		DE,BUFFER+1
		CALL	PRINTSTRING
		CALL	CRLF
		POP		HL						; Waste the return address
		RET								; And Return

TEST_SHEX:								; Show Hex. 
		LD		DE,SHEX
		CALL	TESTLOOP
		RET		NZ
		CALL	GETWORD_TO_END
		CALL	EVAL
		LD		HL,(VALUE)
		CALL	PRINTHEX16

		CALL	CRLF
		POP		HL
		RET
		
TEST_MACRO:
		LD		DE,MACRO
		CALL	TESTLOOP
		RET		NZ

		RET

TEST_MEND:
		LD		DE,MEND
		CALL	TESTLOOP
		RET		NZ

		RET

SET_EQU:
		CALL	GETWORD_TO_END			; Get the label.
		CALL	TEST_EOL
		CALL	TEST_COMMA				; Make sure we got another argument and there's a comma as the operator 
										; OK. we should have a label in the buffer.

		LD		A,(PASS)
		CP		$02
		JR		Z,SET_EQU_PASS2			; Pass 2, we need to match existing labels, and change the value. Pass one made sure no reassignment occured. 

		CALL	ADD_LABEL				; Otherwise, we're in pass 1 so add the label. ADD LABEL SETS THE LABEL VALUE ALSO.... only add labels during PASS1. In pass2 this will cause an error.
		DEC		DE
		DEC		DE						; DE is 2 places past the label value. Fix that so it now points to the label value ( which was set by ADD_LABEL to whatever the value in VALUE was )
		JR		SET_EQU_PASS1			; OK, The label is added. It's assumed the value in VALUE is correct and set it, but it might(will!) be wrong.
										; Let's get the label and reassign the value now. This is a wasteful way to do it... But it's not too bad and saves code. 
SET_EQU_PASS2:
		CALL	MATCH_LABEL				; Match the label.
SET_EQU_PASS1:
		PUSH	DE						; Store the destination of the value.
		 CALL	GETWORD_TO_END			; Get the value. The Value might be other labels.... And could be wrong
	   	 CALL	EVAL					; Convert the buffer value to a number in VALUE.
		POP		DE

		LD		A,(VALUE)
		LD		(DE),A
		LD		A,(VALUE+1)
	    INC		DE
		LD		(DE),A		

		POP		HL						; Waste the previous return address since we're done. 
		RET								; And exit.
		

SET_DB:
		CALL	GETWORD_TO_END			; Get the label.

		CALL	EVAL					; Evaluate it. One byte at a time. If there are multiple bytes, it progresses the PC for each byte. 
										; Need to trap multiple lines for single operation later...  so we can't do stuff like ld a,'abc'
										
		LD		A,(VALUE)

		CALL	WRITEBYTE
		
		POP		HL						; Waste the return byte.
		RET								; And exit.

SET_DW:
		CALL	GETWORD_TO_END			; Get the label.
	
		CALL	EVAL					; Evaluate it. One byte at a time. If there are multiple bytes, it progresses the PC for each byte. 
										; Need to trap multiple lines for single operation later...  so we can't do stuff like ld a,'abc'
		
		LD		A,(VALUE)
		CALL	WRITEBYTE
		LD		A,(VALUE+1)
		CALL	WRITEBYTE

		
		POP		HL						; Waste the return byte.
		RET	

SET_BLOCK:
		CALL	GETWORD_TO_END
		CALL	EVAL
		LD		BC,(VALUE)				; Get large counter.
		LD		A,B
		OR 		C
		JR		Z,BLOCK_EXIT			; Zero block size = no bytes.
		
SET_BLOCK_COUNT:
		LD		A,$00					; Just zero the bytes 
		PUSH	BC
		CALL	WRITEBYTE				; Make sure this NEVER uses BC. 
		POP		BC
		DEC		BC
		LD		A,B
		OR		C
		JR		NZ,SET_BLOCK_COUNT
BLOCK_EXIT:
		POP		HL
		RET
		
		

SET_ORG:
		CALL	GETWORD_TO_END			; Get the REST of the line... Remove whitespace up to next operator or EOL. 
										; Need to do this here - It might be a non-eval - eg, a register or otherwise. 					
		CALL	EVAL					; Convert to a number. Or give an error.
		LD		HL,(VALUE)
		LD		(PC),HL					; Store the PC. 

		POP		HL						; Waste the previous return address.
		RET								; And exit. 

SET_END:
		LD		A,$FF
		LD		(EOF),A					; Force an EOF. 
	
		POP		HL
		RET


; Instructions Here
; We want to test instructions and call Writebyte to write them or null-write them or even real-write them. 


ERR_NO_COMMA:
		LD		DE,ERR_NO_COMMA_MESG
		JP		ERROR_OUT

		
ERR_UNEXPECTED_CHARS:
		LD		DE,ERR_UNEXPECTED_CHARS_M
		JP		ERROR_OUT



TEST_INSTRUCTIONS:
		LD		HL,$0000
		LD		(COMMAND),HL
		LD		(COMMAND+2),HL
		LD		(COMMAND+4),HL		; Clear the command buffer where we might assemble the command. 
									; A successful routine should POP HL and RET. 

									
									; First we test for Assembler Directives.
		CALL	TEST_IF				; Test for conditional statements, because DONT DO ANYTHING IF WE'RE IN ONE.
									
									
		CALL	TEST_LABEL			; See if we found a label. 
		CALL	TEST_EQU			; See if it's EQU.
		CALL	TEST_DB				; DB strings. 
		CALL	TEST_DW				; DW values. 
									; These two operations can build the table... We still need to process instruction encoding of the label process
									; to identify the correct PC. 
									; But we don't need to evaluate anything.
		CALL	TEST_BLOCK			; Test blocks. 
		CALL	TEST_ORG			; ORG instructions will affect the code base. Offset doesn't - Offset only changes where the code goes.
		CALL	TEST_MSG			; Messages to the console...  
		CALL	TEST_SHEX			; Show any hex? 
		CALL	TEST_OFFSET			; Are we assembling to a different location?
		CALL	TEST_END			; Have we reached the stated EOF before the physical EOF?




									; Now we test opcodes.
		CALL	TEST_INC			; All INC instructions. 
		CALL	TEST_DEC			; All DEC instructions. 
		CALL	TEST_PUSH			; All PUSH instructions.
		CALL	TEST_POP			; All POP instructions. 
		CALL	TEST_LD				; All LD instructions... Begin with the 8 bit group. Still need to add special and 16 bit groups. 
		CALL	TEST_ARITHMETIC		; All Arithmetic instructions. 
		CALL	TEST_RET			; All RET instructions, including conditional. 
		CALL	TEST_JP				; All JP instructions 
		CALL	TEST_CALL			; All CALL instructions. 
		CALL	TEST_JR				; All Jump Relative instructions. Add DJNZ-D in here also. But we call it separately.
		CALL	TEST_DJNZ			; DJNZ
		CALL	TEST_SINGLE_OPCODE	; All the single opcodes ( no arguments )
		CALL	TEST_RST			; All the RST codes
		CALL	TEST_IN				; All the IN codes. 
		CALL	TEST_OUT			; All the IN codes. 
		CALL	TEST_EX				; Multiple EXCHANGE codes. 
		
		CALL	BITTEST				; All Bit Related Instructions. 
		CALL	TEST_IM				; Test Interrupt Modes.
		
									; We're at the end now..... We should have gotten SOMETHING. We got Nothing. That's not right. 
		LD		DE,ERR_BAD_OPERATOR
		JP		ERROR_OUT			; We should have gotten something... 
						; Should we generate an unknown error here? No. This is just for testing specific input. LABELS are the exception.
						; Nope, we use this as the final fallback. 
;		RET



COMMAND:
	DB	$00,$00,$00,$00,$00,$00,$00,$00		; Where should we construct the command? 1 byte count, 6 bytes buffer. Only really need 4+1 max. 


TEST_LABEL:								; It's not really an instruction, but it's not a directive either. Before we check for any opcodes, see if it's a label. 
				LD		A,(BUFFER)
				CP		$02				; A label must have at least 2 characters... A single letter and a : symbol.
				RET		C				; It's not a label otherwise.
				
				LD		HL,(BUFFER_PTR)	; We've just collected the word, so the buffer pointer is still valid.
				DEC		HL				; And we go back one character to see if there's a ':' which means it's a label. 
				LD		A,(HL)
				CP		':'				; check for a : ( confirms label ).
										; Do I want to sanitize this to A to Z? Or are numbers OK? Or anything
										; that fits...
				RET		NZ				; Return if it wasn't a match.
				
				LD		A,(PASS)
				CP		$02
				JR		Z,TEST_LABEL_EXIT	; We don't do anything with line labels in Pass2. They should all already be set. 
				
				LD		HL,(PC)
				LD		(VALUE),HL		; Move the program counter to "Value". 

				LD		A,(BUFFER)		; The length is 1 character too long since we have a : to eliminate.
				DEC		A
				LD		(BUFFER),A		; Reduce buffer size by 1 character to remove :
				CALL	ADD_LABEL		; And add this value to the label list. It should be a new value. 
TEST_LABEL_EXIT:	
				POP		HL				; Waste the return address.
				RET						; And that's it. If there was a label, we added it to the table. 


IMODE_ERROR:
LD		DE,ERR_IMODE
		JP	ERROR_OUT

TEST_IM:
LD		DE,IM
		CALL	TESTLOOP
		RET		NZ

		
		CALL	TEST_EOL
		CALL	GETWORD_TO_END
		CALL	EVAL

		LD		A,$ED
		LD		(PREFIX),A	; It's an ED prefix character.
		LD		A,$01
		LD		(COMMAND),A	; One character.
		
		LD		A,(VALUE)
		CP		3
		JR		NC,IMODE_ERROR

		LD		B,$46
		OR		A
		JR		Z,IM0
		LD		B,$56
		DEC		A
		JR		Z,IM1
		LD		B,$5E
IM0:
IM1:		
IM2:
		LD		A,B
		LD		(COMMAND+1),A
		JP		WRITE_EXIT			; Write the codes. 

INC_DEC_MASK:	DB	$00

UNKNOWN_REG:								; Error for unknown reg.
		LD		DE,ERR_UNKNOWN_REG
		JP		ERROR_OUT	

BIT_ERROR:
		LD		DE,ERR_BIT
		JP		ERROR_OUT

BITTEST: 
		LD		DE,BIT			; Test the large ops first. BIT RES and SET
		CALL	TESTLOOP
		LD		A,$40
		JR		Z,BIT_DO
		
		LD		DE,RES
		CALL	TESTLOOP
		LD		A,$80
		JR		Z,BIT_DO
		
		LD		DE,SET
		CALL	TESTLOOP
		LD		A,$C0
		JR		Z,BIT_DO

; Shift operations below this line. 		
		LD		DE,RLC			; Then test the shifts. 
		CALL	TESTLOOP
		LD		A,$00
		JR		Z,BITSHIFT

		LD		DE,RRC
		CALL	TESTLOOP
		LD		A,$08
		JR		Z,BITSHIFT

		LD		DE,RL
		CALL	TESTLOOP
		LD		A,$10
		JR		Z,BITSHIFT

		LD		DE,RR
		CALL	TESTLOOP
		LD		A,$18
		JR		Z,BITSHIFT

		LD		DE,sla
		CALL	TESTLOOP
		LD		A,$20
		JR		Z,BITSHIFT

		LD		DE,sra
		CALL	TESTLOOP
		LD		A,$28
		JR		Z,BITSHIFT

		LD		DE,sll
		CALL	TESTLOOP
		LD		A,$30
		JR		Z,BITSHIFT

		LD		DE,srl
		CALL	TESTLOOP
		LD		A,$38
		JR		Z,BITSHIFT		

		RET


BIT_DO:								; Let's do the BIT commands.... Bit Set RES Test Shift etc. 
		LD		(COMMAND+2),A		; Store start of command. 

		CALL	TEST_EOL			; Make sure we're not at EOL
		CALL	GETWORD_TO_END

		CALL	TEST_COMMA			; Make sure there's a comma
		CALL	TEST_EOL
		
		XOR		A					; Because we know it's a comma, and that causes issues for EVAL
		LD		(OPERATOR),A		; Clear it. Just leave the value. There should be NO other operators in this case. 

		CALL	EVAL				; SHOULD just be a number or a token. 
		LD		A,(VALUE)			; Equates to a binary value
		CP		$08					; Must be less than 8
		JP		NC,BIT_ERROR		;  We MUST have a value from 0 to 7. 
		
		OR		A
		RLA
		RLA
		RLA
		LD		HL,COMMAND+2
		OR		(HL)				; Mix in the bit number.		
									; THEN JUST DROP THROUGH.s
BITSHIFT:							; DONT SEPARATE THIS FROM THE ABOVE. THere's a FALL THROUGH MECHANISM.
		LD		(COMMAND+2),A		

		CALL	GETWORD_TO_END
		CALL	TEST_SINGLEREG
		JP		NC,UNKNOWN_REG				; Only abcdehl(HL)
		LD		HL,COMMAND+2
		OR		(HL)
		LD		(HL),A						; Store instruction
		LD		A,$02
		LD		(COMMAND),A					; Two bytes... CB is NOT prefix. 
		LD		A,$CB
		LD		(COMMAND+1),A				; Install CB  instruction.
		
		JP		WRITE_EXIT




TEST_INC:
		LD		DE,INC						; Test the INC instruction
		CALL	TESTLOOP
		RET		NZ		; Return if it was NOT INC.

		CALL	GETWORD_TO_END	; Get the next part. Should be a register or register pair.	

		CALL	TEST_SINGLEREG	; Is it ABCDEHL(HL)? This is for the 64 bytes of LD A,B LD B,C etc... 
		LD		B,%0000 0100
		JP		C,INC_DEC_REG8		; Change A Register. 

		CALL	TEST_DOUBLEREG_SP	; SP version of doublereg test.
		LD		B,%0000 0011
		JP		C,INC_DEC_REG16
		
		JP		UNKNOWN_REG


TEST_DEC:
		LD		DE,DEC						; Test the INC instruction
		CALL	TESTLOOP
		RET		NZ		; Return if it was NOT INC.

		CALL	GETWORD_TO_END	; Get the next part. Should be a register or register pair.	

		CALL	TEST_SINGLEREG	; Is it ABCDEHL(HL)? This is for the 64 bytes of LD A,B LD B,C etc... 
		LD		B,%0000 0101
		JP		C,INC_DEC_REG8		; Change A Register. 

		CALL	TEST_DOUBLEREG_SP	; SP version of doublereg test.
		LD		B,%0000 1011
		JP		C,INC_DEC_REG16
		
		JP		UNKNOWN_REG


INC_DEC_REG16:
		OR		A
		RLA							; 1 more since it has to go up a nibble. 

INC_DEC_REG8:						; We have a command like INC [A,B,C,D,E,H,L,(HL)] Or DEC. Or might be HL or SP... 
									; Enter with A as the register number and B as the Instruction Mask to add to it. 
		OR		A
		RLA
		RLA
		RLA							; Move command

GENERAL_1BYTE:
		OR		B					; Add command prefix - Set bit 4... 04,0C,14,1C etc. 
		LD		(COMMAND+1),A		; Mix in INC. 
		LD		A,1
		LD		(COMMAND),A			; Preset command for 1 byte.  	
		CALL	WRITECODE			; Write the code buffer. 
		POP		HL					; Waste return address.
		RET							; And exit. 

AREG:	DB	1,'A'
SPREG:	DB	2,'SP'
AFREG:	DB	2,'AF'
HLREG:	DB	2,'HL'
DEREG:	DB	2,'DE'
BCREG:	DB	2,'BC'

TEST_DOUBLEREG_AF:
		LD		DE,AFREG
		CALL	TESTLOOP
		LD		B,$03
		JR		Z,GOT_DOUBLEREG
		JR		TEST_DOUBLEREG_COMMON	; And bypass the SP test depending on which entry point is called. 

TEST_DOUBLEREG_SP:					; If carry is set, we got a match. Number of match is in A. 
		LD		DE,SPREG
		CALL	TESTLOOP
		LD		B,$03				; In reverse so we can get efficient with SP and AF.
		JR		Z,GOT_DOUBLEREG		;
		

TEST_DOUBLEREG_COMMON:	
		LD		DE,HLREG
		CALL	TESTLOOP
		LD		B,$02
		JR		Z,GOT_DOUBLEREG
		
		LD		DE,DEREG
		CALL	TESTLOOP
		LD		B,$01
		JR		Z,GOT_DOUBLEREG

		LD		DE,BCREG
		CALL	TESTLOOP
		LD		B,$00
		JR		Z,GOT_DOUBLEREG
	
		OR		A
		RET							; It's an error. Clear the carry flag and return 
						
GOT_DOUBLEREG:
		LD		A,B
		SCF
		RET






TEST_PUSH:
		LD		DE,PUSH				; Test the PUSH instruction
		CALL	TESTLOOP
		RET		NZ					; Return if it was NOT PUSH.

		CALL	GETWORD_TO_END		; Get the next part. Should be a register or register pair.	

		CALL	TEST_DOUBLEREG_AF	; SP version of doublereg test.
		LD		B,%1100 0101
		JP		C,INC_DEC_REG16		; We can use the same one as INCDEC.

		JP		UNKNOWN_REG


TEST_POP:
		LD		DE,POP				; Test the PUSH instruction
		CALL	TESTLOOP
		RET		NZ					; Return if it was NOT POP

		CALL	GETWORD_TO_END		; Get the next part. Should be a register or register pair.	

		CALL	TEST_DOUBLEREG_AF	; SP version of doublereg test.
		LD		B,%1100 0001
		JP		C,INC_DEC_REG16		; We can use the same one as INCDEC.

		JP		UNKNOWN_REG


MISSING_ARGUMENT:
		LD		DE,ERR_MISS_ARGUMENT
		JP		ERROR_OUT


TEST_RST:							; Test RST commands
		LD		DE,RST
		CALL	TESTLOOP
		RET		NZ

									; OK, we have a rst.
		LD		A,(EOL)
		OR		A
		JR		NZ,MISSING_ARGUMENT	
									; And it's not the EOL or EOF. 
		CALL	GETWORD_TO_END
		CALL	EVAL				; We need a number next.
	
		LD		C,$08
		LD		A,(VALUE)
		LD		L,A
		LD		A,$00
		LD		B,%1100 0111
		CP		L				; RST 00
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 08
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 10
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 18
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 20
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 28
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 30
		JP		Z,GENERAL_1BYTE
		ADD		A,C
		CP		L				; RST 38
		JP		Z,GENERAL_1BYTE

		LD		DE,ERR_RST
		JP		ERROR_OUT		


		
		










		
TEST_LD:
		LD		DE,LD						; Test the LD instruction
		CALL	TESTLOOP
		RET		NZ		; Return if it was NOT LD.
		CALL	TEST_EOL	 ; We should NEVER get an EOL before the next argument. 

		CALL	GETWORD_TO_END	; Get the next part.
		CALL	TEST_EOL		; ALL LD commands will have more - If we're at EOL, Error. 
	
		CALL	TEST_SINGLEREG	; Is it ABCDEHL(HL)? This is for the 64 bytes of LD A,B LD B,C etc... 
		JP		C,LD_SINGLEREG		; Single Register Operation.

		CALL	TEST_DOUBLEREG_SP	; Then do something... This will be 01, 11, 21, 31.
		JP		C,LD_DOUBLEREG

		LD		DE,BRACKETBC
		CALL	TESTLOOP		; Look for (BC) 
		JP		Z,LD_BC_A
		
		LD		DE,BRACKETDE
		CALL	TESTLOOP
		JP		Z,LD_DE_A
		
		LD		DE,RREG
		CALL	TESTLOOP
		JP		Z,LD_R_A
		
		LD		DE,IREG
		CALL	TESTLOOP
		JP		Z,LD_I_A

		LD		A,(BUFFER+1)
		CP		'('					; Could it be (NN)? or (BC) or (DE)? 
		JP		Z,LD_LOCATION	
		
		JP		UNKNOWN_REG


ATHL:		DB	4,'(HL)'

LD_BC_A:
		CALL	CHECK_A			; We set 01 into (COMMAND) here in CHeck A.
		LD		A,$02
		LD		(COMMAND+1),A
		JP		WRITE_EXIT

LD_DE_A:
		CALL	CHECK_A
		LD		A,$12
		LD		(COMMAND+1),A
		JP		WRITE_EXIT

LD_R_A:
		CALL	CHECK_A
		LD		A,$4F
		JR		LD_IR_COMMON
LD_I_A:
		CALL	CHECK_A
		LD		A,$47

LD_IR_COMMON:
		LD		(COMMAND+1),A
		LD		A,$ED
		LD		(PREFIX),A
		LD		A,$01				; 1 byte in command buffer
		LD		(COMMAND),A			; I might write too many otherwise. 

		JP		WRITE_EXIT
		
CHECK_A:
		CALL	GETWORD_TO_END		; Get the next argument.
		LD		A,(BUFFER)
		DEC		A
		JP		NZ,UNKNOWN_REG		; It MUST be 1 char.
		LD		A,(BUFFER+1)
		CP		'A'
		JP		NZ,UNKNOWN_REG		; It MUST be 'A'
		LD		A,$01
		LD		(COMMAND),A			; And start the command count as 1.
		RET

LD_LOCATION:						;Could only be (NN)

		CALL	MATCH_CLOSE_BRACKET ; EVAL Get's called during routine. 
									; The value we want is in VALUE. 
	

		LD		A,(OPERATOR)		; We are expecting a comma SOMETIMES. If we didn't get one, ask for it now. 
		CP		','
		CALL	NZ,GETWORD_TO_END		
		
		CALL	TEST_COMMA			; If we wanted it, make sure we got it.
		CALL	TEST_EOL			; And that we didn't read to EOL yet. 
	
		CALL	GETWORD_TO_END		; Now get the second argument. 
	
		LD		DE,AREG
		CALL	TESTLOOP
		JR		Z,LD_NN_A

		LD		DE,HLREG			; Note - This masks HL from below, which supports IX/IY 
		CALL	TESTLOOP
		JR		Z,LD_NN_HL

		CALL	TEST_DOUBLEREG_SP	; Get the double register destination. 
		JP		NC,UNKNOWN_REG
	
		OR		A
		RLA
		RLA
		RLA
		RLA
		OR	%0100 0011				; Get instruction. Note HL state was addressed in previous instruction.
		LD		(COMMAND+1),A
		
		LD		A,$ED
		LD		(PREFIX),A
LD_LOCATION_NOED:
		LD		A,$03				; 3 bytes.
		LD		(COMMAND),A
		
		LD		HL,(VALUE)
		LD		(COMMAND+2),HL
		
		JP		WRITE_EXIT
		
LD_NN_A:
		LD		A,$32
		LD		(COMMAND+1),A
		JR		LD_LOCATION_NOED	
		
LD_NN_HL:
		LD		A,$22
		LD		(COMMAND+1),A
		JR		LD_LOCATION_NOED	
			
LD_DOUBLEREG:
		OR		A
		RLA
		RLA
		RLA
		RLA
		OR	%0000 0001
		LD	(COMMAND+1),A			; COMMAND+1 now holds the appropriate command.
		LD		A,$03
		LD		(COMMAND),A			; 3 bytes to command.
		
		CALL	GETWORD_TO_END		; Now get the value to write to HL. Might be a formula. Might be a  number. Might be a label. It's NOT in brackets. 

		LD		A,(BUFFER+1)
		CP		'('					; Check if it's (
		JR		Z,LD_DOUBLEREG_BRACKET

		LD		DE,HLREG
		CALL	TESTLOOP
		JR		Z,LD_SPHL			; Special Case. 

		CALL	EVAL

		LD		HL,(VALUE)
		LD		(COMMAND+2),HL
		JP		WRITE_EXIT

LD_SPHL:							; LD HL,SP
		LD		A,$F9
		LD		(COMMAND+1),A
		LD		A,$01
		LD		(COMMAND),A
		JP		WRITE_EXIT		

LD_DOUBLEREG_BRACKET:
		CALL	MATCH_CLOSE_BRACKET	;Test for close bracket and then convert to a number if possible. 
		LD		A,(COMMAND+1)
		CP		$21
		JR		NZ,LD_DOUBLEREG_BRACKET_BCDESP	; Drop through for HL only. 
		
		LD		A,$2A						; Special case for HL - don't use the ED
		LD		(COMMAND+1),A
DOUBLEREG_BRACKET_CONT:
		LD		HL,(VALUE)
		LD		(COMMAND+2),HL	; 3 byte. 
		JP		WRITE_EXIT			;
		
		
; Now do checks for ED commands - Extended 		
LD_DOUBLEREG_BRACKET_BCDESP:
		AND		%0011 0000		; Save just the table location upper nibble
		OR		%0100 1011		; 4B upwards under ED table.
		LD		(COMMAND+1),A	; Set the command for ED set
		LD		A,$ED
		LD		(PREFIX),A		; Set the prefix.
		JR		DOUBLEREG_BRACKET_CONT

LD_FIRST_ARG:	DB	$00				; Just saves a little time later. I could probably remove it. 

LD_SINGLEREG:						; We have a command like LD [A,B,C,D,E,H,L,(HL)] 

		LD		(LD_FIRST_ARG),A	; Store the initial value of A. 
		OR		A
		RLA
		RLA
		RLA							; Move command
		OR		%01000000			; Add command prefix
		LD		(COMMAND+1),A		
		LD		A,1
		LD		(COMMAND),A			; Preset command. 
		
		CALL	GETWORD_TO_END	; Get the rest of the argument.

;		LD		A,(OPERATOR)
;		OR		A
;		JP		NZ, ERR_UNEXPECTED_CHARS	; Should be no operators or anything else.
		; Nope - There might be operators.
		
		

		CALL	TEST_SINGLEREG
		JR		NC,LD_SINGLEREG_OTHER		; It's probably a LD A SOMETHING or maybe a weird one like I or R, or maybe LD B,n or similar. 
									; What do I do if it's not a register? Figure out what is next.
		LD		HL,COMMAND+1
		OR		(HL)				;  Mix it in
		LD		(HL),A				; And write it. - This covers 64 instructions from 01000000 to 01111111

		CALL	WRITECODE			; Write the code buffer. 
		POP		HL					; Waste return code since we finished processing the instruction.
		RET							; And exit. 

IREG:	DB	1,'I'
RREG:	DB	1,'R'
BRACKETBC:	DB	4,'(BC)'
BRACKETDE:	DB	4,'(DE)'

LD_SINGLEREG_OTHER:
			; Deal with LD R,n and LD A,I and LD A,R here.  and LD A,n 	

		; Ignore what's in A now. The second argument is in BUFFER and the only valid first argument is "A"
		
		LD		A,(LD_FIRST_ARG)
		CP		$07
		JP		NZ,LD_SINGLE_EVAL	; If it's not 'A', then the single register options are gone except r,n - so let's go there. 

		LD		A,$01
		LD		(COMMAND),A			; It's most likely a 1 byte...
		
		LD		DE,IREG	
		CALL	TESTLOOP
		JR		Z,LD_SINGLE_AI
		
		LD		DE,RREG
		CALL	TESTLOOP
		JR		Z,LD_SINGLE_AR
		
		LD		DE,BRACKETBC
		CALL	TESTLOOP
		JR		Z,LD_SINGLE_ABC
		
		LD		DE,BRACKETDE
		CALL	TESTLOOP
		JR		Z,LD_SINGLE_ADE
		
		LD		A,(BUFFER+1)
		CP		'('
		JP		Z,LD_A_BRACKETVALUE

LD_SINGLE_EVAL:			; Maybe it's a value. Let's try to evaluate it and process it like that. 
		CALL	EVAL
		LD		A,$02	; Two bytes tot his.
		LD		(COMMAND),A
		LD		A,(COMMAND+1)
		OR		%0000 0110	; Set for LD r,n = add 6
		AND		%0011 1111	; Mask for lower commands
		LD		(COMMAND+1),A
		
		LD		A,(VALUE)
		LD		(COMMAND+2),A
		
WRITE_EXIT:
		CALL	WRITECODE		; And write it. Assume any failures will drop out via the EVAL routine. 
						; Here's where we look at things like LD A,(NNNN). 
		POP		HL		; Waste the return and exit. 
		RET
		
LD_SINGLE_AI:	
		LD		A,$57
		LD		(COMMAND+1),A
		LD		A,$ED
		LD		(PREFIX),A
		JR		WRITE_EXIT
		
LD_SINGLE_AR:
		LD		A,$5F
		LD		(COMMAND+1),A
		LD		A,$ED
		LD		(PREFIX),A
		JR		WRITE_EXIT
		
LD_SINGLE_ABC:
		LD		A,$0A
		LD		(COMMAND+1),A
		JR		WRITE_EXIT

LD_SINGLE_ADE:
		LD		A,$1A
		LD		(COMMAND+1),A
		JR		WRITE_EXIT

LD_A_BRACKETVALUE:
		CALL	MATCH_CLOSE_BRACKET	;Test for close bracket and then convert to a number if possible. 
		LD		A,$03
		LD		(COMMAND),A
		LD		A,$3A
		LD		(COMMAND+1),A
		LD		HL,(VALUE)
		LD		(COMMAND+2),HL	; 3 byte. 
		JR		WRITE_EXIT

MATCH_CLOSE_BRACKET:			; Note we have to check if there's a ) and if yes, remove it and EVAL. If not, Set Special Operator ')' and EVAL.
								; Strip ( and ) from result.  Note, we may or may not get the , operator. 

		CALL	SHUFFLE_BUFFER
		LD		HL,BUFFER
		LD		E,(HL)
		LD		D,$00
		ADD		HL,DE			; Get the last character in the buffer. Check if it's a bracket, or whether we use the operator next. 
		LD		A,(HL)
		CP		')'
		JR		Z,MATCH_CLOSE_BRACKET1
		LD		A,')'
		LD		(SPECIAL_OPERATOR),A		; EVAL with ) removal. 
;;;		LD		A,(OPERATOR)				; Why do I care about the operator???? It's a Plus most likely. I can leave it in OPERATOR. Eval knows where to find it. 
		CALL	EVAL						; Eval and return -

		RET

MATCH_CLOSE_BRACKET1:
		LD		A,(BUFFER)
		CP		2							; Must be at least 2 characters - One is a )
		JP		C,UNKNOWN_REG				; At this point, we have nothing to evaluate - Unknown reg... Or Argument. Who knows. 
		DEC		A
		LD		(BUFFER),A					; Buffer count is one less. 
		LD		(HL),$00					; Clear the last character.
		LD		A,(OPERATOR)
		LD		(MATCH_CLOSE_OPERATOR),A
		XOR		A
		LD		(OPERATOR),A				; DON'T LEAVE an operator in EVAL, or it will EVALUATE IT AS A SERIES OF EVALUATIONS.
											; This might read past the next argument unintentionally.

		CALL	EVAL						; Eval and exit. 
		LD		A,(MATCH_CLOSE_OPERATOR)
		LD		(OPERATOR),A		

		RET

MATCH_CLOSE_OPERATOR:	DB	$00		; Temp place for operator if we manipulate it. 

SHUFFLE_BUFFER:
		LD		A,(BUFFER)
		OR		A
		JR		Z,SHUFFLE_ERROR
		LD		DE,BUFFER+1
		LD		HL,BUFFER+2
		LD		A,(BUFFER)
		LD		C,A
		LD		B,$00
		LDIR
		LD		A,(BUFFER)
		DEC		A
		LD		(BUFFER),A
		RET
SHUFFLE_ERROR:
		LD		DE,EVAL_INTERNAL_ERROR
		JP		ERROR_OUT



TEST_SINGLEREG:						; If carry is set, we got a match. Number of match is in A. 
		LD		A,(BUFFER)			; Single character tests below.
		CP		$01
		JR		NZ,TEST_SINGLEREG_LONG	; If there's more than one character, it's not abcdehl... Try other codes. 

		LD		HL,BUFFER+1			; Location of carrier
		LD		B,$07				; A is 7ths result.
		LD		A,'A'
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;A - Do this first, because we LD A,x or LD x,A a LOT. 
		INC		A
		LD		B,$00
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;B
		INC		A
		INC		B
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;C
		INC		A
		INC		B
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;D
		INC		A
		INC		B
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;E
		LD		A,'H'
		INC		B
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;H
		LD		A,'L'
		INC		B
		CP		(HL)
		JR		Z,TEST_SINGLEREG_MATCH	;L
		
		OR		A
		RET							; It's an error. Clear the carry flag and return 
						

TEST_SINGLEREG_LONG:				; Look for (HL) 
		LD		DE,ATHL
		CALL	TESTLOOP
		LD		B,$06
		JR		Z,TEST_SINGLEREG_MATCH 	;(HL)
		
		OR		A					; Clear Carry Flag. Who cares what is in it. 
		RET							; It wasn't ABCDEHL(HL)

TEST_SINGLEREG_MATCH:
		LD		A,B					; Recover A as the result. 
		SCF							; Set Carry Flag to indicate we got a match and return the value in A. 
		RET
		
NZ: DB	2,'NZ'	; Not Zero
Z:	DB	1,'Z'	; Zero
NC:	DB	2,'NC'	; No Carry
C:	DB	1,'C'	; Carry
PO:	DB	2,'PO'	; Parity Odd
PE:	DB	2,'PE'	; Parity Even
P:	DB	1,'P'	; Positive
M:	DB	1,'M'	; Minus
		
TEST_CONDITION:						; Look for a condition - eg, Z NZ, C, NZ.
		LD		DE,NZ
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$C0				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,Z
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$C8				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,NC
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$D0				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,C
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$D8				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,PO
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$E0				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,PE
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$E8				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,P
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$F0				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!

		LD		DE,M
		CALL	TESTLOOP			; Does it match the buffer?
		LD		A,$F8				; Set the match value in case...
		JR		Z,TEST_CONDITION_MATCH	;We got a match!		
		
		OR		A					; No Match. Clear Carry Flag. 

		RET

TEST_CONDITION_MATCH:
		SCF
		RET
		
SHOW_ERR_RET_COND:
		LD		DE,ERR_RETURN_CONDITION
		JP	ERROR_OUT


TEST_RET:							; Test for Return Statement.
		LD		DE,RET
		CALL	TESTLOOP
		RET		NZ					; Is it a ret? Return otherwise.

		LD		A,$01
		LD		(COMMAND),A
		LD		A,$C9				; Return RET
		LD		(COMMAND+1),A		; Start with a basic return. 
		
		LD		A,(EOL)				; First, check if we're already at the EOL since it could be a command ending the line.
		OR		A
		JR		NZ,TEST_RET_END		; EOL means we're done. 

		CALL	GETWORD_TO_END		; Get the condition which should appear next. 
		LD		A,(BUFFER)
		OR		A					; Test for zero. 
		JR		Z,TEST_RET_END		; Means it was just a normal return as there was no return value.

		CALL	TEST_CONDITION		; Was it a condition?
		LD		DE,ERR_RETURN_CONDITION
		JP		NC,ERROR_OUT		; We can error out here if there was something other than a condition code. 
									; If we get here, there was no error, and the condition code is in A.
		LD		(COMMAND+1),A		; And it happens to be the exact opcode, No modification. Update the code. 

TEST_RET_END:						; Sometimes we omit some of the steps above and jump straight out. 
		CALL	WRITECODE			; Write the current code buffer 	
		POP		HL					; Waste the return address so we don't check any other instructions. 
		RET							; And exit the routine. 


TEST_JP_BAD:
		LD		DE,ERR_JP_BAD
		JP		ERROR_OUT

	
CALL_JUMP_MASK:	DB	%00000010			; 00000010 JP and 00000100 for call. 
		
TEST_JP:							; Test for JUMP instructions.. Like RET but with 2 added to them, and a two-byte destination value. Except we process the JP by itself LAST since it will be picked up.
		LD		DE,JP
		CALL	TESTLOOP
		RET		NZ					; Is it a JP? Return otherwise.
		
		LD		A,%0000 0010		; JUMP MASK
		LD		(CALL_JUMP_MASK),A	; Save the mask.
		LD		A,$03				; And it's going to be three bytes.
		LD		(COMMAND),A			; Record this now. It will be, or it will error. 

		CALL	GETWORD_TO_END		; JUMP is always followed by something. Either a condition or a value.
		LD		A,(OPERATOR)
		CP		','					; Conditions are always followed by a comma.
		JR		NZ,TEST_JP_VALUE	; Might be a value? Let's jump to the value check.

TEST_CALL_ENTRY:					; We can re-enter here for call. The code is the same. 
		CALL	TEST_CONDITION		; Was it a condition?
		LD		DE,ERR_RETURN_CONDITION
		JP		NC,ERROR_OUT		; We can error out here if there was something other than a condition code. 
									; If we get here, there was no error, and the condition code is in A.

		LD		HL,CALL_JUMP_MASK	; Add the missing bits to A.
		OR		(HL)				; Move along to the JUMP opcodes since we use the same test routine for return on condition.
		LD		(COMMAND+1),A		; Update the opcode with the correct one ( either jump or call )

		CALL	GETWORD_TO_END		; Now get the jump target.

TEST_JP_NO_CONDITION:
		CALL	EVAL				; Evaluate it as a number. 
		LD		A,(OPERATOR)		; Make sure there's no operator.
		OR		A
		JR		NZ,TEST_JP_BAD		; Bad Jump address. ( Operator found after address )
		LD		A,(BUFFER)
		OR		A
		JR		Z,TEST_JP_BAD		; No actual jump address. 		

		LD		HL,(VALUE)
		LD		(COMMAND+2),HL		; Store the destination address
		
		CALL	WRITECODE			; And write it
		POP		HL					; Discard the original return address
		RET							; And exit. 

TEST_JP_VALUE:						; Sometimes we omit some of the steps above and jump straight out. 
									; But.... There's also Jump HL, Jump (IX) and JUMP(IY)
		LD		DE,ATHL				; Is it JP (HL)?
		CALL	TESTLOOP			; Check it.
		JR		Z,TEST_JP_HL		; If it was the HL exception, branch here. Otherwise let's preset for a value now.
		
		LD		A,$C3
		LD		(COMMAND+1),A		; Just a straight JP nnnn
		JR		TEST_JP_NO_CONDITION	; Lets just go straight to the address. 
		
TEST_JP_HL:							; Special case - this is for HL.
		LD		A,$E9
		LD		(COMMAND+1),A
		LD		A,$01
		LD		(COMMAND),A
		CALL	WRITECODE			; Write it. 
		POP		HL					; Waste the return
		RET							; Exit.

		
		
TEST_CALL:							; Test for CALL instructions.. Like RET but with 4 added to them, and a two-byte destination value. Except we process the JP by itself LAST since it will be picked up.
		LD		DE,CALL
		CALL	TESTLOOP
		RET		NZ					; Is it a CALL? Return otherwise.

		LD		A,%0000 0100		; CALL MASK
		LD		(CALL_JUMP_MASK),A	; Save the mask.
		LD		A,$03				; And it's going to be three bytes.
		LD		(COMMAND),A			; Record this now. It will be, or it will error. 

		CALL	GETWORD_TO_END		; JUMP is always followed by something. Either a condition or a value.
		LD		A,(OPERATOR)
		CP		','					; Conditions are always followed by a comma.
		JR		NZ,TEST_CALL_VALUE	; Might be a value? Let's jump to the value check.

		JR		TEST_CALL_ENTRY		; The remaining code is the same for CALL and JUMP. 


TEST_CALL_VALUE:					; Sometimes we omit some of the steps above and jump straight out. 
									; There's no CALL (HL) so we don't test for it in call.	
		LD		A,$CD				; CD is the code for CALL nnnn
		LD		(COMMAND+1),A		; Just a straight CALL nnnn
		JR		TEST_JP_NO_CONDITION	; Lets just go straight to the address. Same as with Jump JP so reuse the same code and entry point. . 

TEST_EOL:
		PUSH	AF					; Store the result in case we don't fail here.
		LD		A,(EOL)
		OR		A
		JP		NZ,MISSING_ARGUMENT
		POP		AF
		RET
		
		
TEST_DJNZ:							; Has connections to Jump Relative.
		LD		DE,DJNZ
		CALL	TESTLOOP
		RET		NZ
		CALL	TEST_EOL			; We should NEVER have an EOL - there's always a destination.
		
		LD		A,$10
		LD		(COMMAND+1),A
		CALL	GETWORD_TO_END
		JR		TEST_JR_DESTINATION
		

TEST_JR:							; Let's test relative here.
		LD		DE,JR
		CALL	TESTLOOP
		RET		NZ					; Is it a JP? Return otherwise.
		CALL	TEST_EOL			; We should NEVER have an EOL straight after JR. There will ALWAYS be another argument. 

		CALL	GETWORD_TO_END		; JUMP is always followed by something. Either a condition or a value.
		LD		A,(OPERATOR)
		CP		','					; Conditions are always followed by a comma.
		JR		NZ,TEST_JR_VALUE	; Might be a value? Let's jump to the value check.		
		
		CALL	TEST_CONDITION
		JP		NC,SHOW_ERR_RET_COND	; If there's no condition, see if we got a value or a label?
									; Returned conditions in a are;
									; $C0 = NZ
									; $C8 = Z
									; $D0 = NC
									; $D8 = C
									; Anything higher is an error.									
		CP	$D9						; Higher...
		JP		NC,SHOW_ERR_RET_COND	; The condition may be valid, but not for JR.
		
		AND	%0001 1000 				; Just mask the jump, and bring it back to zero...
		OR	%0010 0000				; And JRs are $20 $28 $30 $38
		
		LD	(COMMAND+1),A
		
		CALL	GETWORD_TO_END		; Now get displacement. 
		JR		TEST_JR_DESTINATION



TEST_JR_VALUE:						; Just a straight command is 18... 
		LD		A,$18
		LD		(COMMAND+1),A		; Set up for JR d
TEST_JR_DESTINATION:	
		LD		A,(BUFFER)
		OR		A
		JR		Z,JUMP_NOWHERE		; We need at least a value... Nothing to do is zero, but it's likely an error.
		CALL	EVAL				; But if we have something to evaluate, then evaluate it.
		LD		HL,(VALUE)			; What is the absolute place to go?
JUMP_RELATIVE:						; Enter into this part to determine the relative jump vector to write. 						
									; HL is the absolute place. PC is the instruction vector. 
		LD		DE,(PC)				; DE is now the PC.
		INC		DE
		INC		DE					; Remember that the PC will have moved two locations by the time the instruction is read. 
		OR		A
		SBC		HL,DE				; Subtract the PC from the Destination.
		LD		A,L
		LD		(COMMAND+2),A		; Store the relative displacement as a signed 7 bit integer.
									; Might have to change it a little here to make up for not moving the PC onwards.
									; Store the result for the moment.
									; Now let's bounds-check the jump ( for out of range. )
		LD		DE,$0080			; Let's move it up into an 8 bit value.
		ADD		HL,DE				
		LD		A,H
		OR		A					; Is it all zero?
		JR		NZ,JUMP_RELATIVE_OUT	 ; Fail out with out of bounds error.
									
JUMP_RELATIVE_OK:									
		LD		A,$02
		LD		(COMMAND),A
		
		CALL	WRITECODE			; Write it. 
		
		POP		HL					; Discard former return address
		RET							; And exit. 


JUMP_RELATIVE_OUT:
	LD		A,(PASS)
	CP		$01
	JR		Z,JUMP_RELATIVE_OK		; Let's not go calling issues for PASS 1 since we don't know the destinations yet. 

	LD		DE,ERR_OUT_OF_BOUNDS
	JP		ERROR_OUT


JUMP_NOWHERE:
	LD		DE,ERR_JUMP_NOWHERE
	JP		ERROR_OUT


		
;;; Arithmetic testing.
;ADD:	DB	3,'ADD'
;ADC:	DB	3,'ADC'
;SUB:	DB	3,'SUB'
;SBC:	DB	3,'SBC'
;AND:	DB	3,'AND'
;OR:	DB	2,'OR'
;XOR:	DB	3,'XOR'
;CP:	DB	2,'CP'

TEST_ARITHMETIC:

		LD		DE,ADD
		CALL	TESTLOOP
		LD		A,$80				; Prefix for ADD
		JP		Z,SET_ADD			

		LD		DE,ADC
		CALL	TESTLOOP
		LD		A,$88				; Prefix for ADC
		JP		Z,SET_ADC			

		LD		DE,SUB
		CALL	TESTLOOP
		LD		A,$90				; Prefix for SUB
		JP		Z,SET_SUB			

		LD		DE,SBC
		CALL	TESTLOOP
		LD		A,$98				; Prefix for SBC
		JP		Z,SET_SBC	

		LD		DE,AND
		CALL	TESTLOOP
		LD		A,$A0				; Prefix for AND
		JP		Z,SET_AND			

		LD		DE,XOR
		CALL	TESTLOOP
		LD		A,$A8				; Prefix for XOR
		JP		Z,SET_XOR

		LD		DE,OR
		CALL	TESTLOOP
		LD		A,$B0				; Prefix for OR
		JP		Z,SET_OR			

		LD		DE,CP
		CALL	TESTLOOP
		LD		A,$B8				; Prefix for CP
		JP		Z,SET_CP

		RET							; Wasn't an arithmetic match. Just return so we can check other opcodes.  
		
SET_ADD:	
SET_ADC:
SET_SBC:							; Group these together as the format is A,<target>
		LD		(COMMAND+1),A		; Set the prefix into the command.

		CALL	GETWORD_TO_END		; We are not expecting a register then 'A' unless its HL
		
		LD		A,(OPERATOR)
		CP		','
		JP		NZ,MISSING_COMMA 	;	All ADD commands MUST have a comma.

		LD		DE,HLREG
		CALL	TESTLOOP			; Is it HL?
		JR		Z,TEST_ADD_16		; If it is, then maybe let's do it differently. Note- THIS CAN BE IX/IY also. 

		LD		A,(BUFFER)			; Make sure it's just 1 character now since it wasn't HL.
		CP		1
		JP		NZ,ERR_UNEXPECTED_CHARS	; Didn't get what we expected.

		LD		A,(BUFFER+1)		; Make sure it's an A.
		CP		'A'
		JP		NZ,ERR_UNEXPECTED_CHARS

		XOR		A					; Clear A so we don't corrupt the command when we fall through. (we already wrote it )
SET_SUB:
SET_AND:
SET_XOR:
SET_OR:
SET_CP:								; Group these together as single targets
		LD		HL,COMMAND+1		; Or A with the command, which changes dependong on the entry point. 
		OR		(HL)
		LD		(HL),A				; Make sure the prefix is in place in case we came in via the above routines. 
		LD		A,$01
		LD		(COMMAND),A			; 1 character most likely at this point. We can address later if required. 

		CALL	GETWORD_TO_END		;

		CALL	TEST_SINGLEREG		; Look for ABCDEHL(HL)
		JP		NC,SET_ARITHMETIC_VALUE	; If it's not a register, it should be a value.
		LD		HL,COMMAND+1
		OR		(HL)
		LD		(HL),A				; Update by adding the correct register.

		CALL	WRITECODE			; Write the bytes.
		POP		HL					; Waste the return adress so we don't check anything else. 
		RET							; And we're done.
		
SET_ARITHMETIC_VALUE:
		CALL	EVAL				; it SHOULD be a value.
		LD		A,(COMMAND+1)
		OR		%01000110			; Move it up a bit and drop into the hl column.
		LD		(COMMAND+1),A		; Save the new opcode. 
		LD		A,(VALUE)
		LD		(COMMAND+2),A
		LD		A,2
		LD		(COMMAND),A			; Update the counter to two bytes. 

		CALL 	WRITECODE			; Write the opcode and the extended value.
		POP		HL					; Waste the return address. 
		RET							; And exit the opcode scanning routine. 


TEST_ADD_PREFIXERROR:
		LD		DE,ERR_PREFIX
		JP		ERROR_OUT


TEST_ADD_16:
		CALL	GETWORD_TO_END		; Get the next registers.
		CALL	TEST_DOUBLEREG_SP	; Get the next ?? argument - eg, ADD HL,??
		JP		NZ,MISSING_COMMA	; Missing comma or argument not found message is good for more than the comma. 
		LD		C,A					; Store command variable in C... 
		
		LD		A,(COMMAND+1)		; Recover the command we thought most likely. 
		LD		B,%0000 1001
		CP		$80					; 80=ADD
		JR		Z,TEST_Arith16_WRITE
		LD		A,(PREFIX)			; If we already have a prefix, it's an IX/IY - Not valid for this instruction.
		OR		A
		JR		NZ,TEST_ADD_PREFIXERROR
		LD		A,$ED
		LD		(PREFIX),A			; Set up for After ED for these instructions now. (MISC extended z80 instructions )
		LD		A,(COMMAND+1)
		LD		B,%0100 1010
		CP		$88					; 88=ADC
		JR		Z,TEST_Arith16_WRITE
		LD		B,%0100 0010
		CP		$98					; 98=SBC
		JR		Z,TEST_Arith16_WRITE
		JP		MISSING_COMMA		; Not valid after comma. 
									
TEST_Arith16_WRITE:		
		LD		A,C					; Get the result from TEST_DOUBLEREG_SP
		OR		A
		RLA
		RLA
		RLA
		RLA							; Move A into position. 
		OR		B					; Add 9 to it.

ONE_OPCODE:							; The code is in A. There's nothing else to do but write it. 

		LD		(COMMAND+1),A
		
		LD		A,$01
		LD		(COMMAND),A			; Simple
		CALL	WRITECODE
		POP		HL					; Waste the return address. 
		RET							; And exit

ONE_ED_OPCODE:
		LD		HL,PREFIX
		LD		(HL),$ED
		JR		ONE_OPCODE




TEST_SINGLE_OPCODE:					; All the opcodes that are a single specific opcode. With no arguments. One after another.
		LD		DE,NOP
		CALL	TESTLOOP
		LD		A,$00
		JP		Z,ONE_OPCODE

		LD		DE,RLCA
		CALL	TESTLOOP
		LD		A,$07
		JP		Z,ONE_OPCODE
		
		LD		DE,RRCA
		CALL	TESTLOOP
		LD		A,$0F
		JP		Z,ONE_OPCODE

		LD		DE,RLA
		CALL	TESTLOOP
		LD		A,$17
		JP		Z,ONE_OPCODE

		LD		DE,RRA
		CALL	TESTLOOP
		LD		A,$1F
		JP		Z,ONE_OPCODE

		LD		DE,DAA
		CALL	TESTLOOP
		LD		A,$27
		JP		Z,ONE_OPCODE

		LD		DE,CPL
		CALL	TESTLOOP
		LD		A,$2F
		JP		Z,ONE_OPCODE

		LD		DE,SCF
		CALL	TESTLOOP
		LD		A,$37
		JP		Z,ONE_OPCODE

		LD		DE,CCF
		CALL	TESTLOOP
		LD		A,$3F
		JP		Z,ONE_OPCODE

		LD		DE,HALT
		CALL	TESTLOOP
		LD		A,$76
		JP		Z,ONE_OPCODE

		LD		DE,RET
		CALL	TESTLOOP
		LD		A,$C9
		JP		Z,ONE_OPCODE

		LD		DE,EXX
		CALL	TESTLOOP
		LD		A,$D9	
		JP		Z,ONE_OPCODE

		LD		DE,DI
		CALL	TESTLOOP
		LD		A,$F3
		JP		Z,ONE_OPCODE

		LD		DE,EI
		CALL	TESTLOOP
		LD		A,$FB
		JP		Z,ONE_OPCODE

									; Now do extended ED codes with ONE_ED_OPCODE

		LD		DE,NEG
		CALL	TESTLOOP
		LD		A,$44
		JP		Z,ONE_ED_OPCODE

		LD		DE,RETN
		CALL	TESTLOOP
		LD		A,$45
		JP		Z,ONE_ED_OPCODE

		LD		DE,RETI
		CALL	TESTLOOP
		LD		A,$4D
		JP		Z,ONE_ED_OPCODE

		LD		DE,RRD
		CALL	TESTLOOP
		LD		A,$67
		JP		Z,ONE_ED_OPCODE

		LD		DE,RLD
		CALL	TESTLOOP
		LD		A,$6F
		JP		Z,ONE_ED_OPCODE

		LD		DE,LDI
		CALL	TESTLOOP
		LD		A,$A0
		JP		Z,ONE_ED_OPCODE

		LD		DE,CPI
		CALL	TESTLOOP
		LD		A,$A1
		JP		Z,ONE_ED_OPCODE

		LD		DE,INI
		CALL	TESTLOOP
		LD		A,$A2
		JP		Z,ONE_ED_OPCODE

		LD		DE,OUTI
		CALL	TESTLOOP
		LD		A,$A3
		JP		Z,ONE_ED_OPCODE

		LD		DE,LDD
		CALL	TESTLOOP
		LD		A,$A8
		JP		Z,ONE_ED_OPCODE

		LD		DE,CPD
		CALL	TESTLOOP
		LD		A,$A9
		JP		Z,ONE_ED_OPCODE

		LD		DE,IND
		CALL	TESTLOOP
		LD		A,$AA
		JP		Z,ONE_ED_OPCODE

		LD		DE,OUTD
		CALL	TESTLOOP
		LD		A,$AB
		JP		Z,ONE_ED_OPCODE

		LD		DE,LDIR
		CALL	TESTLOOP
		LD		A,$B0
		JP		Z,ONE_ED_OPCODE

		LD		DE,CPIR
		CALL	TESTLOOP
		LD		A,$B1
		JP		Z,ONE_ED_OPCODE

		LD		DE,INIR
		CALL	TESTLOOP
		LD		A,$B2
		JP		Z,ONE_ED_OPCODE

		LD		DE,OTIR
		CALL	TESTLOOP
		LD		A,$B3
		JP		Z,ONE_ED_OPCODE

		LD		DE,LDDR
		CALL	TESTLOOP
		LD		A,$B8
		JP		Z,ONE_ED_OPCODE

		LD		DE,CPDR
		CALL	TESTLOOP
		LD		A,$B9
		JP		Z,ONE_ED_OPCODE

		LD		DE,INDR
		CALL	TESTLOOP
		LD		A,$BA
		JP		Z,ONE_ED_OPCODE

		LD		DE,OTDR
		CALL	TESTLOOP
		LD		A,$BB
		JP		Z,ONE_ED_OPCODE
		
		RET

TEST_COMMA:
		PUSH	AF		; A probably holds an important value. Preserve it. 
		LD		A,(OPERATOR)
		CP		','
		JR		Z,TEST_COMMA_OK
		LD		DE,ERR_COMMA_MISSING
		JP		ERROR_OUT
TEST_COMMA_OK:
		POP		AF		; Reestore value that was in A.  We pushed it earlier. 
		RET

CHECK_BRACKETS:		
		LD		A,(SPECIAL_OPERATOR_FOUND)	
		OR		A
		RET		NZ					; If this is set, then the special operator was FOUND... Hence it was a bracket. 
MISSING_BRACKETS:
		LD		DE,ERR_MISSING_BRACKETS
		JP		ERROR_OUT
		
TEST_IN:							; There is some torturous logic here.
									; Will be BCDEFHL(HL) if it's IN r,(C)
									; If it's (A), it could be IN A,(C) or IN A,(VALUE)...  
		LD		DE,IN
		CALL	TESTLOOP
		RET		NZ
		CALL	TEST_EOL			; There MUST be something after this command. Always		
		
		CALL	GETWORD_TO_END		; Get the next word. Will have a comma.
		CALL	TEST_COMMA			; Make sure we got a comma as the operator. 
		
		CALL	TEST_SINGLEREG		; Is it ABCDEHL(HL)? This is for the 64 bytes of LD A,B LD B,C etc... 
		JP		NC,UNKNOWN_REG		; If there's no carry, it wasn't a valid IN... Error out with error message.
									; A now carries the register.
		CP		$07					; If the register was "A" then we need to check for (C) and VAL. 
		JR		NZ,TEST_IN_C		; It's automatically C otherwise. Write the command.

									; Since it's "A" it could be as simple as A,(C) or A,($00) or as complex as A,(SERIAL+3)
									; First let's strip the first bracket. 
		LD		A,'('
		LD		(SPECIAL_OPERATOR),A
		CALL	GETWORD_TO_END		; Should just read up to the ( symbol and strip it. 
		CALL	CHECK_BRACKETS		; Make sure that's what we got.
			
		LD		A,')'				; We need to bracket the number without the bracket. Remove from all subsequent getwords until we find it. 
		LD		(SPECIAL_OPERATOR),A	; Special operator one-off for this process.  Stays valid until encountered. 
										; the EVAL routine will do the calling to GETWORD_TO_END here when evaluating. We don't need to do it directly. 	
;		CALL	EVAL			; Now we have a legit buffer to EVAL. 
		CALL	GETWORD_TO_END			; Don't trigger via EVAL since it might be (C).
		LD		A,(SPECIAL_OPERATOR_FOUND)
		OR		A
		JR		Z,TEST_IN_EVAL		; If we didn't find the special operator yet, it might be because it was a label or value. 
			
		LD		A,(BUFFER+1)
		CP		'C'
		JP		NZ,TEST_IN_EVAL		; If it's not C, maybe it's a label?

		LD		A,(BUFFER)
		CP		$01
		JR		NZ,TEST_IN_EVAL		; If it's more than 1 character, maybe it's a label?

		CALL	CHECK_BRACKETS		; Check the final bracket.	; Because it was a single character C
		
		LD		A,$07
		JR		TEST_IN_AC			; It's IN A,(C). Set for A manually and jump to write. 

TEST_IN_EVAL:						; It might be a value. 
		CALL	EVAL				; Special Operator may or may not be in play... If it's not, it's because we got a single argument.
									; If it is, it will be handled when we get to it. 
									; We should have the 8 bit port now.
		LD		A,$02
		LD		(COMMAND),A			; 2 bytes for in a,(n).
		LD		A,$DB
		LD		(COMMAND+1),A
		LD		A,(VALUE)			; Get the 8 bit value.
		LD		(COMMAND+2),A		; And store it.
		CALL	WRITECODE
		POP		HL					; Waste the return address. 
		ret

		
									; in r,(c) instructions. 
CVAL: DB 3,'(C)'
TEST_IN_C:
		PUSH	AF
		CALL	GETWORD_TO_END		; Collect the (C)
		LD		DE,CVAL
		CALL	TESTLOOP			; Check it's (C)
		JP		NZ,MISSING_BRACKETS	; Something is wrong if we didn't get a match.
		POP		AF					; Get the register we want (B to A ) 
TEST_IN_AC:							; We already collected and validated the (C) if it was an A. (ie, A=7). 

		OR		A					; It's a (C) related instruction. 
		RL		A
		RL		A
		RL		A					; Move up A three times.
		OR		%0100 0000			; Mask for A from 4 to 7, ending in 8 or 0.
		LD		(COMMAND+1),A		; Store the instruction. 
		LD		A,$ED
		LD		(PREFIX),A			; ED Misc Instructions.
		LD		A,$01
		LD		(COMMAND),A			; 1 character with the prefix. 

		CALL	WRITECODE			; Write two bytes.

		POP		HL					; Waste the return byte.
		RET							; And exit.


TEST_OUT:							; This like IN is rather torturous. First, make sure we got brackets. Then make sure we got C. If not EVAL. 
									; Then we check for the register - If A, the value is saved. 
									; It's one of the more complex commands to figure out using my algorythms. 
		LD		DE,OUT
		CALL	TESTLOOP
		RET		NZ
		CALL	TEST_EOL			; There MUST be something after this command. Always		

		LD		A,'('				; Check there's a bracket next. There must ALWAYS be a bracket. 
		LD		(SPECIAL_OPERATOR),A
		CALL	GETWORD_TO_END		; Should just read up to the ( symbol and strip it. 
		CALL	CHECK_BRACKETS		; Make sure that's what we got.

		LD		A,')'				; We need to bracket the number without the bracket. Remove from all subsequent getwords until we find it. 
		LD		(SPECIAL_OPERATOR),A	; Special operator one-off for this process.  Stays valid until encountered. 
										; the EVAL routine will do the calling to GETWORD_TO_END here when evaluating. We don't need to do it directly. 	
;		CALL	EVAL			; Now we have a legit buffer to EVAL. 
		CALL	GETWORD_TO_END			; Don't trigger via EVAL since it might be (C).
		CALL	TEST_EOL 			; There will STILL be more to come. Make sure it's there. 
		
		LD		A,(SPECIAL_OPERATOR_FOUND)
		OR		A
		JR		Z,TEST_OUT_EVAL		; If we didn't find the special operator yet, it might be because it was a label or value. 
			
		LD		A,(BUFFER+1)
		CP		'C'
		JP		NZ,TEST_OUT_EVAL		; If it's not C, maybe it's a label?

		LD		A,(BUFFER)
		CP		$01
		JR		NZ,TEST_OUT_EVAL		; If it's more than 1 character, maybe it's a label?

		CALL	CHECK_BRACKETS		; Check the final bracket.	; Because it was a single character C

		CALL	GETWORD_TO_END		; NOW we need the , since we stopped at the )
		CALL	TEST_COMMA			; Make sure we got the COMMA. We should check there's nothing in the buffer also.
		LD		A,(BUFFER)
		OR		A
		JP		NZ,ERR_NO_COMMA		; Expecting a comma. But we got JUNK and a comma. 
		
		CALL	TEST_EOL			; Yeah, we still got more to go.
		CALL	GETWORD_TO_END	
		CALL	TEST_SINGLEREG		; Is it ABCDEHL(HL)? This is for the 64 bytes of LD A,B LD B,C etc... 
		JP		NC,UNKNOWN_REG		; If there's no carry, it wasn't a valid IN... Error out with error message.

		OR		A					; It's a (C) related instruction. 
		RL		A
		RL		A
		RL		A					; Move up A three times.
		OR		%0100 0001			; Mask for A from 4 to 7, ending in 8 or 0. For OUT. 
		LD		(COMMAND+1),A		; Store the instruction. 
		LD		A,$ED
		LD		(PREFIX),A			; ED Misc Instructions.
		LD		A,$01
		LD		(COMMAND),A			; 1 character with the prefix. 

		CALL	WRITECODE			; Write two bytes.

		POP		HL					; Waste the return byte.
		RET							; And exit.


TEST_OUT_EVAL:						; Well, we know it's probably a value in the buffer
		CALL	EVAL				; Special Operator may or may not be in play... If it's not, it's because we got a single argument.
									; If it is, it will be handled when we get to it. 
									; We should have the 8 bit port now.

		CALL	GETWORD_TO_END		; NOW we need the , since we stopped at the ) This bit is the same as above. I might be able to remove some.
		CALL	TEST_COMMA			; Make sure we got the COMMA. We should check there's nothing in the buffer also.
		LD		A,(BUFFER)
		OR		A
		JP		NZ,ERR_NO_COMMA		; Expecting a comma. But we got JUNK and a comma. 
		
		CALL	TEST_EOL			; Yeah, we still got more to go.
		CALL	GETWORD_TO_END	
		CALL	TEST_SINGLEREG		; Is it ABCDEHL(HL)? This is for the 64 bytes of LD A,B LD B,C etc... 
		JP		NC,UNKNOWN_REG		; If there's no carry, it wasn't a valid IN... Error out with error message.

		CP		$07					; But we only are about A here.
		JP		NZ,UNKNOWN_REG		; ANd we'll error on anything else. 

		LD		A,$02
		LD		(COMMAND),A			; 2 bytes for in a,(n).
		LD		A,$D3
		LD		(COMMAND+1),A
		LD		A,(VALUE)			; Get the 8 bit value.
		LD		(COMMAND+2),A		; And store it.
		CALL	WRITECODE
		POP		HL					; Waste the return address. 
		ret		


EXAF:	DB	2,'AF'
EXAF2:	DB	3,'AF',"'"
EXSP:	DB	4,'(SP)'

TEST_EX:							; EX with two arguments.
		LD		DE,EX
		CALL	TESTLOOP
		RET		NZ
		CALL	TEST_EOL			; Make sure we're not EOL, because there's more to come. 
		
		LD		A,$01
		LD		(COMMAND),A			; 1 byte for all of these.
		
		CALL	GETWORD_TO_END		; Get the next argument.
		CALL	TEST_COMMA				; Make sure there's a comma here. 

		LD		DE,EXAF
		CALL	TESTLOOP
		JR		Z,TEST_EX_AFAF
		
		LD		DE,EXSP
		CALL	TESTLOOP
		JR		Z,TEST_EX_SPHL
		
		LD		DE,DEREG
		CALL	TESTLOOP
		JR		Z,TEST_EX_DEHL
		
TEST_EX_ERROR:
		LD		DE,ERR_EX
		JP		ERROR_OUT			; A Full Metal Alchemist joke here. 


TEST_EX_AFAF:
		CALL	GETWORD_TO_END		; Get the next argument.
		LD		DE,EXAF
		CALL	TESTLOOP
		JR		NZ,TEST_EX_AFAF3
TEST_EX_AFAF2:
		LD		A,$08
TEST_EX_EXIT:
		LD		(COMMAND+1),A
		CALL	WRITECODE
		POP		HL					; Waste return and exit.
		RET
TEST_EX_AFAF3:
		LD		DE,EXAF2
		CALL	TESTLOOP
		JR		NZ,TEST_EX_ERROR
		JR		TEST_EX_AFAF2		; Otherwise accept AF,AF'


TEST_EX_SPHL:
		CALL	GETWORD_TO_END		; Get the next argument.
		LD		DE,HLREG
		CALL	TESTLOOP
		JR		NZ,TEST_EX_ERROR
		LD		A,$E3
		JR		TEST_EX_EXIT


TEST_EX_DEHL:
		CALL	GETWORD_TO_END		; Get the next argument.
		LD		DE,HLREG
		CALL	TESTLOOP
		JR		NZ,TEST_EX_ERROR
		LD		A,$EB
		JR		TEST_EX_EXIT




		

; LABEL_TABLE is the start location at the end of code ( Note - Need to check for Overflow, TPA etc, Stack etc )
; The table is a linked list, as per the following.
; 
;NEXT_LABEL, 2 bytes
;LABEL_LENGTH, 1 byte ( Length of label in characters )
;LABEL_NAME,1 to 32 bytes	; STRING, Variable. Up to 32 characters... Label name without :
;LABEL_VALUE,2 bytes. Integer. LSB MSB Regardless of 8 or 6 bit operations. 
;Repeats. 
;

MATCH_LABEL:		; Before we add a label, or when searching for a value, we must search to 
					; see if the label exists. This also locates the next label location.
		LD		HL,LABEL_TABLE			; Initial label table location.
MATCH_LABEL_LOOP:
		PUSH	HL						; Store the current vector on the stack. 

		LD		A,(HL)
		INC		HL
		OR		(HL)					; are the two locations zero?
		JR		Z,MATCH_LABEL_NOTFOUND	; If the link vector is zero, it means there is no label here yet. 
										; This is the first possible outcome of this routine. (not found).
										; We will clear carry and exit also to show "not found"
										
										; If there was a vector though, then
		INC		HL						; Get to the label part to see if it matches buffer. 
		
		LD		A,(BUFFER)				; Number of characters.
		CP		(HL)					; Check against label number of characters.
		JR		NZ,MATCH_LABEL_NEXT		; Not same length? Not a match. 
		INC		HL						; Step up to label. 
		LD		B,A						; Count through the characters to match. 
		LD		DE,BUFFER+1				; What we're matching against?
MATCH_LABEL_CHECK:
		LD		A,(DE)
		CP		(HL)
		JR		NZ,MATCH_LABEL_NEXT		; It wasn't this label.
		INC		DE
		INC		HL						; Increment here. Note that our final increment will go past the label.
		DJNZ	MATCH_LABEL_CHECK		; and will point to the value of the match... 
	
										; HL is now at the value point in the table for the matching entry. 
 						
		LD		A,(HL)
		LD		(VALUE),A
		INC		HL
		LD		A,(HL)
		LD		(VALUE+1),A				; Copy the value of the matching vector to "Value", to return a value. 
		DEC		HL
		EX		DE,HL					; Store the start of the value in case we want to change it now we have located it. 
		POP		HL						; Restore the vector to the start of the entry. Now HL=Label Start, DE=Label Value Start 
										; HL is the vector of the entry, which holds the start of the next entry (linked list).
		SCF								; And set the carry flag to indicate we got a match.
		RET								;

MATCH_LABEL_NEXT:						; We didn't find a match, so we go to the next vector .
		POP		DE						; Recover the current vector. 
		LD		A,(DE)
		LD		L,A
		INC		DE
		LD		A,(DE)
		LD		H,A						; Get the next vector into HL....
		JR		MATCH_LABEL_LOOP		; And check the next vector. 

MATCH_LABEL_NOTFOUND:
		LD		A,(PASS)
		CP		$02			; Pass 2 there should be no such thing as a label that does not exist. This is an error.
		JR		Z,LABEL_NOT_EXIST
		
		POP		HL	; Retrieve the current vector which is the end of the label linked list. 
					; Note we got to the end without finding a label. HL is pointing to the next vector.
		LD		(LABEL_LAST),HL	; Store the last and highest the list got. 
		OR		A	; Clear the carry flag to show there was no match. VALUE is unset. 
					; HL is current vector at end of label table linked list ( or start if unused yet ). 
		RET



LABEL_NOT_EXIST:					; This is an error.
		LD		DE,ERR_LABEL_NOT_EXIST
		JP		ERROR_OUT
LABEL_ALREADY_EXIST:
		LD		DE,ERR_LABEL_ALREADY_EXIST
		JP		ERROR_OUT
		
LABEL_LAST: DW $0000

LABEL_OVERFLOW_MSG:	DB	$0D,$0A,'Label memory exhausted. Out of memory.$'

LABEL_OVERFLOW:
		LD		DE,LABEL_OVERFLOW_MSG
		JP		ERROR_OUT

LABEL_POS:	DW	LABEL_TABLE					; Where are we in the label table?
.EQU	LABEL_TOP,$C000						; Generate label overflow error if Label Pos goes above Label Top.
ADD_LABEL:
		CALL	MATCH_LABEL				; This sets us up at the end of the tree or returns an existing location.

		JR		C,LABEL_EXISTS			; OK, we found the label already existed. Do we update it's value? Do we check it's value?
		
		
		LD		A,(PASS)
		CP		$02
		JP		Z,LABEL_NOT_EXIST		;  ALL labels should exit by Pass 2, so don't add new ones... ERROR ERROR ERROR!
										; If we fall through, we have a label in BUFFER and no entry in the table.
										; So we write the entry into the table. 
										; Match label routine should return with HL = Location of next empty label.
		EX		DE,HL					; Move the location of the label to DE, and HL with Memory Top. 
;		LD		HL,LABEL_TOP			; The highest memory address of a label. 
;		OR		A
;		SBC		HL,DE					; Check overflow of label. 
;		JR		C,LABEL_OVERFLOW		; Label memory exhausted. Test this later.

		LD		HL,BUFFER				; used to start with buffer +1 but we also use the character count now. 
		
		PUSH	DE						; Store the vector bytes of the label in the stack.  
		
		INC		DE
		INC		DE						; Go past linked list vector. Destination is now the label. 
		
		LD		A,(BUFFER)				; Number of bytes to copy (label).
		INC		A						; Label length + character count at start. 
		LD		C,A						;
		LD		B,$00					; HL is Buffer holding the label, DE is the label part of the entry
		LDIR							; BC is count... Copy them.  Here we copy the label and the label character count from the buffer 
		
		
		LD		A,(VALUE)				; Write the VALUE part of the entry.
		; Copy value to DE here.
		LD		(DE),A
		INC		DE						; Just increment for the moment. 
		LD		A,(VALUE+1)
		LD		(DE),A					; And store the PC...
		INC		DE						; DE now holds the next location.
										; It's a new entry so zero it. 
		
		
		XOR		A
		LD		(DE),A
		INC		DE
		LD		(DE),A					; And write 0000 to the next label record to show it's the end of the list
		DEC		DE						; And decrement so DE holds the vector to it.
		
		POP		HL						; Recover the vector at the start of the label.
		LD		(HL),E
		INC		HL
		LD		(HL),D					; And store the vector to the location held in DE. 
										; Leave DE the same in case we need to add a value later. We can dec twice
										; then write the value. 

		RET								; And the label has been added to the end of the list
										; and the list updated. We can exit here. 
										
										; Exceptions next. 
		
LABEL_EXISTS:							; OK, we found the label.. Update if it's zero. If it's not, give an error. 
										; We can address what we do if the label exists later. 
										; In pass 1, this is an instant fail - a label should only be assigned once. 
										; Or do I want to change that?
		JP		LABEL_ALREADY_EXIST		; Oops... Just assume if we get here, it's a mistake. This is ONLY called by LABEL: type labels. NOT EQU type labels assignments.  
;		LD		A,(PASS)
;		CP		$01
;		JP		Z,LABEL_ALREADY_EXIST	; Trap attempt to reassign label. 
;RST 20
;		CALL	SET_LABEL				; DE should hold the location of the label
;RST 28
;		ret	
;
;SET_LABEL:								;Set the value of a pre-existing label once Match_Label as located it. Right now VALUE holds the previous value. 
;		PUSH	DE						; Store the label value location. It's in DE presently. 
;		CALL	GETWORD_TO_END
;		CALL	EVAL					; Get the value of the label...  I think I already checked for the comma.  We do this, because the label MIGHT have changed, Even in an EQU. If a formula. 
;		POP		DE
;		LD		A,(VALUE)
;		LD		(DE),A
;		LD		A,(VALUE+1)
;	    INC		DE
;		LD		(DE),A			
;		RET
			

TESTLOOP:
		LD	HL,BUFFER
		LD	B,(HL)		; First byte is the count. But we also test the count, so add a loop for the count.
		INC	B

TESTLOOP1:
		LD	A,(DE)
		CP	(HL)						; Check the number count is the same first. 
		JR	NZ,TESTBAD					; We've already established that the NZ is set if we didn't get a match.
		INC	DE
		INC	HL
		DJNZ	TESTLOOP1
		; TEST GOOD ! Got it.
		XOR		A						; Set the zero flag before exit.
TESTBAD:								; And we just exit here. If zero flag set, we got a match. If not set, No match. 
		RET
		
	
		
ENTRYNUMBER:	DB		$00				; For a count - Starts at $30.
INBUFFER: 		DW		$0000					; Temp variable for place in buffer. 	

	
PRINTWORD_LINE:			DB	' Ln:$'
PRINTWORD_MEMADDRESS:	DB	' PC:0x$'
PRINTWORD_TOKEN:		DB	' Token:$'
PRINTWORD_EOL:			DB	' EOL:$'
PRINTWORD_VALUE:		DB	' Value?:0x$'

PRINTWORD_EVAL:	DB	' EVAL $'
PRINTWORD_WS:	DB	' 2WS  $'
PRINTWORD_xEND:	DB	' 2END $'


PWEVAL:	
		LD DE,PRINTWORD_EVAL
		JP	PRINTSTRING	

PWWS:	
		LD DE,PRINTWORD_WS
		JP	PRINTSTRING
		
PWEND:	
		LD DE,PRINTWORD_xEND
		JP 	PRINTSTRING				


PRINTLINE:													; Print the incomming line number from the source file. 
		LD		DE,PRINTWORD_LINE					; Tell the user 'Line'
				CALL 	PRINTSTRING
				
				LD		HL,(LINE_NUMBER)					; Print the Line Number.
				CALL	PRINTDEC16
				RET

PRINTPC:													; Print the program counter. 
		LD		DE,PRINTWORD_MEMADDRESS				; Tell the user the PC comes next.
				CALL 	PRINTSTRING
	
				LD		HL,(PC)								; Add the PC in HEX. 
				CALL	PRINTHEX16

				LD		DE,PRINTWORD_TOKEN					; Mention the TOKEN comes next.
				JP		PRINTSTRING
				
PRINTENTRY:													; The entry number for the line ( which argument from the line? )											
		LD		A,(ENTRYNUMBER)
				LD		E,A
				INC		A
				LD		(ENTRYNUMBER),A
				LD		C,Console_Output
				CALL	BDOS
				RET
				
PRINTBUFFER:												; What's in the Entry Buffer at the moment?				
		LD		E,"["								; 
				LD		C,Console_Output
				CALL	BDOS		
															
				LD		HL,BUFFER							; Start of buffer. 
				LD		A,(HL)
				OR		A									; Test A
				JR		Z,PRINTWORD_NOBUFFER				; If there's nothing in the buffer.

				LD		B,A									; Transfer the Count
				INC		HL
				LD 		(INBUFFER),HL
PRINTWORD_LOOP:
				LD		HL,(INBUFFER)
				LD		E,(HL)
				INC		HL
				LD		(INBUFFER),HL
				LD		C,Console_Output
				CALL	BDOS
				DJNZ	PRINTWORD_LOOP
PRINTWORD_NOBUFFER:
	
				LD		E,"]"								; Tell the user the PC comes next.
				LD		C,Console_Output						; 
				CALL	BDOS

				LD		A,(OPERATOR)
				LD		E,A
				LD		C, Console_Output
				CALL	BDOS

				LD		A,' '				; Tell the user the PC comes next.
				JP		PRINTCHAR
				


	
CRLF:
				LD		E,$0D
				LD		C,Console_Output
				CALL	BDOS
				LD		E,$0A
				LD		C,Console_Output
				CALL	BDOS				
				ret


PRINTSPACE:
				LD		A,' '
				JP		PRINTCHAR
				

IFNZ DEBUG
PRINTHASH:
				LD		A,'#'
				JP		PRINTCHAR

PRINTDASH:
				LD		A,'-'
				JP		PRINTCHAR

PRINTAT:
				LD		A,'@'
				JP		PRINTCHAR

PRINTAST:
				LD		A,'*'
				JP		PRINTCHAR

PRINTEX:
				LD		A,'!'
				JP		PRINTCHAR

PRINTDOT:
				LD		A,'.'
				JP		PRINTCHAR

PRINTCOLON:
				LD		A,':'
				JP		PRINTCHAR

PRINTSEMI:
				LD		A,';'
				JP		PRINTCHAR

ENDIF











				
GETCHAR:
				LD		DE,$0080
				LD		H,$00
				LD		A,(CHARPOS)
				LD		L,A				; Collect the lower position.
				BIT		7,L				; Did we go past 128 characters?
				CALL	NZ,GETCHAR_NEXTPAGE	; Do we need to load in another page?
											; WARNING. Note there is an error bypass in the GETCHAR_NEXTPAGE routine that exits via GETCHAR_READERROR. 
				ADD		HL,DE				; Next character location in memoory. 
				LD		A,(HL)				; Retrieve the next character from the file buffer.
				LD		HL,CHARPOS
				INC		(HL)				; Note we've moved to the next character position. 
				RET							; And return. 
GETCHAR_NEXTPAGE:
				XOR		A
				LD		(CHARPOS),A

				CALL	READ_SOURCE

				OR		A					; Test the A register response from the read operation. 
				JR		NZ,GETCHAR_READERROR
				
				LD		HL,(CHAR_RECORD)
				INC		HL
				LD		(CHAR_RECORD),A		; Update the record counter we want. Not sure I really need to do this, but later I'll add line counter too.

				RET							; Get the next 

GETCHAR_READERROR:
				POP		HL					; Dispose of the last return... We're bypassing the stack here. Remove last return address.
				LD		A,$FF
				LD		(EOF),A				; Set the END OF FILE byte. We're read past the end of file or hit another disk issue. 
				LD		A,26				; Insert and End Of File marker into the stream. ( File may have been ended without EOF ). 
				RET							; And just drop out with an EOF. 


											; but don't ignore operators.  00= respect whitespace. FF = Read to End Of Line. 
OPERATOR:		DB	$00						; Is there a known operator in play? eg + - * / , 
											; Operators
											; , separator
											; + add
											; - subtract
											; / divide
											; \ modulo ( remainder from divide ). 
											; * multiply
											; @ and
											; # or
											; $ hexadecimal value follows.
											; % binary number value follows.
											; ' single quote means a byte or series of bytes follows in ASCII. 8 bits. Quotes are NOT normal operators. 
											; " same as single quote, but must also be closed with a double. eg, '"' and "'" are both valid. 
											; < rotate left ( Only on immediate value... Can be chained. )
											; > rotate right ( Only on immediate value... Can be chained. )
											; ^ current program counter ( Without offset ). Tested in Eval to a variable. 
											; ! invert current value. !+1 = Make Negative. 
											; Order of operators is sequential - eg, apply current value to next value. 
											; Operators DO NOT require whitespace. If an operator is encountered, it will be treated as whitespace
											; then returned next time a word is requested. 
											; Divider is non-zero means an operator was encoutered last time GETWORD was called. 
											
OPERATOR_LIST:	db ',+-/\*@#<>!'			; List of all operators. Make sure _ is never an operator. _ is a character. It appears in labels. Quote is NOT an operator anymore. 
											; Quote changes the mode of returning words and returns characters as values until the next same-quote. 
OPERATOR_LISTEND:							; All operators should be symbols. 
											; #### NOTE - the DOT or Decimal Point - Represents an "ignore" character...  Like ignorable whitespace. 
											; #### It is just a way for format for convenience - eg, long binary numbers %0000.0000.0000.0000 instead of 
											; #### just %0000000000000000 - It makes it more readable. 
.EQU	NUMBER_OPERATORS,OPERATOR_LISTEND-OPERATOR_LIST	; Calculate the number of operators in case we add others later. 
SPECIAL_OPERATOR:	DB	$00					; Sometimes we need to look for something that isn't normally an operator (eg. IX+DISP) - The second bracket needs to be invisible. 
											; Special Operator MUST COME AT THE END. We only check it if it's non-zero. 
SPECIAL_OPERATOR_FOUND:	DB	$00				; So we can flag we got it. Will be non-zero if found. 
											;Sometimes used by other routines that need to know if it was encountered since it doesn't show up. 
READ_TO_EOL:	DB	$00						; Read through to the end of line - eg, We want to read the remainder of the line. Ignore ALL whitespace. 




GETWORD_TO_END:								; Same as GETWORD, but ignores ALL WHITE SPACE until either an operator or EOL is encountered. 
IFNZ DEBUG
CALL PWEND					; Indicate Get to End called. 
ENDIF
				LD		A,$FF
				LD		(READ_TO_EOL),A		; We want the rest of the argument. 
				CALL	GETWORD
IFNZ DEBUG
CALL PRINTBUFFER
ENDIF
				CALL	TRANSLATE			; Some to-end symbols require translation to (HL) HL or (HL) - Only affects To End reads. 

IFNZ DEBUG
CALL PRINTBUFFER				; Post translation. 
ENDIF

;LD		A,(PREFIX)
;OR		A
;RET		Z			; Don't print translated buffer unless we've translated it. 
;
;CALL PRINTAST
;CALL PRINTBUFFER							; We can show post-translation. 
;CALL PRINTAST
				RET	
				

GETWORD_TO_WS:	
IFNZ DEBUG
CALL	PWWS				; Indicate Whitespace Get Called.
ENDIF
				LD		A,$00
				LD		(READ_TO_EOL),A		; Stop reading when we hit whitespace. 
				
				CALL	GETWORD
IFNZ DEBUG
CALL PRINTBUFFER
ENDIF
				RET

QUOTE_ERR:
		LD	DE,ERR_QUOTE
		JP	ERROR_OUT

INSTRING:			DB	$00					; If not zero, we're in a string. 
											; It is either ' or " depending on which string started it. 
ONE_STEP:			DB	$00					; One step ahead... The last / next read character... We need a little bit of a peek ahead. 
														
											
											; Routine to get the next word from the source... Either a command, the opcode or function and the value. 
											; Routine to get the next word from the source... Either a command, the opcode or function and the value. 
GETWORD:									; DON'T CALL DIRECTLY. Either call GETWORD_TO_WS (whitespace) or GETWORD_TO_END (EOL or Operator)

				XOR		A					; Initialise the buffer. 
				LD		(OPERATOR),A		; Clear any previous operator in play since it's relevant only to the last word we got. 
				LD		(BUFFER),A			; Reset the buffer counter.
				LD		(SPECIAL_OPERATOR_FOUND),A ; We haven't found the special operator yet (if set)
				LD		HL,BUFFER+1			; Start of text in buffer is in HL.
				LD		(HL),A				; Clear the buffer to show there's nothing there... Just in case. 
				LD		(BUFFER_PTR),HL		; Save the pointer. 
				
GETWORD_NO_OPERATOR:							; No previous operator encountered so get the next word from the file. 	
GETWORD_LOOP:								; Let's loop until we find something of interest. 

				LD		A,(INSTRING)			; Are we in a string?
				OR		A
				JR		Z,GETWORD_BAU		; In a string, we feed it a byte at a time with literals and commas between entries. Otherwise we scan for Business As Usual. 
				
				LD		A,(ONE_STEP)		; Get the character we want to process - In a slight lag so we can see when the list is going to end. 
				PUSH	AF
				CALL	GETCHAR				; Get the next character. 
				LD		(ONE_STEP),A		; And load the next character in so we know when it's going to come to an end. Also affects the operator we fake. 
				POP		AF					; And recover the character from 
				
				CP		$0D					; EOL.
				JR		Z,QUOTE_ERR			; No EOL in a quote. anything else other than EOF is OK.
				CP		26					; No End Of File either. 
				JR		Z,QUOTE_ERR
				
				LD		HL,BUFFER			; Rewrite the buffer with single bytes separated by a comma. 
				LD		(HL),$02			; 2 bytes of data.
				INC		HL
				LD		(HL),'&'			; Literal Code
				INC		HL
				LD		(HL),A				; And the byte we got from the file.
				INC		HL
				LD		(HL),$00			; And a terminating 0.

				LD		A,','				; And add a separator.
				LD		(OPERATOR),A		; to the operator.
				
				LD		A,(ONE_STEP)
				LD		HL,INSTRING	
				CP		(HL)				; And compare the next byte to the terminating character to look ahead ( will be ' or " )
				RET		NZ					; And return if it's not the terminator.
				
				XOR		A					; Clear the operator. If it's encountered next, it will set it, otherwise not. 
				LD		(OPERATOR),A		; And save it. 	
				LD		(INSTRING),A		; And clear the INSTRING - We no longer are in a string. 				

GETWORD_BAU:								; If not in a string, it's Business As Usual.				

IFNZ	DEBUG
CALL PRINTDOT	; Print a dot for each character we are about to get. 
ENDIF

				CALL	GETCHAR				; Get the next character. If we got a character before, and it was a " or ' then we'll ignore it. 

IFNZ DEBUG
PUSH AF ; Print the character we actually retrieved. 
CP	$20 ; space
JR	NC,CHAROK
LD	A,'~'
CHAROK:
CALL PRINT_DEBUG_CHAR
POP AF				
ENDIF
				CP		'.'					; Special character... We just IGNORE all DOTs as though they don't exist... Just read past them.
				JR		Z,GETWORD_LOOP		; Redo from top if it was a '.'	

				CP		';'					; Is a comment?
				CALL	Z,GETWORD_SKIPCOMMENT	; Skip comments. We will skip to EOL of we hit this, regardless of other symbols. We will end up with the first EOL returned. 

				CP		"'"					; Compare to quote.
				JR		Z,GETWORD_QUOTE			; Collect everything in the quotations. Size limited.
				CP		'"'					; For both quotes.
				JR		Z,GETWORD_QUOTE2		; But must close with same kind as entry quote. 

				CP		$0D
				JP		Z,GETWORD_EOL		; Same for CR... EOL is just more whitespace. 
				CP		26
				JP		Z,GETWORD_EOL


				
				CALL	GETWORD_OPERATORS	; Check for operators. Will return A as 0 and the zero flag is set if it finds an operator
											; Then loads the operator it found into the (OPERATOR) variable. Operator doesn't return if it finds an operator. It pops then returns
											; If it returns, it wasn't an operator. 

; Store the character if it's above CHR20 (space)
				CP		$21					; Check for whitespace now. Anything up to space.
				JR		NC,GETWORD_CHAR		; Should generate carry if there's a Space or lower. Zero for "!" but no carry.  Strip out other white space.
; Below this line, we got Whitespace, not a character or an Operator. 
; Eliminate whitespace at the start.
				LD		A,(BUFFER)			; Have we received any characters in the buffer yet????
				OR		A
				JR		Z,GETWORD_LOOP		; If it's the first to put in the buffer ( zero characters ) then continue to loop - ie, Always ignore whitespace before we have a character.
				
				LD		A,(READ_TO_EOL)		; Were we told to ignore Whitespace until Operator or EOL? ( or special operator ).
				OR		A
				JR		NZ,GETWORD_LOOP		; Ignore ALL whitespace if we have read-to-eol set to non-zero. 
				
; We found whitespace... We can end now unless we were told otherwise ( as checkd above)
;				JR		GETWORD_END			; If we have content, it's the end of the word here. 
				RET

; This is where we check for things GETWORD picked up....
GETWORD_QUOTE:		
GETWORD_QUOTE2:						; Scan the whole string until we get another single quote '
				LD		(INSTRING),A		; Store the quote so we know what to terminate it with.
				CALL	GETWORD
				LD		(ONE_STEP),A		; Store this for the next step.
				LD		HL,INSTRING
				CP		(HL)
				JP		NZ,GETWORD_LOOP		; And restart the loop.
											; Or fall through and error. 					

GETWORD_CHAR:								; Now we know we got legitimate characters. Store them.
				CP		$61					; a? First we make ALL CAPS... 
				JR		C,GETWORD_CHAR_CAPS	; If it's below a, it's already caps.
				CP		$7B					; z?
				JR		NC,GETWORD_CHAR_CAPS
				AND		$DF					; Convert lower case to upper case 				
GETWORD_CHAR_CAPS:
				CALL	GETWORD_ADDCHAR		; Add the character to the buffer.
				JP		GETWORD_LOOP		; And repeat.



GETWORD_ADDCHAR:							; Add the character to the buffer.
				LD		HL,(BUFFER_PTR)		
				LD		(HL),A
				INC		HL
				LD		(BUFFER_PTR),HL
				LD		HL,BUFFER
				INC		(HL)					
				RET





				
	
GETWORD_OPERATORS:								; Check for special characters that are operators.
				LD		B,NUMBER_OPERATORS		; Check the full list of operator symbols.
				LD		HL,OPERATOR_LIST
GETWORD_OPERATORS_LOOP:
				CP		(HL)					; Test against list.
				JR		Z,GETWORD_OPERATORS_FOUND	; If an operator was found, note it and exit. 						
				INC		HL						; And go to the next in the list. 
				DJNZ	GETWORD_OPERATORS_LOOP			; Otherwise loop until all operators checked.
; Now check special operators only sometimes imposed - Since HL is advanced.
;				LD		HL,SPECIAL_OPERATOR	; Check for a special operator first... It will be "!" or above in ASCII. We do it here so 00 is ignored. 
				CP		(HL)
				JR		Z,GETWORD_CLEARSPECIAL	; End but clear the special operator also.  This is critical for things like (IX+DISP) and IN (C) IN (VALUE)
				CP		'|'						; Symbol for separating commands. Like an EOL without a new line.
				JR		Z,GETWORD_CLEARSPECIAL	; Same as a special character. Ends the input search, but doesn't record the character and doesn't cause an EOL. 
				RET									; Return with no operators found. 
; Below it drops out of the call and forces a return via a POP and a RET. 
GETWORD_OPERATORS_FOUND:
				LD		(OPERATOR),A				; Note we found an operator. 
				POP		HL					; Waste the return address
				RET							; And exit the entire Getwork routine. 
GETWORD_CLEARSPECIAL:
				LD		(HL),$00			; Clear the special operator... It's a single trigger.
				LD		HL,SPECIAL_OPERATOR_FOUND
				LD		(HL),$FF			; Trap that we found it. 
GETWORD_CLEARSPECIAL_NORECORD:				; Later Entrypoint - Don't note that we found a special operator. 				
				POP		HL					; Waste the return address
				RET							; And exit before we do anything further. 


GETWORD_SKIPCOMMENT:				
				CALL	GETCHAR
				CP		$0D					; Exit on EOL
				RET		Z
				CP		26					; Exit on EOF. 
				RET		Z
				JR		GETWORD_SKIPCOMMENT	; And loop until we have skipped the comment ( terminated by EOL or EOF )

GETWORD_EOL:								; Called for EOL or EOF. 
;				LD		A,(SPECIAL_OPERATOR)		; Check here for not finding a special operator or not closing a quote... 
;				OR		A
;				JP		NZ,MISSING_BRACKETS			; We only use this for looking for brackets. If we get EOL first, we never got the bracket. Error.
				LD		A,$FF
				LD		(EOL),A						; Mark that we actually hit an EOL. 
				RET									; and return to software, exiting the GETWORD LOOP.   
													; We count EOL for software debugging and error purposes. 



; ################ Translation details ( Sometimes we see IX or IY instead of HL ).
; These routines translates from IX to HL, with appropriate consideration. 

ATIX:	DB	4,'(IX)'
ATIY:	DB	4,'(IY)'
IXREG:		DB	2,'IX'
IYREG:		DB	2,'IY'
IXHREG:	DB	3,'IXH'
IXLREG:	DB	3,'IXL'
IYHREG:	DB	3,'IYH'
IYLREG:	DB	3,'IYL'
DISPIX:	DB	3,'(IX'
DISPIY:	DB	3,'(IY'
JUSTHL:	DB	'HL'

TRANSLATE:
		LD		DE,ATIX
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_ATIY
		LD		HL,(JUSTHL)		; Letters L and H in HL. 
		LD		(BUFFER+2),HL	; Write HL in over IX in the buffer before we do anything. 
		LD		A,$DD
		LD		(PREFIX),A		; DD Prefix. Otherwise instruction is the same. 
		RET
TRANSLATE_ATIY:
		LD		DE,ATIY
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_IX
		LD		HL,(JUSTHL)		; Letters L and H in HL. 
		LD		(BUFFER+2),HL	; Write HL in over IX in the buffer before we do anything. 
		LD		A,$FD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET

TRANSLATE_IX:
		LD		DE,IXREG
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_IY
		LD		HL,(JUSTHL)
		LD		(BUFFER+1),HL	; Write HL in over IX in the buffer before we do anything. 
		LD		A,$DD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET
TRANSLATE_IY:
		LD		DE,IYREG
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_IXH
		LD		HL,(JUSTHL)
		LD		(BUFFER+1),HL	; Write HL in over IX in the buffer before we do anything. 
		LD		A,$FD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET


TRANSLATE_IXH:					; IXH and IXL for 8 bit operations. Undocumented. 
		LD		DE,IXHREG
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_IXL
		LD		A,$01
		LD		(BUFFER),A
		DEC		A
		LD		(BUFFER+2),A
		LD		A,'H'
		LD		(BUFFER+1),A
		LD		A,$DD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET
TRANSLATE_IXL:
		LD		DE,IXLREG
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_IYH
		LD		A,$01
		LD		(BUFFER),A
		DEC		A
		LD		(BUFFER+2),A
		LD		A,'L'
		LD		(BUFFER+1),A
		LD		A,$DD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET
TRANSLATE_IYH:					; Same for IYH and IYL
		LD		DE,IYHREG
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_IYL
		LD		A,$01
		LD		(BUFFER),A
		DEC		A
		LD		(BUFFER+2),A
		LD		A,'H'
		LD		(BUFFER+1),A
		LD		A,$FD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET
TRANSLATE_IYL:					
		LD		DE,IYLREG
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_DISPIX
		LD		A,$01
		LD		(BUFFER),A
		DEC		A
		LD		(BUFFER+2),A
		LD		A,'L'
		LD		(BUFFER+1),A
		LD		A,$FD
		LD		(PREFIX),A		; FD Prefix. Otherwise instruction is the same. 
		RET


TRANSLATE_DISPIX:					; Displacement with IX?
		LD		A,(OPERATOR)
		CP		'+'
		JR		Z,TRANSLATE_DISPCONFIRMED
		CP		'-'
		JR		Z,TRANSLATE_DISPNEGATIVE
		JR		TRANSLATE_DONE	; Here we drop out since it also wasn't displacement oriented - ie, MUST be with a + or - operator. 

TRANSLATE_DISPNEGATIVE:			; We might need to kick off a negative operator action if there's a - here, ie make 0- But should be same both ways.
TRANSLATE_DISPCONFIRMED:	
		LD		DE,DISPIX
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_DISPIY
		
		LD		A,$DD			; It's a DD or IX based operation.
		JR		TRANSLATE_GETDISPLACE	; Get the postfix displacement and exit. 

TRANSLATE_DISPIY:
		LD		DE,DISPIY
		CALL	TESTLOOP
		JR		NZ,TRANSLATE_DONE	; It might have looked like a possible IX/IY, but it wasn't... So exit. 
		LD		A,$FD
TRANSLATE_GETDISPLACE:				; Get the displacement and put in a fake (HL) so the instruction is processed correctly. 

		LD		(PREFIX),A			; Store the prefix first.
		
		XOR		A					; Make the buffer look like a zero so we can get the postfix. ie, 0+d or 0-d
		LD		(BUFFER+2),A
		INC		A
		LD		(BUFFER),A
		LD		A,'0'
		LD		(BUFFER+1),A	; Now the buffer holds the value of 0. Clear the buffer. Leave the Operator. Now we either have 0+ or 0-

		LD		A,')'				; We need to bracket the number without the bracket. Remove from all subsequent getwords until we find it. 
		LD		(SPECIAL_OPERATOR),A	; Special operator one-off for this process.  Stays valid until encountered. 
										; the EVAL routine will do the calling to GETWORD_TO_END here when evaluating. We don't need to do it directly. 
		
		CALL	EVAL			; Now we have a legit buffer to EVAL. 
		
		CALL	GETWORD_TO_END			; We would have missed the comma. Get it now. By itself. Or the EOL... Because of Special Operator, we stopped on a ) so there's more to get. 

; CALL TEST_EMPTY								; I can also check the buffer is empty here - #TO_DO# - If not empty - need an error eg, LD (IX+d)HELLO, n or INC (IX+d)SOMETHINGHERE

		LD		A,(VALUE)		; Recover 8 bits displacement value as a value. 
		LD		(POSTFIX),A		; Save it into the POSTFIX number. 
		LD		A,$FF
		LD		(ADDPOST),A		; Note there was a postfix to add. Now work out whether it was IX or IY. 

								; Now make the buffer look like (HL)
		LD		HL,(JUSTHL)
		LD		A,$04
		LD		(BUFFER),A		; 4 characters in rewritten buffer. 
		LD		(BUFFER+2),HL	; Write HL in over IX in the buffer before we do anything. 
		LD		A,'('
		LD		(BUFFER+1),A
		LD		A,')'
		LD		(BUFFER+4),A
		RET

TRANSLATE_DONE:					; No IX/IY syntax was encountered - Just exit from here. 
		RET						; I might do something else. but right now, there's no translation required. 



; $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ Generic stuff. Print routines. etc. Error messages.  

WELCOME_MESSAGE:
	db 'Loki z80 Assembler 2023. Usage: assemble filename.asm output.com',$0A,$0D,'$'

ERR_NOT_FOUND:			DB	'Source file not found$'
ERR_NO_DEST:			DB	'Cant Open output$'
ERR_OPEN_FAIL:			DB	'Output file issue$'
ERR_COMMA_MISSING:		DB	'Comma or Trailing argument missing$'
EVAL_INTERNAL_ERROR:	DB	'ASM Bug Detected$'
EVAL_BADVALUE:			DB	'Value followed wrong operator$'
ERR_EVAL_FAIL:			DB	'Could not evaluate expression$'		
ERR_EVAL_HEX:			DB	'HEX value error$'
ERR_EVAL_BIN:			DB	'BIN value error$'
ERR_EVAL_DEC:			DB	'16 bit overflow$'
ERR_OUT_OF_BOUNDS: 		DB	'Jump exceeds relative bounds.$'		
ERR_JUMP_NOWHERE:		DB	'Jump to nowhere.$'	
ERR_PREFIX:				DB	'Index usage invalid$'
ERR_NO_COMMA_MESG:		DB	'Expected comma not found$'
ERR_UNEXPECTED_CHARS_M:	DB	'Unexpected characters$'
ERR_MISS_ARGUMENT:		DB	'Missing Argument$'		
ERR_RST: 				DB	'RST invalid$'
ERR_UNKNOWN_REG:		DB	'Invalid register.$'	
ERR_RETURN_CONDITION:	DB	'Invalid flag condition.$'
ERR_JP_BAD:				DB	'Jump Invalid.$'
ERR_BAD_OPERATOR:		DB	'Not opcode, directive or label.$'
ERR_MISSING_BRACKETS:	DB	'Missing Brackets$'
ERR_EX:					DB	'*FMA Alchemy Error* Equivalent Exchange violated$'
ERR_BIT:				DB	'Invalid bit$'
ERR_QUOTE:				DB	'Quotes Unclosed$'
ERR_IMODE:				DB	'Invalid IM$'
ERR_BREAK:				DB	'Break Detected$'
ERR_LABEL_NOT_EXIST:	DB	'Label does not exist$'
ERR_LABEL_ALREADY_EXIST: DB 'Label reassignment attempted$'
NOERRORS:				DB	$0D,$0A,'NO errors encountered. Assembly Completed.$'
		

; **************************************************** Support Routines.

PRINTHEXCHAR:	DB $00					; Temp place to store the char.

PRINTHEX16:
		LD		A,H
		PUSH	HL
		CALL	PRINTHEX			; Print hex byte. 
		POP		HL
		LD		A,L					; And fall through
		
PRINTHEX:							; Print a HEX number in A
		LD		(PRINTHEXCHAR),A
		LD		HL,PRINTHEXCHAR
		RLD								; Move the upper nibble of the byte into A
		AND		$0F						; Mask to 4 bits
		OR		$30						; Convert to a number.
		CP		$3A						; See if we need to add 7. 
		JR		C,		PRINTHEX1
		ADD		A,$07
PRINTHEX1:
		CALL 	PRINTCHAR
		LD		HL,PRINTHEXCHAR		
		RLD								; Now rotate the lower 4 back to A. 
		AND		$0F						; And repeat as above. 
		OR		$30
		CP		$3A
		JR		C,		PRINTHEX2
		ADD		A,$07
PRINTHEX2:
		CALL 	PRINTCHAR
		RET
	
PRINTCHAR:							; We can redirect here if necessary...  BDOS character output. 
		LD		E,A
		LD		C,Console_Output
		CALL	BDOS
		RET

PRINTCHAR_TEMP:	DB	$00	; Temp store		
PRINT_DEBUG_CHAR:						; Debug to show what we're getting.
		LD	(PRINTCHAR_TEMP),A		; PReserve the character in A
		LD		A,(PRINTCHAR_TEMP)	; Recover the character in A
		JR		PRINTCHAR			; And use the printchar routine.

PRINTVAL:
		OR		$30
		JR		PRINTCHAR				; It's a number, so make it a character. Single digit convert to ASCII. 

PRINTDEC16:								; Prints an 16 bit integer.
										; Enter with number in HL to print.										
		LD		DE,10000
		CALL	DIVIDE
		LD		A,(RESULT)

		CALL	PRINTVAL

		LD		HL,(REMAINDER)
		LD		DE,1000
		CALL	DIVIDE
		LD		A,(RESULT)				; Will be less than 8 bits.
		CALL	PRINTVAL

		LD		HL,(REMAINDER)
PRINTDEC8_ENTRY:
		LD		DE,100
		CALL	DIVIDE
		LD		A,(RESULT)				; Will be less than 8 bits.
		CALL	PRINTVAL

		LD		HL,(REMAINDER)
		LD		DE,10
		CALL	DIVIDE
		LD		A,(RESULT)				; Will be less than 8 bits.
		CALL	PRINTVAL	

		LD		A,(REMAINDER)
		CALL	PRINTVAL	
		
		RET
		
PRINTDEC8:								; Print 8 bit integer.
										; Enter with number in A.
		LD		L,A
		LD		H,$00
		JR		PRINTDEC8_ENTRY
		
		
		
;;;;; Evaluate an expression, or an operator on the current expression. 

LAST_OPERATOR:	DB	$00					; Last operator in play. For the current value. For iterative calculations.
LAST_VALUE:		DW	$0000				; Last Value. 
VALUE:	DW	$0000						; 16 bit arithmetic. Here's the result where we store the value.


EVAL:									; Evaluate a new expression. Usually GETWORD_TO_END has been called and we have a value to convert and 
										; Possibly also an operator to apply. 
		LD		HL,$0000
		LD		(VALUE),HL				; Clear the current value before proceeding.		
										; Get the first value - we ALWAYS expect a value or a constant or a label here, NOT an operator. 
		CALL	EVAL_LIST				; This sets up the current value. 
										; First run at Evaliation - Convert the value in BUFFER to a value in VALUE. Drop Through. 				
EVAL_ITERATIVE:							; If we have an operator, let's check it out. We can re-enter here with chained operators. 		
		LD		A,(OPERATOR)			; Was there an operator?
		OR		A
		RET		Z						; If there is no operator detected in the last value, we're good to return just the value. 
		
		LD		(LAST_OPERATOR),A		; Store the operator in case we read a new one.
		LD		HL,(VALUE)
		LD		(LAST_VALUE),HL			; And store the last value in case we need it. 		

										; When an operator is in play, we need to know what comes next, eg, Chained Operator, Value etc?
		CALL	GETWORD_TO_END			; Get the next value if there was a valid operator. ( could be anything to newline. )

IFNZ	DEBUG
CALL PWEVAL
ENDIF
		CALL	EVAL_LIST				; And convert any values we got. 

		CALL	EVAL_OPERATOR			; We should now have the relevant operator in LAST_OPERATOR and the next pending operator in OPERATOR.
										; Now we can evaluate the operator. 
		JR		EVAL_ITERATIVE			; And keep on repeating while there's an operator involved. We exit on no operator, ie, no further evaluation. 
	

; EVAL OPERATOR is where we complete the maths between two terms to calculate a value.. This allows for complex expressions in the assembler in Hex, Binary, Decimal and with Operators. 
; It also supports some constants like PC. 	

EVAL_OPERATOR:							; Evaluate the expression based on the operator, the value and the previous value.
										; NOTE MATHS ORDER - Apply the operator to the LAST VALUE with the VALUE - 
										; eg, LAST_VALUE=100
										;     VALUE=25
										;     OPERATOR="/"
										; VALUE BECOMES 100 / 25 = 4. VALUE = 4. 
										;	
										; Operators we deal with;
											; + add
											; - subtract
											; / divide
											; * multiply
											; @ and
											; # or
											; ' single quote means a byte or series of bytes follows in ASCII. 8 bits. Quotes are NOT normal operators. 
													; Need to check for multiple ( only valid in a DB ).
											; " same as single quote, but must also be closed with a double. eg, '"' and "'" are both valid. 
													; Need to check for multiple ( only valid in a DB ).
											; < rotate left ( Only on immediate value... Can be chained. )
											; > rotate right ( Only on immediate value... Can be chained. )
											; ! Not - XOR $FFFF... 
											; !+1 - Convert from Negative to Positive. 0 is 0 and -32768 is -32768. Is a bit "Macro" since ! and + are diff. 

		; I need one for MODULUS.... or Remainder. 


		LD		A,(LAST_OPERATOR)			; What is the operator to apply?
		CP		'<'
		JP		Z,EVAL_ROTATELEFT			; This should be an immediate one. 
		CP		'>'
		JP		Z,EVAL_ROTATERIGHT
		CP		'!'							; NOT - Invert last number. Basically XOR... Note !+1 = make negative. 
		JP		Z,EVAL_NOT
		;
		CP		'/'						; Divide.
		JP		Z,EVAL_DIVIDE
		CP		'\'						; Modulo.
		JP		Z,EVAL_MODULO
		CP		'*'						; Multiply.
		JP		Z,EVAL_MULTIPLY
		CP 		'-'						; Subtract.
		JP		Z,EVAL_SUBTRACT
		CP		'+'						; Add
		JP		Z,EVAL_ADD			
		CP		'@'
 		JP		Z,EVAL_AND
		CP		'#'
		JP		Z,EVAL_OR
		
		CP		','
		JP		Z,EVAL_NEXTVALUE

;;;		RET								; Leave it alone it might need to iterate. 

										; We should NEVER get here... It means we got an unanticipated operator. I should trap it anyway.
		LD		DE,EVAL_INTERNAL_ERROR
		JP		ERROR_OUT				; Just error out. 
		
	
EVAL_NEXTVALUE:							; We got a comma. It's a stream of values that we've expanded. 

		LD		A,(LAST_VALUE)		
		CALL 	WRITEBYTE

		RET								; I only need to return the last value here. 

EVAL_SINGLE_OPERATOR:					; Single operator - eg, Rotate Left, Rotate Right, NEG, Invert, Complement etc. 
		LD		A,(OPERATOR)			; Check immediate operators also.

		RET
		
EVAL_ROTATELEFT:
		CALL	CHECK_NOVALUE			; Ensure there's no value in VALUE.
		LD		HL,(LAST_VALUE)
;		OR		A						; Clear carry - Don't need to - the CP before cleared it already.
		RL		L
		RL		H
		LD		(VALUE),HL				; Should not be a value in there before. Maybe I should trap it just in case. 
		RET

EVAL_ROTATERIGHT:
		CALL	CHECK_NOVALUE			; Ensure there's no value in VALUE.
		LD		HL,(LAST_VALUE)
;		OR		A						; Clear carry - Don't need to - the CP before cleared it already.
		RR		H
		RR		L
		LD		(VALUE),HL
		RET

EVAL_NOT:								; Invert HL. 
		CALL	CHECK_NOVALUE
		LD		HL,(LAST_VALUE)
		LD		A,$FF
		XOR		L
		LD		L,A
		LD		A,$FF
		XOR		H
		LD		H,A
		LD		(VALUE),HL
		RET

CHECK_NOVALUE:							; Syntax checking means make sure there's no value obtained for these operators... eg, < > ! etc. 
		LD		HL,(VALUE)
		LD		A,H
		OR		L
		RET		Z						; No value in HL.
		LD		DE,EVAL_BADVALUE		; Load up an error
		JP		ERROR_OUT
		
EVAL_DIVIDE:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		CALL	DIVIDE
		LD		HL,(RESULT)
		LD		(VALUE),HL
		RET

EVAL_MODULO:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		CALL	DIVIDE
		LD		HL,(REMAINDER)
		LD		(VALUE),HL
		RET
		
EVAL_MULTIPLY:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		CALL	MULTIPLY
		LD		HL,(RESULT)
		LD		(VALUE),HL
		RET
		
EVAL_ADD:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		ADD		HL,DE
		LD		(VALUE),HL
		RET
		
EVAL_SUBTRACT:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		OR		A						; Clear Borrow
		SBC		HL,DE
		LD		(VALUE),HL
		RET			
		
EVAL_AND:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		LD		A,L
		AND		E
		LD		L,A
		LD		A,H
		AND		D
		LD		H,A
		LD		(VALUE),HL				; HL AND DE.
		RET

EVAL_OR:
		LD		HL,(LAST_VALUE)
		LD		DE,(VALUE)
		LD		A,L
		OR		E
		LD		L,A
		LD		A,H
		OR		D
		LD		H,A
		LD		(VALUE),HL				; HL OR DE.
		RET


			
;####################### This routine calculates the value of a label, number, constant (eg, ^ for PC ) and place the 16 bit result in "(VALUE)"	
; Routines test for their own condition, and if found, drop out of the loop with an extra POP before RET. Otherwise they Return and it goes on to the next one. 	
EVAL_LIST:								; Call all evaluations in order. The routine will bypass this call if it gets a match, so keep tests separate.
		LD		HL,$0000
		LD		(VALUE),HL				; Clear the last value... So if we fall out, the value is 0000. For predictability. 
		CALL	EVAL_PC					; Was it the Program Counter symbol ie the ^ symbol ?
		CALL	EVAL_LITERAL			; Is there a literal byte in the value? Defined by & - eg, &A would have a value of 65 or $41
		CALL	EVAL_HEX				; Is it a Hex Number?
		CALL	EVAL_BIN				; Is it a Binary Number?
		CALL	EVAL_DEC				; Check out numbers first before we look for operators, perform maths or recover a label value. 
		CALL	EVAL_LABEL				; Was it a label?

		LD		A,(OPERATOR)			; If there was an operator, we can ignore there was no value. 
		OR		A
		RET		NZ

		LD		A,(EOL)					; If there's no operator but we got an End Of Line, then we're done.... 
		OR		A
		RET		NZ						; And if what we got was an EOF then we can clear the operator and return.
		
		LD		A,$FF
		LD		(EOL),A					; In case we hit an EOF, make sure it also looks like an EOL, since it's functionally both. 
		
		LD		A,(EOF)
		OR		A
		RET		NZ						; Likewise, if we got to the end of the file, we can also assume we're done... 
										; But if called with no value and no operator, that was an error. 
										
		LD		DE,ERR_EVAL_FAIL		; Could not evaluate the number if we fell through without bypassing the rest of the process.
		JP		ERROR_OUT				; Error out.

		RET


EVAL_PC:
		LD		A,(BUFFER+1)			; Test for a PC symbol first. 
		CP		'^'						; Symbol for current Program Counter. 
		RET		NZ						; Wasn't for the PC, so just exit.
		LD		A,(BUFFER)
		CP		$01
		RET		NZ						; MUST be only 1 character... Just exit and let another error occur. 
		
		LD		HL,(PC)					; Retrieve the program counter.
		LD		(VALUE),HL				; And replace the value with it... 
		POP		HL						; Waste the return address from the last call if we're done :)  Skip other tests that were called in order. 
		RET								; And exit.





EVAL_LITERAL:
		LD		A,(BUFFER+1)			; Test for a literal byte in the next value. 
		CP		'&'						; Literal Byte prefix. Indicates the next character is literally a code. Eg, ASCII to VALUE. 
		RET		NZ						; Wasn't a literal byte, so just exit.

		
		LD		A,(BUFFER+2)			; Return the value of the next byte - eg, &A = 65. Ignore the rest of the characters in the buffer. 
		LD		(VALUE),A
		XOR		A
		LD		(VALUE+1),A
		
		POP		HL						; Waste the return address from the last call if we're done :)  Skip other tests that were called in order. 
		RET								; And exit.

; Three possible numbers.		
EVAL_HEX:
		LD		A,(BUFFER+1)			; Test for a Hex number first. 
		CP		'$'						; Hexadecimal prefix.
		RET		NZ						; Wasn't hex, so just exit.
		
		CALL	EVAL_HEX_VALUE			; Convert the value
		
		POP		HL						; Waste the return address from the last call if we're done :)  Skip other tests that were called in order. 
		RET								; And exit.

EVAL_HEX_VALUE:		
		LD		A,(BUFFER)				; Number of characters we need to convert. Check bounds first. Number of characters in hex number. 
		DEC		A
		LD		DE,ERR_EVAL_HEX		; Something went wrong with the hex value message. 
		JP		Z,ERROR_OUT				; Must be more than 1 character ($ symbol)
		CP		5						; Should not be higher than 4 characters = Hex Digit too long. We can make larger for 32 bit numbers if needed. 
										; since this routine is of variable length conversion. 
		JP		NC,ERROR_OUT				; Error Out. Something seriously wrong has occured. 
				
		LD		B,A						; number of characters.
		LD		DE,BUFFER+1			; Before First hex character. 

EVAL_HEX_LOOP:
		INC		DE
		LD		A,(DE)					; Get next HEX value. 
		CALL	HEXTOBIN				; Convert number from Hex to Binary and check it. 
		LD		HL,VALUE
		RLD								; Decimal Rotate of Hex Value - Move four bits into place. 
		LD		HL,VALUE+1
		RLD								; And carry over any extra bits.
		DJNZ	EVAL_HEX_LOOP
		RET								; And we're done. 


HEXTOBIN:							; Convert a hex number in A ( AS ASCII ) to a 4 bit BINARY number.

		CP		'0'					; Check it's a HEX character
		JR		C,	HEXTOBIN_ERROR	; Not hex, set error.
		CP		'9'+1
		JR		C,	HEXTOBIN_STRIP		; If between 0 and 9, then we got the right bits in the lower nibble.
		CP		'A'
		JR		C,	HEXTOBIN_ERROR		; Not hex, set error.
		CP		'F'+1
		JR		C,	HEXTOBIN_STRIP2		; Not hex, set error.
		JR		HEXTOBIN_ERROR			; Number higher than "F"
HEXTOBIN_STRIP2:
		ADD		A,$09				; Add 9.
HEXTOBIN_STRIP:
		AND		$0F
		RET
HEXTOBIN_ERROR:
		LD		DE,ERR_EVAL_HEX
		JP		ERROR_OUT			; Is already set for HEX error.
		
		










EVAL_BIN:
		LD		A,(BUFFER+1)
		CP		'%'						; Binary prefix.
		RET		NZ						; Just return if it's not BIN. 

		CALL	EVAL_BIN_VALUE			; Evaluate the Binary valur. 
		POP		HL						; Waste the return address 
		RET								; And exit if we got a hit. 
		
		
		
EVAL_BIN_VALUE:
		LD		A,(BUFFER)				; number of digital in asci binary number. 
		DEC		A
		LD		DE,ERR_EVAL_BIN		; Something went wrong with the hex value.
		JP		Z,ERROR_OUT				; Must be more than 1 character (% symbol)
		CP		17						; Should not be higher than 17 characters = Hex Digit too long. We can make larger for 32 bit numbers if needed. 
										; since this routine is of variable length conversion. 
		JP		NC,ERROR_OUT				; Error Out. Something seriously wrong has occured. 
				
		LD		B,A						; number of characters.
		LD		DE,BUFFER+1			; Before First hex character. 

EVAL_BIN_LOOP:
		INC		DE
		LD		A,(DE)					; Get next HEX value. 
		CP		'0'
		JR		C,BINTOBIN_ERROR		; Less than 0.
		CP		'2'
		JR		NC,BINTOBIN_ERROR		; And not 1 either.
		RRA								; Move the 0 bit into the carry.
		
		LD		HL,VALUE
		RL		(HL)					; Decimal Rotate of Hex Value - Move four bits into place. 
		LD		HL,VALUE+1
		RL		(HL)					; And carry over any extra bits.
		DJNZ	EVAL_BIN_LOOP
		RET		


		
		LD		A,(BUFFER+1)
		CP		'%'						; Hexadecimal prefix.
		RET		NZ
		
		
		RET

BINTOBIN_ERROR:
		LD		DE,ERR_EVAL_BIN
		JP		ERROR_OUT			; Is already set for HEX error.

		


EVAL_DEC:
			; Use a few shifts - only need to add the 8x value and the 2x value to get 10x for each step. Much quicker than using multiply.
			; eg, Sheft Left, Store.
			; Shift Left, Shift Left - Add to store.... Now we have 10x. In a single pass.
			; Note - Decimal is NOT preceeded by anything. If it's not right, we assume it's a label.... If it's not defined, we'll pick that up later. 
EVAL_DEC_VALUE:
		LD		A,(BUFFER)				; number of digital in asci binary number. 
		OR		A
		JR		Z,NOTDECIMAL			; No characters in buffer
		CP		6						; Should not be higher than 5 characters = Dec Digit too long. We can make larger for 32 bit numbers if needed. 
										; since this routine is of variable length conversion. 
		JP		NC,NOTDECIMAL			; Error Out. Something seriously wrong has occured. 
				
		LD		B,A						; number of characters. 1 to 5. 
		LD		DE,BUFFER				; Pre First decimal character. 			

EVAL_DEC_LOOP:
		INC		DE						; Next place in buffer. 
		LD		A,(DE)
		CP		'0'						; Check it's a numeral.
		JR		C,NOTDECIMAL			; Smaller than a 0 is not a decimal number.
		CP		'9'+1
		JR		NC,NOTDECIMAL			; Larger than a 9 is not a decimal number. 
										; After here, the number is from 0 to 9. 
		AND		$0F						; Mask result to binary 4 bits. 
		PUSH	DE						; Store DE.
			LD		HL,(VALUE)			; Get current value in 16 bit word VALUE.
			ADD		HL,HL				; Double it.
			PUSH	HL					; Copy to DE via the stack.
			POP		DE
			ADD		HL,HL
			ADD		HL,HL				; Double it twice more ( 8x )
			ADD		HL,DE				; And add the 2x... Now HL= 10 x VALUE.
			JR		C,DECTOBIN_ERROR	; Any overflow is a bad thing. It will only happen on the last add if it happens. 

			LD		D,$00
			LD		E,A
			ADD		HL,DE	
			JR		C,DECTOBIN_ERROR	; Any overflow is a bad thing. 
			LD		(VALUE),HL			; Store the value with the new 10 x and added 1x
		POP		DE

		DJNZ	EVAL_DEC_LOOP			; And repeat. 

		POP		HL						; If we get this far, there were no errors and we had a decimal number... Waste the previous return and exit. 
		RET								; And exit straight with a valid value. 

NOTDECIMAL:							; If we discover what we're looking at is NOT decimal, we can drop out here. 
		LD		HL,$0000
		LD		(VALUE),HL			; Clear the value that might have been created.... 
		RET							; There is no specific return for not decimal. We just exit and check for other stuff. 




DECTOBIN_ERROR:
		LD		DE,ERR_EVAL_DEC
		JP		ERROR_OUT			; Is already set for DECs error.



EVAL_LABEL:
		CALL	MATCH_LABEL
		JR		C,EVAL_LABEL_OK		; The label was OK and matched. ( And it's value is in VALUE )
										; Don't bomb out on Pass 1. 
		LD		A,(PASS)
		CP		$01						; We can forgive values not being present in PASS 1.
		JR		Z,EVAL_LABEL_FAKE
		RET							; NC from earlier test = NO LABEL. If it's not pass 1, then just exit the label test here, which usually generates an error. 

EVAL_LABEL_FAKE:					; Fake the label being OK for Pass 1, so we can still assembler. We will not let it past Pass 2 though if it's not declared. 
EVAL_LABEL_OK:						; We come here if it's OK also. 
		POP		HL					; Otherwise, we have a value... Exit the scanning routine. 
		RET							; But ret anyway, because if it was a label, it's legit. 
									; Also label might not exist yet, in which case the value might be random.


;;;;; Write Bytes - To a file, an output, a label or other destination.

WRITEBYTE_STORE:	DB	$00				; Temp store for the byte we're writing.

WRITEBYTE:
		LD		HL,(PC)
		LD		DE,(PC_OFFSET)			; We can write to a different location.
		ADD		HL,DE					; ADD them.

		LD		(WRITEBYTE_STORE),A		; Store the byte

;LD	(HL),A 	  							; TEST. Don't write during Pass1 and don't write direct to memory unless switch is on. 

		LD		A,(PASS)
		CP		$01
		JR		Z,DRY_WRITE				; If in pass1, don't write anything. 

		LD		A,(WRITEBYTE_STORE)		; Recover the byte.
		CALL BYTE_TO_FILE				; And write to the output file. 


DRY_WRITE:								; In case we didn't really write it.

		LD		HL,(PC)					; Now step PC forward
		INC		HL
		LD		(PC),HL					; And store the byte since it's a list. 
					
IFNZ	DEBUG
		CALL	WRITEBYTE_SHOWBYTE
ENDIF
		
		LD		HL,(OPCODES)			; How many opcodes did we write?
		INC		HL
		LD		(OPCODES),HL
		RET

IFNZ DEBUG
; Do we want to show what we're writing? (DEBUG mode)
WRITEBYTE_SHOWBYTE:
		CALL	CRLF
		LD	HL,(PC)
		DEC	HL
		PUSH	HL
		CALL	PRINTHEX16
		CALL 	PRINTSPACE
		POP		HL
		LD		A,(HL)
		CALL PRINTHEX
		RET
ENDIF

;WRCODE_SHOWCOMMAND:				; Just prints out the command buffer.... Not really necessary. Might use for debugging again sometime. 
;		CALL	CRLF
;		LD		HL,COMMAND
;		LD		B,8
;WRTOP:
;		PUSH HL
;		PUSH BC
;		LD	A,(HL)
;		CALL	PRINTHEX
;		POP	BC
;		POP HL
;		INC HL
;		DJNZ WRTOP
;		RET

;  Below we assemble the bytes from the command, add a prefix and maybe swap the displacement ( postfix ) into the second last byte. 
WRITECODE:
		LD		A,(PREFIX)				; Was there a prefix for IX or IY? ( Translated to HL by now... ) or for ED commands? Note: BIT commands are NOT treated as a prefix. 
		OR		A
		JR		Z,WRITECODE_NOPREFIX
		CALL	WRITEBYTE				; Write any prefix here.

WRITECODE_NOPREFIX:						; Here's where it gets complex. Not all get swapped. Some are just post. Only those with command 36 or CB are swapped. 
		LD		A,(ADDPOST)
		OR		A
		JR		Z,WRITECODE_NOPOSTFIX	; If there's nothing, just go on. 
		LD		A,(COMMAND+1)
		CP		$36						; LD (i?+d),n is PREFIX 36 d n
		JR		Z,WRITECODE_SWAP
		CP		$CB
		JR		NZ,WRITECODE_NOPOSTFIX	; All Bitwise substitutions are also a d-n Swap. 
					
WRITECODE_SWAP:							; Here's where we swap the Postfix value for the last value in the command stream. 
		LD		HL,COMMAND				; Otherwise we want to insert a code into the command stream and add the postfix.
		INC		(HL)					; Increment the command number of opcodes by 1.						
		LD		E,(HL)
		LD		D,$00
		ADD		HL,DE					; The new end of the command.
		DEC		HL						; Step back 1 and move the byte.
		LD		A,(HL)
		INC		HL
		LD		(HL),A
		LD		A,(POSTFIX)				; Get the byte to insert.
		DEC		HL
		LD		(HL),A					; And insert the displacement ( most likely )
		XOR		A
		LD		(ADDPOST),A				; Don't re-add it. Mark it as done now. 

WRITECODE_NOPOSTFIX:
		LD		A,(COMMAND)
		LD		B,A
		LD		HL,COMMAND+1

WRITECODE_LOOP:
		PUSH	BC
		PUSH	HL
		
		LD		A,(HL)
		CALL	WRITEBYTE				; Write the opcodes for the instruction here... 
				
		POP		HL
		INC		HL
		POP		BC
		DJNZ	WRITECODE_LOOP

		LD		A,(ADDPOST)				; Sometimes we add this to the end instead of swapping as above. 
		OR		A
		RET		Z						; And exit if there's nothing. 
		
		LD		A,(POSTFIX)
		CALL	WRITEBYTE				; But if we still need to, add it on here.

		XOR		A
		LD		(ADDPOST),A				; Shouldn't be needed - but maybe gets missed. 
		
		RET
		
		
		
		
		
		
		
		LD		A,(ADDPOST)
		OR		A
		RET		Z				; No Postfix
		
		LD		A,(POSTFIX)
		CALL	WRITEBYTE				; Write any post information here - ie, Displacement for (IX+d) type commands. 

		ret



;;;;; LONG DIVISION and LONG MULTIPLICATION ROUTINE ;;;;; ------------------------------------------------------------ 16 bit. 

;;;;; LONG DIVISION and LONG MULTIPLICATION ROUTINE ;;;;; ------------------------------------------------------------ 16 bit. 
DIVIDE_SMALLER_NOM:						; Deal with zero results here. Also use this to set things up.
		LD		HL,$00
		LD		(RESULT),HL
		LD		HL,(NOMINATOR)
		LD		(REMAINDER),HL
		RET
DIVIDE_BY_ZERO:
		LD		HL,$FFFF				; Divide by zero means FFFF in everything. 
		LD		(RESULT),HL
		LD		(REMAINDER),HL			; Both FFFF means Divide By Zero attempt. 
		RET

NOMINATOR:		DW	$0000				; Temp store for Nominator
DENOMINATOR:	DW	$0000				; Temp store for Denominator
RESULT:			DW  $0000				; Temp store for the result.
RESULT_H:		DW	$0000				; High Order Bytes for result ( Multiply Cycle )
REMAINDER:		DW	$0000				; Temp store for the remainder. 
DIVIDE:									; Divide HL by DE.... 16 bit divide. 
		LD		(NOMINATOR),HL
		LD		(DENOMINATOR),DE		; Store the original numbers.. We can see them later. We can also reuse these locations for results. Our choice. 
		
		LD		A,L
		OR		H
		JR		Z,DIVIDE_SMALLER_NOM			; Exception for zero. We already know the answer is zero. 
		
		LD		A,E
		OR		D
		JR		Z,DIVIDE_BY_ZERO		; Exception for div by zero. The answer is always infinity... We can just ignore the calculation and note this. 

										; First check the nominator.
		XOR		A						; Clear Carry Flag and Count how far we are down the bit line.
		SBC		HL,DE					; Make sure the denominator is less than the result...
		JR		C,DIVIDE_SMALLER_NOM	; If we hit this problem straight away, the denominator is larger than the Nominator. We know the result already.
		CALL	DIVIDE_SMALLER_NOM		; But we can call it to set up same outcomes at the moment and clear things.
		INC		A						; Make sure we count the first cycle now, because we KNOW it's going to be successful. 
DIVIDE_1:								; In this loop, we shift the denominator left until it's too big to subtract from Nom, then back once.
		LD		HL,(REMAINDER)			; Recover HL to the original, since we use HL for calculations in-loop. 
		OR		A
		RL		E
		RL		D
		JR		C,DIVIDE_2XX				; If we get a rotation carry, DE went 17 bit. Means we're done.
		SBC		HL,DE					; Perform the subtract.
		JR		C,DIVIDE_2				; And exit when DE is bigger than HL otherwise.
		INC		A						; Increment number of final iterations here as we count the number of times we can double DE before it's bigger than HL
		JR		DIVIDE_1				; Do this until we can subtract DE from HL with a remainer and no carry.

		
DIVIDE_2:								; Now we know how many iterations ( ie, Valid Bits ) in the result, we can do long division. 
		OR		A						; Clear carry
DIVIDE_2XX:								; Entry point when we want carry to remain... eg, after rotating off bit 15.
		LD		B,A						; If this works, I can get rid of the Iterations variable.
DIVIDE_2A:
		RR		D						; DE is always twice the size it should be for this calculation after our last tests. 
		RR		E						; This will reduce it to the necessary size to subtract from the Nominator, which is now in remainder. 
		LD		HL,(REMAINDER)
		OR		A						; Clear carry
		SBC		HL,DE					; And perform subtract.
		JR		C,DIVIDE_2B				; Don't store if the operation went negative.
		LD		(REMAINDER),HL
DIVIDE_2B:		
		CCF								; Complement Carry Flag - ie, No Carry means we store a bit in the result table. 
		LD		HL,(RESULT)				; And move the bit into the result. 
		RL		L						; Rotate the bit in from the bottom. 
		RL		H						; Move the result of the calculation into HL
		LD		(RESULT),HL				; And store the result. 
		DJNZ	DIVIDE_2A				; And iterate for each in B. 
										; At the end, Result and Remainder should be set. 
		RET
	




ADDITIVE:		DW	$0000				; We need to store up to 4 bytes of stuff to add to the result.
ADDITIVE_H:		DW	$0000
										; For multiply we end up with a 32 bit number. HL x DE. Use (RESULT) and (RESULT_H) for high value. 
MULTIPLY:
		LD		(NOMINATOR),HL
		LD		(DENOMINATOR),DE		; Store the original numbers.. We can see them later. We can also reuse these locations for results. Our choice. 
		
		LD		HL,$0000
		LD		(RESULT),HL				; Clear 32 bits of result. 
		LD		(RESULT_H),HL
		LD		(ADDITIVE),DE			; The initial additive is DE.
		LD		(ADDITIVE_H),HL			; High byte is zero. Clear and set up the variables. 

		LD		B,16					; We need 16 cycles in total to be sure.
MULTIPLY_LOOP:
		LD		HL,(NOMINATOR)
;		OR		A						; We don't care about incoming bits since we're only testing 16 bits in total. 
		RR		H
		RR		L						; Move HL along.
		LD		(NOMINATOR),HL			; And save it.
		JR		NC,MULTIPLY_SHIFT		; If there's no carry, just shift the additive and loop
		
MULTIPLY_ADD:							; If there was a carry, add the additive. 
		LD		HL,(RESULT)
		LD		DE,(ADDITIVE)
		ADD		HL,DE
		LD		(RESULT),HL
		
		LD		HL,(RESULT_H)
		LD		DE,(ADDITIVE_H)
		ADC		HL,DE
		LD		(RESULT_H),HL

MULTIPLY_SHIFT:
		LD		HL,(ADDITIVE)
		OR		A						; Clear any incoming bits.
		RL		L
		RL		H
		LD		(ADDITIVE),HL
		LD		HL,(ADDITIVE_H)
		RL		L
		RL		H
		LD		(ADDITIVE_H),HL
		
		DJNZ	MULTIPLY_LOOP			; Do this 16 times.
		
		LD		HL,(RESULT)
		LD		DE,(RESULT_H)			; DE = High Order Bytes. ( Multiply is 32 bit ) 
		
		RET
		

; The Label Table begins with 0000 which moves along to the end as it is populated.		
LABEL_TABLE:	DB	$00,$00,'This is the label table.'	; ' This is where the variable block starts...'

	
	

; CPM Calls as EQU functions.
EQU	System_Reset		,	0
EQU	Console_Input		,	1
EQU	Console_Output		,	2
EQU	Reader_Input		,	3
EQU	Punch_Output		,	4
EQU	List_Output			,	5
EQU	Direct_Console_IO 	,	6
EQU	Get_IO_Byte			,	7
EQU	Set_IO_Byte			,	8
EQU	Print_String		,	9
EQU	Read_Console_String	,	10
EQU	Get_Console_Status	,	11
EQU	Return_Version		,	12
EQU	Reset_Disk_System	,	13
EQU	Select_Disk			,	14
EQU	Open_File			,	15
EQU	Close_File			,	16
EQU	Search_For_First	,	17
EQU	Search_For_Next		,	18
EQU	Delete_File			,	19
EQU	Read_Sequential		,	20
EQU	Write_Sequential	,	21
EQU	Make_File			,	22
EQU	Rename_File			,	23
EQU	Return_Login_Vector	,	24
EQU	Return_Current_Disk	,	25
EQU	Set_DMA_Address		,	26
EQU	Get_ADDR_ALLOC		,	27
EQU	Write_Protect_Disk	,	28
EQU	Get_RO_Vector		,	29
EQU	Set_File_Attributes	,	30
EQU	Get_ADDR_DiskParms	,	31
EQU	Set_Get_User_Code 	,	32
EQU	Read_Random			,	33
EQU	Write_Random		,	34
EQU	Compute_File_Size	,	35
EQU	Set_Random_Record	,	36
EQU	Reset_Drive			,	37
EQU	Access_Drive		,	38
EQU	Free_Drive			,	39
EQU	Write_Random_Fill	,	40

; CPM Calls.
;
;
;Function   Entry Value to     Return Value from
; Number    BDOS Passed in       BDOS Passed in 
;DEC  HEX     Function (DE) or (E) regs   (HL) or (A) register
;-------------------------------------------------------------------------
; 0    00 | System Reset           |      ****        |      ****        |
; 1    01 | Console Input          |      ****        | (A)=character    |
; 2    02 | Console Output         | (E)=character    |      ****        |
; 3    03 | Reader Input           |      ****        | (A)=character    |
; 4    04 | Punch Output           | (E)=character    |      ****        |
; 5    05 | Printer Output         | (E)=character    |      ****        |
; 6    06 | Direct Console I/O     | (E)=0FFH is input| (A)=character    |
;         || (E)=chr is output|      ****        |
; 7    07 | Get IOBYTE |      ****        | (A)=IOBYTE       |
; 8    08 | Set IOBYTE | (E)=IOBYTE       |      ****        |
; 9    09 | Display Console String | (DE)=string addr |      ****        |
;10    0A | Input Console String   | (DE)=string addr | (A)=# chr input  |
;11    0B | Get Console Status     |      ****        | (A)=000H idle    |
;         ||      | (A)=0FFH ready   |
;12    0C | Get CP/M Version Number|      ****        | (HL)=Version #   |
;13    0D | Reset Disk Subsystem   |      ****        |      ****        |
;14    0E | Select Disk Drive      | (E)=disk number  |      ****        |
;15    0F | Open a File| (DE)=FCB address | (A)=dir code     |
;16    10 | Close a File           | (DE)=FCB address | (A)=dir code     |
;17    11 | Search for File        | (DE)=FCB address | (A)=dir code     |
;18    12 | Search for Next        |      ****        | (A)=dir code     |
;19    13 | Delete File| (DE)=FCB address | (A)=dir code     |
;20    14 | Read next Record       | (DE)=FCB address | (A)=error code   |
;21    15 | Write next Record      | (DE)=FCB address | (A)=error code   |
;22    16 | Create New File        | (DE)=FCB address | (A)=dir code     |
;23    17 | Rename File| (DE)=FCB address | (A)=dir code     |
;24    18 | Get Login Vector       |      ****        | (HL)=login vector|
;25    19 | Get Logged Disk Number |      ****        | (A)=logged disk  |
;26    1A | Set R/W Data Buff Addr | (DE)=buffer addr |      ****        |
;27    1B | Get Allocation Vector  |      ****        | (HL)=alloc vector|
;         ||      |      address     |
;28    1C | Write Protect Disk     | (E)=disk number  |      ****        |
;29    1D | Get Read Only Vector   |      ****        | (HL)=R/O vector  |
;30    1E | Set File Attributes    | (DE)=FCB address | (A)=dir code     |
;31    1F | Get Addr of Disk Parms |      ****        | (HL)=parm addr   |
;32    20 | Get/Set User Select    | (E)=0FFH get     | (A)=current user |
;33    21 | Read Random Record     | (DE)=long FCB adr| (A)=error code   |
;34    22 | Write Random Record    | (DE)=long FCB adr| (A)=error code   |
;35    23 | Get Size of File       | (DE)=long FCB adr| (r0-2=rec cnt)   |
;36    24 | Set Random Record Num  | (DE)=long FCB adr| (r0-2=rec numb)  |
;37    25 | Reset Drive| (DE)=drive vector|      ****        |
;38    26 | Not used   |      |      |
;39    27 | Not used   |      |      |
;40    28 | Write Random with      | (DE)=long FCB adr| (A)=error code   |
;-------------------------------------------------------------------------
; Bad Error - End of the file is here. I just put this text here as a marker. 

.END ; I always like to mark this.
