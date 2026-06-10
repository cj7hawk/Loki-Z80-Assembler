rem LOKIASM - new Loki Cross-Assembler. Written 2024. David Kitson. 
rem 
rem Call as LOKICROSS <ASMFILE.ASM> <OUTPUT.BIN> /D /F /P 
rem where;	ASMFILE.ASM = The input ASM file.
rem 		OUTPUT.BIN = The output Binary file. 
rem 		Switches;
rem		/H - Output file is in Intel Hex format
REM		/I - Ignore errors. Attempt to continue from the point we started... If necessary keep throwing up more errors. Not implemented yet. 
REM		/P - PRN output format ( note, uses CR without line feed to store line details. )
REM			 PRN Format LLLLL MMMM AA BB CC DD INSTRUCTIONS - Line, Memory, DATA DATA DATA Opcodes. Not implemented yet. 
REM     /O - PRN with more information. 
REM		/C - Output screen responses to CONSOLE.TXT instead of the console. 
REM		/D - Disable output. Unless overwritten by source. 
REM 
REM 	Windows/DOS only functions...
REM		/? None at present. 
REM
REM Parser - Done.
REM Translater - Incomplete.
REM Labels - Incomplete.
REM Maths - Incomplete.
REM Token Analysis - Not Started.
REM
REM BUGS TO FIX.
REM 1. Closing group that points to end of table causes crash and table corruption (eg Group ends at end of table ). 
REM 2. Include without .END instruction locks up before returning down a level.



dim shared ASMFILENAME as string 		: rem Incoming Assembly File NAME
dim shared OUTFILENAME as string		: rem Binary or Hex or Output Filename 
dim shared COMLINE as string			: rem Command line 
dim shared ASMFILE as string 			: rem Incoming Assembly File NAME
dim shared SOURCE as string				: rem What are we currently reading?
dim shared FILEPOINTER as integer		: rem Where we are in the file. As a character position. 
dim shared ERRORMESSAGE as string		: rem Cumulative Error Message. 
dim shared ERRORNUM as integer			: rem Number of errors.
dim shared CODEBASE as string			: rem Representational code locations of 64K.
dim shared CODEPTR as integer			: rem Do I need this? 

rem FLAGS... Yeah, I use integers. But so does the z80 version.
rem dim shared EndOfFile as integer				: rem End Of File. 
dim shared OP as string					: rem Single character operator. Note STRING OPERATOR.
dim shared Special_Operator as string	: rem When we have a special operator ( "" or CHR0 = no operator ). 
dim shared INSTRUCTION as string		: rem Current Instruction. 
dim shared SOURCELINE as string			: rem 64 bytes of buffer for PRN output.
dim shared LINENUMBER as integer		: rem The line in the source that we're matching. 
dim shared BUILD as string				: rem Let's build the machine code. 
dim shared PART1 as string				: rem Operand as PART1.
dim shared PART2 as string				: rem Operand as PART2. 
dim shared EOL as integer				: rem EOL encountered during GETWORD scan.
dim shared F_EOF as integer				: rem File-EOF encountered during GETWORD scan.
dim shared DontIgnoreEol as integer		: rem Flag to NOT ignore EOL as Whitespace when scanning for words. 
dim shared TOEND as integer				: rem Scan buffer TO END OF LINE or operator, etc. Do not terminate on whitespace.
dim shared NOTRANSLATE as integer		: rem DO NOT TRANSLATE IX/IY to HL
dim shared OPCODE as string				: rem BYTE. Leave this as integer to simplify maths. 
dim shared OPCODE2 as integer			: rem More opcode values. 
dim shared OPERAND as string			: rem Byte or Word as STRING. 
dim shared WORD16 as integer			: rem Operand, if it exists, is a WORD and is 16 bits. 
dim shared DISPLACEMENT as string		: rem Exists when there's a displacement. IX and IY instructions with a + or -
dim shared PREFIX1 as string				: rem Byte. Prefix like DD/FD for IX/IY Only ( can combine with CB )
dim shared PREFIX2 as string			: rem Byte. Prefix like ED/CB
dim shared POSTFIX as string			: rem BYTE.
dim shared LabelTable as string			: rem Our Growing Label Table... SAME as the assembly table, but bigger.
dim shared LabelPos as integer			: rem Where in the table are we currently?
rem dim shared LabelEnd as integer			: rem End of the label. 
dim shared N as Integer					: rem 8 bit store.
dim shared a as integer					: rem General Purpose. 
dim shared b as integer					: rem General Purpose.
dim shared c as integer					: rem General Purpose.
dim shared NN as integer				: rem 16 bit store. 
dim shared MM as integer				: rem 16 bit store temp for NN. 
dim shared PC as integer				: rem 16 bit program counter
dim shared TARGETPC as integer			: rem "Virtual Program Counter" that takes offset into account, for relocated code. Affects labels with a : 
dim shared FIRSTBYTE as integer			: rem 16 bit FIRST BYTE - What is the first byte in the code? Establishes where we start exporting code.
dim shared LASTBYTE as integer			: rem 16 bit LAST BYTE - What is the last byte in the code? Establishes where exporting code ends.
dim shared Binarycode as string			: rem Binary representation of the code in a string. 		
 rem 64K bytes of array.
dim shared FAIL as integer				: rem If zero, means the program has not failed to assemble. 1=warning. 2=fatal. 
dim shared INTELHEX as integer			: rem if non-zero means show output as HEX format.
dim shared INTELSTRING as string		: rem Holds a series of characters/bytes for Intel Hex format output. 
dim shared INTELOVERFLOW as string		: rem Store overflow characters.
dim shared CHECKSUM as INTEGER			: rem Checksum for Intel Hex format output.
dim shared INTELPOS as integer			: rem Where we are in the Intel Hex stream. 
dim shared HEXADDRESS as integer		: rem We need to know if the HEXADDRESS has changed mid-stream to close out HEX format output
dim shared INTELSUBSTRING as string		: rem Substring holds the new hex characters from the current write.
dim shared INTELLASTADDRESS as integer	: rem What was the last address we wrote to ?
dim shared PRNFORMAT as integer			: rem if non-zero means show output as PRN. 
dim shared INSTRING as STRING			: rem Signals that we're reading a string from source. Holds the terminator character. 
dim shared GROUP as integer				: rem Signals that we're dealing with a group. 
dim shared CURRENTGROUP as integer		: rem When searching for labels, this is the current group. 

rem Labels variables.
dim shared NextLabel as integer
dim shared LabelLength as integer		
dim shared LabelSize as integer			: rem Length is the text of the label... Size is the distance from this label to the next.
dim shared CurrentLabel as string
dim shared LabelValue as integer
dim shared MacroLength as integer
dim shared MacroText as string		: rem Contents of the last Macro read.
dim shared MacroActive as string	: rem Contents of an active macro. 
dim shared MacroPointer as integer	: rem Where are we in the Macro? 
dim shared InText as string			: rem Note we're IN TEXT at the moment. Keep this up until we're out of text. Expand as a series of values with commas. 
dim shared ThisLabel as integer		: rem In case we update Next Label, Keep track of what THIS label is. 
dim shared LabelValueLocation as integer : rem The location of the label value location. 

dim shared value as Integer				: rem Value of the Buffer, end of calculation, Of a label etc. 

dim shared I8080 as integer				: rem Instructions are 8080 compatible.
dim shared i8 as integer				: rem Instruction is an 8 bit value.
dim shared i16 as integer				: rem Instruction is a 16 bit value. ( I have to work on how I build the instruction ). Or I make a value a string?	

rem FLAGS
dim shared Conditional as integer		: rem Conditional Assembly - Blocks output. 
rem dim shared INQUOTES as integer			: rem We are in QUOTES. - Nope, I used INSTRING for this. 

rem TESTING
dim shared DEBUG as integer				: rem Debug type.  1=initial debug. 


rem System Variables.
dim shared TEMPBASE as integer : rem We get a race condition when setting system variables (LBASE) - Break this. 
dim shared ORGPC as integer
dim shared PCOFF as integer
dim shared XWLOC as integer
dim shared XPASS as integer
dim shared LBASE as integer
dim shared XSYST as integer
dim shared ARGC as integer
dim shared ARG1 as integer
dim shared ARG2 as integer
dim shared ARG3 as integer
dim shared ARG4 as integer
dim shared ARG5 as integer
dim shared ARG6 as integer
dim shared ARG7 as integer
dim shared ARG8 as integer
dim shared ARG9 as integer
dim shared XNEST as integer 
dim shared XDEBUG as integer : rem PRN output. Lower = flags, Upper = characters to show.

rem dim shared pass as integer : rem Store from XPASS.
rem dim shared gpass as integer : rem Global Pass.
dim shared nest as integer : rem nestin level.
dim shared userlabels as integer : rem The location of the first user label. 

dim shared NoUndocs as integer

dim shared InMacro as integer	: rem Flag - we're reading source from a macro.
dim shared MacroName as string	: rem What macro are we executing?
dim shared MacroBytes as integer	: rem How many more bytes should we take from the Macro. 

DIM SHARED SOURCESTORE (30) as string : rem Source Store for recursion.
DIM SHARED POINTERSTORE (30) as INTEGER : rem Source Pointer store for recursion.  
DIM SHARED LINENUMBERSTORE (30) as INTEGER	: rem Line number. 
DIM SHARED PASSSTORE (30) as INTEGER : rem GPASS info... What pass are we one. 
DIM SHARED ONE_MORE (30) as integer : rem Store for One More Time - Recursion in previous routines. 
DIM SHARED Depth as Integer : rem How deep are we into recursion - original source is zero. 
DIM SHARED ONE_MORE_TIME as integer : rem If not 0, then make one more pass at the alternative level. 
DIM SHARED TWO_PASS_ORG as integer : rem temp store for ORG for 2pass. 

DIM SHARED SFILENAME as string : rem get the filename specified in source in "filename.ext" format. 
DIM SHARED BINFILE as string : rem Something for Binary files.
DIM SHARED BINSIZE as integer : rem Count of bytes we will transfer, since CP/M isn't sure about file size. 


DIM SHARED OUTFILE as integer : rem The port for the file output. 

#define PI= 4 * Atn(1)

Function LogError (Byref text as string) as integer
dim result as integer
	errornum=errornum+1
	result=errornum
	Errormessage=errormessage+str (Errornum)+" Line-"+str(linenumber)+":"+text+CHR(&h0A)+CHR(&h0D)

F_EOF=1
EOL=1
FAIL=2 : rem Fatal Error. 

return result
End Function

Function LogWarning (Byref text as string) as integer
dim result as integer
	errornum=errornum+1
	result=errornum
	Errormessage=errormessage+str (Errornum)+" Line-"+str(linenumber)+":"+text+CHR(&h0A)+CHR(&h0D)

FAIL=1 : rem NOT Fatal Error. 

return result
End Function


Function LoadFile(ByRef filename As String) As String                                   : rem Load in a file from the hard disk. Used to load in DISK DSK files.

    Dim h As Integer
    Dim txt As String

    h = FreeFile

    If Open( filename For Binary Access Read As #h ) <> 0 Then Return ""

    If LOF(h) > 0 Then

        txt = String(LOF(h), 0)
        If Get( #h, ,txt ) <> 0 Then txt = ""

    endIf

    Close #h                                                                                   

    Return txt

End Function

Function OpenFile(ByRef filename As String) As Integer                                   : rem Load in a file from the hard disk. Used to load in DISK DSK files.
rem Open a file and return the handle in the response. 
 
	Dim h As Integer
    h = FreeFile

    If Open( filename For Binary Access Write As #h ) <> 0 Then h=0                                                                                

    Return h

End Function

Function GetFileCLI ( ) As String
dim result as string
rem Remove a filename from the CLI command line, and shorten it. 
dim filepos as integer
dim gotslash as integer : rem temp flag to break up switches.

gotslash=0

result=""
for filepos=1 to len(Comline)
if mid(comline,filepos,1)>" " then goto GetFileCLI_Next
next filepos
Goto GetFileCLI_End

GetFileCLI_Next:
if mid(comline,Filepos,1)="/" and gotslash=1 then FilePos=FilePos-1 : goto GetFileCLI_End
result=result+mid(comline,Filepos,1)
if mid(comline,Filepos,1)="/" then gotslash=1 
Filepos=Filepos+1
if Filepos>len(comline) then comline="" : goto GetFileCLI_End
if mid(comline,FilePos,1) > " " then goto GetFileCLI_Next

GetFileCLI_End:
comline=right(comline,Len(comline)-Filepos)
return result
End Function


Function Printhex (Byref image as string, Byref numhex as integer) as integer

        rem Image is the string you want to dump as HEX.
        rem numhex is the number of characters you want to display ( won't be less than 32 displayed... Might adjust that later. )

        dim a as integer
        dim b as integer
        dim c as integer

        print "         !           !           !           !           !           !           !           !           "

        for a=0 to int(((numhex-1)/32))

                print hex$(A*32,4);"  -  ";                             : rem Print relative location in Hex at start of line.

                for b=1 to 32
                        print hex$(asc(mid$(image,(a*32)+b,1)),2);" ";  : rem Print out the hex of the bytes.
                next b

                print "  -  ";

                for b=1 to 32                                                                   : rem Now print out the ASCII characters.
                        c=asc(mid$(image,(a*32)+b,1))
                        if c<32 then c=asc("+")
                        if c>127 then c=asc("+")
                        print chr$(c);
                next b

                print

        next a

        Return len (image)

End function



Function InsertString (Byref Textmain as string, Byref Textadd as string, Byref position as integer) as string
	dim result as string
	result=left(Textmain,position-1)+Textadd+right(Textmain,len(textmain)-len(Textadd)-position+1)
	return result
End Function


REM ******************************************
rem *                                        *
REM * TEXT INPUT AND WORD FORMATION ROUTINES *
rem *                                        *
REM ******************************************

Function Peekchar (Byref TEXTIN as string) as String
rem Return the currently pointed character, but don't move file pointers. 
dim result as string

If Inmacro=0 then
	result=mid(TEXTIN,filepointer,1)
else
	result=mid(MacroText,MacroPointer,1)
endif

if result=chr(9) then result=" " : rem Substitute space for tab.  

Return Result
End Function


Function GetChar (Byref TEXTIN as string) As String
rem Return a single character from the GetChar function
dim result as string


If Inmacro=0 then
	result=mid(TEXTIN,filepointer,1)
	filepointer=filepointer+1
	if filepointer>len(TextIn) then 
		EOL=1
		F_EOF=1
	endif
else
	result=mid(MacroText,MacroPointer,1)
	MacroPointer=MacroPointer+1
	if Macropointer>=len(MacroText) then InMacro=0 : rem Check later that dropping the stream here doesn't break other things. 
endif

if result=chr(9) then result=" " : rem Substitute space for tab.  

Return result
End Function



Function NoWhiteSpace (Byref TEXTIN as string) as string
dim character as string	: rem Return the first character that isn't whitespace. 
rem We want to Strip out any whitespace, EOL or other character before we get to the first real character. ( > &h20 )
dim length as integer	: rem Length of the string.
length=len(TEXTIN)
	
Not_Whitespace_TOP:
rem	character= mid(TEXTIN,FILEPOINTER,1) : rem Get the character next to pickup.
	character=peekchar(TEXTIN)				: rem Peek at the next character. 
	if character > " " then goto Not_Whitespace : rem If it's not a space, tab or control code, then we're done.

	REM Update the LineNumber in case we encounter a few EOLs - They are sometimes whitespace and sometimes not. Depends on dontignoreeol
	if character=chr(13) then 
			If DontIgnoreEOL=1 then 
				DontIgnoreEol=0 : rem reset it. It's a one-shot. 
				GOTO Not_Whitespace : rem If we're looking for a possible comma, Don't Ignore EOL. Treat it as non-whitespace. 
			endif
			LineNumber=LineNumber+1 : rem In case we're ignoring EOL, Increment the line counter now. 
	endif
	
	REM Always be mindful we may have exceeded the File Length - Exit if we're too far. 
	IF FILEPOINTER>LENGTH then 
		EOL=1
		F_EOF=1 
		goto Not_Whitespace : rem We can just exit. Past EOF is NOT whitespace. Who knows what it is?
	Endif	

	if character > " " then goto Not_Whitespace : rem Here's our primary test.  Do this before we step past it. 
	character=getchar(TEXTIN) 				: rem WASTE the next character and progress the pointer. 
	 
	Goto Not_Whitespace_TOP	: rem Loop until satisfaction, EOL or END. 

Not_Whitespace:
Return Character
End Function






Function GetWord (Byref TEXTIN as string) As String
	dim result as string
	dim character as string	: rem use a string so multibyte chars are just one char. 
	dim length as integer	: rem Length of the string.
	dim quote as string

quote=chr(34)
length=len(TEXTIN)
op="" : rem clear any previous operator. 
	
Pretop: 

rem First scan through any whitespace at the present pointer until we find text or something important. 
if instring="" then character=NoWhiteSpace(TEXTIN) : 
	rem The outcome is wasted - We will scan through whitespace and pick up the character at TOP:
	rem ONLY do this when not in a literal string, since in a literal string, there IS no whitespace - just a terminating character. 

TOP:
	character= GetChar(TextIn)	: rem Pick up the next character and move the pointer. 
	if character >=" " then sourceline=sourceline+character	: rem Store the current source line as we read it in. ONLY PRINTABLE. 
rem only process  string if INSTRING <> 0  - otherwise go straight to the Business As Usual routines. 
	If Instring=""	then
		Goto GetWord_Not_String
	endif
	
rem Do we need to close out any string?
	if Instring=Character then
		if notranslate<>0 then 
			result=result+instring : rem In Macro mode, copy the quote. 
			result=result+" " : rem add a space also after the closing quote in Macro Mode.
		endif
		Instring=""
		Character=GetChar(TextIn) : rem Get the next character after the string... Or maybe exit? Could be a comma or an operator. 
rem 	character=" " : rem Make it a space.... 
		Goto GetWord_Not_String
	endif
	
	If character=chr(13) then 
		logerror ("Quotes Unclosed")
		Goto DoNotTranslate
	endif

	if notranslate=0 then 
		result="&"+character : rem Literal Byte - Note I have to check here later there was nothing in RESULT when I do this or error out. 
	
		rem Peek ahead to see if we put a ',' operating in?
		if peekchar(TextIn)<>INSTRING then
			op=","
		ELSE
			Goto TOP	: rem Scan to see what is next? Will be a quote, but we're done. 
		Endif
	else
		result=result+character : rem Copy Verbatim if we're instructed not to translate anything
		Goto 	TOP 	: rem Scan and add until we get the end of string. 
	endif


rem And exit the getword routine from here. We're done. 	
	Goto DoNotTranslate



rem We come here if we're not in a string - ie, Process what we find. 
GetWord_Not_String:	

rem Caps Convert ( lower case to caps )
	If character >= "a" and character <= "z" then character=chr(asc(character)-&h20) : rem Lower case TO CAPS.

rem We come here if the incoming character was not a part of a string.	
select case character
	case ";"
		While PeekChar(TextIn)<>chr(13)
			Sourceline=Sourceline+GetChar(TextIn)
			WEND
			goto DONE
	case "."
		goto TOP	: rem Ignore this character
	case ","
		goto ADDOPERATOR	: rem Comma separator, even if it's not a normal operator. 
	case "+"
		goto ADDOPERATOR
	case "-"
		goto ADDOPERATOR
	case "*"
		goto ADDOPERATOR
	case "\"
		goto ADDOPERATOR
	case "/"
		goto ADDOPERATOR
	case ","
		goto ADDOPERATOR
	case "!"
		goto ADDOPERATOR
	case "@"
		goto ADDOPERATOR
	case "#"
		goto ADDOPERATOR
rem	case "^" 
rem Expand as a numerical number. 
rem		goto ADDOPERATOR
	case "&" 
	rem THIS is a literal designator - Like $ for Hex or % for Binary- This means the next character is literal. ( but printable only )
		result=result+character
		Sourceline=Sourceline+PeekChar(TextIn)
		result=result+getchar(TextIn) : rem store the next character so it gets through as a literal. 
	case "<"
		goto ADDOPERATOR
	case ">"
		goto ADDOPERATOR
	case Special_Operator
		goto ADDOPERATOR
	case ":"
		goto ADDOPERATOR
		
	case "'"
		If result <> "" then LogError ("Unexpected Quote")
		INSTRING=character : rem Note we're in a string type 1 ( single quote )
		Character="" : rem Erase the quote.
		If notranslate <> 0 then result=result+instring : rem But in a macro, still save the quote. 
	case quote
		If result <> "" then LogError ("Unexpected Quote")
		INSTRING=character : rem Note we're in a string type 1 ( single quote )
		Character="" : rem Erase the quote.
		If notranslate <> 0 then result=result+instring : rem But in a macro, still save the quote. 
	case " "
		if TOEND=0 then goto DONE
	case chr(13)
		EOL=1 : rem Mark EOL encountered. Note 13 is the END, not 10... 
		goto DONE			: rem EOL is always a terminator. 
	case "|"
		goto DONE 			: rem It's like EOL but without a new line. 
	case chr(8) : rem TAB?
		if TOEND=0 then goto DONE

	case else

	if character<=" " then character="" : rem Erase ALL whitespace. Whitespace should never be in the returned result. 
	RESULT=RESULT+character
	
end select

	IF FILEPOINTER>LENGTH then 
		EOL=1
if debug=1 then PRINT "END OF FILE ENCOUNTERED"
		F_EOF=1 
		goto DONE	
		Endif	

GOTO TOP : rem And Iterate



ADDOPERATOR:
	op=character
	if FILEPOINTER>LENGTH then EOL=1: F_EOF=1
DONE:
	if NoTranslate<>0 then goto DoNotTranslate

	TOEND=0	: rem Reset any flag to go to the end of the line or next operator. 

	if debug=1 then print "debugpre:";Result

	Select Case result
		Case "IX"
				Result="HL"
				Prefix1=chr(&HDD)
		Case "(IX","(IX)"				
				Result="(HL)"
				Prefix1=chr(&HDD)	
		Case "IY"
				Result="HL"
				Prefix1=chr(&HFD)
		Case "(IY","(IY)"
				Result="(HL)"
				Prefix1=chr(&HFD)			

	Case Else
		Goto DoNotTranslate	: rem It wasn't something to translate. 

	End Select


DoNotTranslate:

rem print "Result:{";result;"}{";op;"}"

Return result	
End Function


Function LABEL16 (Byref location as integer) as integer
	rem Return a 16 bit integer located in the table at LOCATION
	dim result as integer
	dim tval as integer
	result=asc(mid(labeltable,location+1,1)) + (256*asc(mid(labeltable,location+2,1)))
	return result
	end function
Function LABEL8 (Byref location as integer) as integer
	rem Return a 8 bit integer located in the table at LOCATION
	dim result as integer
	dim tval as integer
	result=asc(mid(labeltable,location+1,1))
	return result
	end function
Function LABEL8HIGH (Byref location as integer) as integer
	rem Return a 8 bit integer located in the table at LOCATION+1 ( High value of a 2 byte value ). 
	dim result as integer
	dim tval as integer
	result=asc(mid(labeltable,location+1,1)) + (256*asc(mid(labeltable,location+2,1)))
	return result
	end function	
	
Function String16 (Byref value as Integer) as String
	rem Return a String of two bytes equal to the label as characters.
	dim result as string
	result=chr(value mod 256)+chr(int(value/256))
	return result
	end function

Function SETLABEL16 (Byref location as integer, Byref value as integer) as integer
rem DIRECT - Does not use dynamic locations. 
	dim result as integer
		result=0
		labeltable=Insertstring (labeltable,string16(value),location+1)
	return result
	End Function	

Function SETLABEL8 (Byref location as integer, Byref value as integer) as integer
rem DIRECT - Does not use dynamic locations. 
	dim result as integer
		result=0
		labeltable=Insertstring (labeltable,chr(value),location+1)
	return result
	End Function	

Function SETLABEL8HIGH (Byref location as integer, Byref value as integer) as integer
rem DIRECT - Does not use dynamic locations. 
	dim result as integer
		result=0
		labeltable=Insertstring (labeltable,chr(value),location+2)
	return result
	End Function	
	

Function Pass (byref value as integer) as integer
rem If value=0 then return value.
rem Otherwise set value and return it.
dim result as integer
if value <> 0 then 
		setlabel8(xpass,value)
		result=value
	else
		result=label8(xpass)
	endif
return result
End Function

Function GPass (byref value as integer) as integer
rem If value=0 then return value.
rem Otherwise set value and return it.
dim result as integer
if value <> 0 then 
		setlabel8(xpass+1,value)
		result=value
	else
		result=label8(xpass+1)
	endif
return result
End Function
	

Function HexOut (Byref text as string) as string
	rem Return a string of hex in place of a string of binary.
	dim result as string
	dim count as integer
	if len(text)<1 then result="#": goto hexoutend
	
	for count=1 to len(text)
	result=result+hex(asc(mid(text,count,1)),2)
	next count
HexOutEnd:
	return result
	end function


Function GetNextLabel (Byref MatchLabel as String, Byref Startfrom as Integer) as Integer
rem returns pointer to the label entry in the label table - Returns 0 if label does not exist. 
dim GroupTest as integer
	dim result as integer 
	result=Startfrom : rem First byte in table. We will search through. 
	
	LabelValue=-1 : rem Indicate the value did NOT get assigned. 
	
	while result < len(labeltable)-1 and result <> 0
	rem Fetch the current label values. 
			NextLabel=label16(result)
			LabelLength=label8(result+2) and &h07F : rem mask out group bit. 
			LabelSize=NextLabel-Result				: rem Full Label Size... Used when deleting labels. 
			currentgroup=label8(result+2) and &h80
			CurrentLabel=mid(labeltable,result+4,LabelLength)
			LabelValue=Label16(result+3+LabelLength)
			MacroLength=NextLabel-Result-LabelLength-5 : rem 5 numerical places, the label and the difference in size.
			MacroText=mid(labeltable,result+6+LabelLength,MacroLength)
			ThisLabel=result
			LabelValueLocation=result+3+LabelLength
			
			if Matchlabel=CurrentLabel or MatchLabel="*" then 
				goto GETEND
				endif	
			result=NextLabel		
	wend

	result=0 : currentgroup=0 : rem Bad Result. Label not present.
GETEND:
return result
End Function

Function GetLabel (Byref MatchLabel as String) as integer
dim result as integer
	result=GetNextLabel(Matchlabel,label16(LBASE)) : rem Real table starts at &h0020 into the string. 
	return result
End Function


Function markgroup (Byref text as string) as string
rem Return a string with Bit 7 set on the byte counter for the buffer.
rem so 01 in the count = 1 character. 129 in the count= 1 character + it's a group.
dim result as string

return result
End Function



Function Groupcheck (Byref value as integer) as integer
dim result as integer



return result
End Function


Function PrintLabel () as integer

	Print hex(ThisLabel,4);">";
	Print hex(NextLabel,4);
	If MacroLength<>0 and currentgroup=0 then print "~"; : Rem Macro
	If currentgroup <> 0  and macrolength=0 then print "*"; : rem Group Open 
	If currentgroup <> 0 and macrolength <> 0 then print "#"; : rem Group HIDDEN ( HIDDEN )
	If Currentgroup+Macrolength=0 then print " ";
	Print hex(LabelValue,4);" ";
	Print CurrentLabel;" ";
	
	if Macrolength>0 and currentgroup=0 then 
		print left(MacroText,labellength) : rem Cut off GROUP data if closed. 
	else
		print
	endif

return 0
End Function

Function SetLabel (Byref LabelName as string, Byref Value as integer) as Integer
rem Sets the value of a label. Returns -1 if the label didn't exist. 
	dim result as integer
	result=-1 : rem Error default
		Getlabel (LabelName) : rem Set the label to the correct pointer. 
		if NextLabel=0 then logerror(" : SET Label Not Found.") : goto SetLabelExit : rem Can't set label - doesn't exist.
		LabelTable=insertstring (labeltable,string16(Value),ThisLabel+4+LabelLength)
	result=1 : rem Result=good. 
SetlabelExit:
return result
End function

Function OpenGroup (Byref LabelName as string) as Integer
rem Swaps the next-label and label-value for GROUPS only, if the next label is bigger than the label value. 
rem NextLabel=Location of next label - first two bytes of label.
rem LabelValue=Value of label.
	dim result as integer
	result=-1 : rem Error default
	Getlabel (LabelName) : rem Set the label to the correct pointer. 
	if NextLabel=0 then 
		Logerror (labelname+"-Group Not Found.") : goto SetLabelExit : rem Can't set label - doesn't exist.	
	else
		if CurrentGroup <> 0 then
			if nextlabel> labelvalue then

rem			print "LabelTable Nextlabel:";hex(Nextlabel,4);"  LabelValue:";hex(labelvalue,4)
rem			print "Thislabel:";hex(thislabel,4)
rem			print "LabelLength:";hex(labellength,4)
rem			print "Value Location:";hex(thislabel+labellength+3,4)

			
				LabelTable=insertstring (labeltable,string16(LabelValue),ThisLabel+1)
				LabelTable=insertstring (labeltable,string16(NextLabel),ThisLabel+4+LabelLength)					
				result=1 : rem Result=good. 
			endif
		else
			logwarning ("Not a Group Label")
		endif
	endif
SetlabelExit:
return result
End function

Function CloseGroup (Byref LabelName as string) as Integer
rem Swaps the next-label and label-value for GROUPS only, if the next label is bigger than the label value. 
rem NextLabel=Location of next label - first two bytes of label.
rem LabelValue=Value of label.
	dim result as integer
	result=-1 : rem Error default
	Getlabel (LabelName) : rem Set the label to the correct pointer. 
	if NextLabel=0 then 
		Logerror (labelname+"-Group Not Found.") : goto SetLabelExit : rem Can't set label - doesn't exist.	
	else
		if CurrentGroup <> 0 then
			if nextlabel< labelvalue then

rem			print "LabelTable Nextlabel:";hex(Nextlabel,4);"  LabelValue:";hex(labelvalue,4)
rem			print "Thislabel:";hex(thislabel,4)
rem			print "LabelLength:";hex(labellength,4)
rem			print "Value Location:";hex(thislabel+labellength+3,4)

				LabelTable=insertstring (labeltable,string16(LabelValue),ThisLabel+1)
				LabelTable=insertstring (labeltable,string16(NextLabel),ThisLabel+4+LabelLength)				
				result=1 : rem Result=good. 
			endif
		else
			logwarning ("Not a Group Label")
		endif
	endif
SetlabelExit:
return result
End function


Function EndGroup (Byref LabelName as string) as Integer
rem Swaps the next-label and label-value for GROUPS only, if the next label is bigger than the label value. 
rem NextLabel=Location of next label - first two bytes of label.
rem LabelValue=Value of label.
	dim result as integer
	result=-1 : rem Error default
	Getlabel (LabelName) : rem Set the label to the correct pointer. 
	if NextLabel=0 then 
		Logerror (labelname+"-Group Not Found.") : goto SetLabelExit : rem Can't set label - doesn't exist.	
	else
		if CurrentGroup <> 0 then
				SETLABEL(LABELNAME,LEN(LABELTABLE)-2)
				result=1 : rem Good. 
		else
			logwarning ("Not a Group Label")
		endif
	endif
SetlabelExit:
return result
End function

Function ValLabel (Byref LabelName as string) as Integer
rem Returns the value of the label.
	dim result as integer
	result=0 : rem Error default
		Getlabel (LabelName) : rem Set the label to the correct pointer. 
		if NextLabel=0 then  Logerror (LabelName+" VAL Label not found.") : goto SetLabelExit : rem Can't find label - doesn't exist.
		result=LabelValue : rem If the label was valid, we can get the result. 
SetlabelExit:
return result
End Function

Function IncLabel (Byref LabelName as string) as Integer
rem Returns -1 if an error, or returns 0. 
	dim result as integer
	result=-1 : rem Error default
		Getlabel (LabelName) : rem Set the label to the correct pointer. 
		if NextLabel=0 then goto SetLabelExit : rem Can't find label - doesn't exist.
		
		SetLabel(Labelname,ValLabel(Labelname)+1)
		
SetlabelExit:
return result
End Function


Function Addlabel (Byref text as String, Byref Value as integer) as integer
rem Result returned is the start location of the label. 
	dim result as integer
	dim tempstring as string 		:rem A temporary string for construction.
	dim newnext as integer			:rem New next label location.

	result=len(labeltable)-2 : rem Return location of new label. It will always end with 00, and LEN=2, so position1 is the start. We erase the old 00 when we start a new label. 
	tempstring=chr(len(text)+group)+text+string16(value)
	newnext=result+len(tempstring)+2 : rem +2 for the pointer
	tempstring=string16(newnext)+tempstring+chr(0)+chr(0)	: rem End of label is 00. 
	labeltable=left(labeltable,len(labeltable)-2)+tempstring

	return  result
End Function

Function BinCon (Byref text as string) as integer	
rem Read in a string, starting with % and convert to a binary number.
dim result as integer
dim steps as integer

	result=0
	if len(text)>1 then
		for steps=2 to len(text)
			result=result*2	: rem Shift left for Binary conversion - we start with 0.
			if mid(text,steps,1)<"0" or mid(text,steps,1)>"9" then logerror("Binary conversion failure. Bad character")
			result=result+val(mid(text,steps,1))
		next steps
	else
		Logerror("Binary conversion error. No value") 
	endif

	if steps > 18 then logerror("Binary number too large.")
	if result > 65535 then logerror("Number too large.")
return result
End Function


Function HexCon (Byref text as String) as integer
rem Read in a string, starting with $ and convert to a hex number.
dim result as integer
dim steps as integer
dim tval as integer : rem temp val
dim tchar as string : rem temp char

	result=0
	if len(text)>1 then
		for steps=2 to len(text)
			result=result*16	: rem Shift left for HEX conversion - we start with 0.
			tchar=mid(text,steps,1)
			select case tchar
				case "0","1","2","3","4","5","6","7","8","9"
					tval=asc(tchar)-48
				case "A","B","C","D","E","F"
					tval=asc(tchar)-55
				case else
					tval=0
					Logerror("Hex conversion error. Bad character encountered."	) 
			end select

			result=result+tval
		next steps
	else
		Logerror("Hex conversion error. No value")
	endif

	if steps > 6 then Logerror("Hex number too large.")
	if result > 65535 then Logerror("Number too large.")
return result
End Function


Function DecCon (Byref text as String) as integer
rem Read in a string, starting with $ and convert to a Decimal number. Or reference a label. 
dim result as integer
dim steps as integer
dim tval as integer : rem temp val
dim tchar as string : rem temp char

	tval=0
	result=0
	if len(text)>0 then
		for steps=1 to len(text)
			result=result*10	: rem Shift left for DEC conversion - we start with 0.
			tchar=mid(text,steps,1)
			select case tchar
				case "0","1","2","3","4","5","6","7","8","9"
					tval=asc(tchar)-48
				case else
					tval=-1	: rem note it's not a decimal value. 	
					result=-1
					goto BYPASSLOOP : rem Don't step through number if it's not a number. Maybe I should use While. 
			end select
			result=result+tval
		next steps
BYPASSLOOP: : rem No steps here if we bypass. 
	else
		LogError ("Decimal or Value conversion error. No value. ["+text+"]")
		rem No Characters... 
	endif
	
	if tval=-1 then 	
		if getlabel(text)=0 and pass(0) <> 1 then LogError ("Label does not exist:>"+text+"<>"+	Part1+OP+Part2+"<") 
		result=LabelValue
	endif
	if result=-1 then 
		if pass(0)<>1 then Logerror("Value did not get assigned. Label may not exist.")	
		result=&hFFFF
	endif	
	if result > 65535 then LogWarning ("Number too large.") : rem Warning. 
	
return result
End Function

Function Eval (Byref Textin as String) as Integer
rem Evaluation Function.
dim result as Integer
dim lastop as string : rem we need to know what the previous operator was if we recursively pick up terms.
dim LeftMost as string : rem For numbers, etc.
dim LastValue as integer	: rem The value we're working on. 

	if Textin="" then Textin="0" : rem If we don't have a value, then it's ZERO. This allows for leading operators. 
	lastop="NUL" : rem We don't have a last operator yet...  We only have a single value. Whatever was provided in the call.

	REEVAL:		: rem Top of loop. In case we recursively evaluate. 

	if textin="^" then
		rem Substitution of ^ for PC value. 
		textin=str(label16(orgpc))
	endif 
	
		LeftMost=left(Textin,1)

		rem Get the value of the current token/label/value. 
		Select CASE LeftMost
			Case "&"
				rem Literal.
				Value=asc(mid(textin,2,1))				
			Case "%"
				rem Binary.
				Value=BinCon(Textin)
			Case "$"
				rem Hexadecimal.
				Value=HexCon(Textin)
			Case Else
				rem Decimal or Label. Check for decimal, or default to Label. If neither, error out. 			
				Value=DecCon(Textin) 
		End Select

		if debug=1 then Print "The value we got was:";value
		if debug=1 then Print "Tracking Value:";lastvalue,lastop,value,"=",

		Select CASE lastop
			Case "+"
				value=lastvalue+value
			Case "-"
				value=lastvalue-value
			Case "*"
				value=lastvalue*value
			Case "/"
				value=lastvalue/value
			Case "!"
				value=(65535-lastvalue) and 65535
			Case "@"
				value=lastvalue and value
			Case "<"
				value=(lastvalue*2) and 65535
			Case ">"
				value=(lastvalue/2) and 65535
			Case "#"
				value=lastvalue OR value
rem			Case "^"
rem			rem Program Counter.
rem				label16(ORGPC)
rem				value=LabelValue
			Case "\"
				value=lastvalue MOD value
			Case ")"
				Value=Lastvalue
			Case "Nul"
				rem Do Nothing... It's a null value. 
			Case Else
				rem Do nothing...  Or what do I do? 
		End Select

if debug=1 then	Print value,op,lastop,"$$$"

		if op <> "" and op <> ")" and op <> "," then 
			lastop = op	: rem Preserve the last value and op - they are relevant if we get another. 
			lastvalue = value
			toend=1
			DontIgnoreEol=1
			textin=getword(SOURCE) : rem Strip out spaces - Look for operators. We've set ToEnd=1 manually here   and DontIgnoreEOL also so we don't mix lines. 
			
			goto REEVAL : rem No further ops, or at end of bracketed statement. 
		endif

		result=value	: rem Transfer the value to the result. 
		
return result
End Function


Function GetwordToEnd (Byref Textin as String) As String
dim result as string
dim tempcomma as string
dim displace as integer : rem Make an integer first so we can bounds check the displacement. 
rem Set Special functions here - eg, Flags to change operation. 
	TOEND=1	: rem Note we want to NOT recognize whitespace as a terminator of the input. 

	result=Getword(textin)
	if result="(HL)" and PREFIX1 <> "" then
	rem We do this if it's clearly (IX, (IX), (IY or (IY) 
		if op="-" or op="+" then
			Special_Operator=")" : rem ADD ) to operator list. 
			displace=EVAL(""): rem Send starting "" to EVAL to start as "0" - eg, 0+ or 0-
			if displace<-128 or displace>127 then logerror ("Index Usage Invalid. -128..127 only")
			displace=displace and &hFF : rem Mask to 8 bits.
			displacement=chr(displace)
			Special_Operator="" : rem REMOVE ) from operator list. 
			
			if OP <> ")" then logerror ("Missing Brackets")		
			
			DontIgnoreEol=1 : rem There MIGHT be a comma, or there MIGHT me an EOL or who knows what ? Don't search past EOL. 
			tempcomma=getword(source) : rem Just to clear out the comma we know will follow ( and we can check it )
									: rem It will still set OP to "," if all is OK. 
rem		else
rem			LogError ("Index Usage Invalid")
rem Used to identify exceptions here, but now accept both forms of (IX) with and without an index. 
		endif
	endif
	
return result
End Function


Function BracketsEval (Byref Textin as String) as Integer
rem Just calls EVAL but removes the brackets first.
dim result as integer
	Textin=right(textin,len(textin)-1)
	Textin=Left(textin,len(textin)-1) : rem Remove both brackets.
	Special_Operator=")"
	result=Eval(textin)	: rem Get the value in the brackets.
	Special_Operator=""
return result		
End Function

Function OneBracketEval (Byref Textin as String) as Integer
rem Just calls EVAL but removes the LEFT BRACKET ONLY first.
dim result as integer
	Textin=right(textin,len(textin)-1)
rem	Textin=Left(textin,len(textin)-1) : rem Remove both brackets.
	Special_Operator=")"
	result=Eval(textin)	: rem Get the value in the brackets.
	Special_Operator=""
	if OP=")" then 
		DontIgnoreEol=1 : rem In case we're at the back of an expression, we don't want to go past the EOL
		if getwordtoend(source)<> "" then logerror ("Unexpected characters in expression")
	endif
return result		
End Function

Function CheckComma (Byref text as string) as string
dim result as string
	result=""
	if text <> "," then logerror ("Comma or trailing argument missing.")
return result
End Function



Function Reg (Byref text as string) as integer
rem Return a value to add to a base value depending on register selection
dim result as integer
	Select case text
		case "B"
			result=&h00
		case "C"
			result=&h01
		case "D"
			result=&h02
		case "E"
			result=&h03
		case "H","IXH","IYH"
			result=&h04
			if text="IXH" and noundocs=0 then LogWarning ("Undocumented Opcode: IXH")
			if text="IYH" and noundocs=0 then LogWarning ("Undocumented Opcode: IYH")
		case "L","IXL","IYL"
			result=&h05
			if text="IXL" and noundocs=0 then LogWarning ("Undocumented Opcode: IXL") 
			if text="IYL" and noundocs=0 then LogWarning ("Undocumented Opcode: IYL")
		case "(HL)"
			result=&h06
		case "A"
			result=&h07
		case else
			result=-1 : rem Not found. 
	End select
return result
End Function


Function RegPair (Byref text as string) as integer
rem Return a value to add to a base value depending on register selection
dim result as integer
	Select case text
		case "BC"
			result=&hC0
		case "DE"
			result=&hD0
		case "HL"
			result=&hE0
		case "AF"
			result=&hF0
		case else
			result=-1
	End select
return result
End Function

Function RegPairSP (Byref text as string) as integer
rem Return a value to add to a base value depending on register selection
dim result as integer
	Select case text
		case "BC"
			result=&h00
		case "DE"
			result=&h10
		case "HL"
			result=&h20
		case "SP"
			result=&h30
		case else
			result=-1
	End select
return result
End Function


Function RegPairBR (Byref text as string) as integer
rem Return Register pair with brackets....... eg, (DE), (BC). 
dim result as integer
	Select case text
		case "(BC)"
			result=&h00
		case "(DE)"
			result=&h10
		case else
			result=-1
	End select
return result
End Function

Function PRNOUTPUT (byref addtext as string) as string
dim OUTLINE as string
		OUTLINE=""
		OUTLINE=OUTLINE+" Gp:"+HEX(GPASS(0),2)+HEX(PASS(0),2)+" "
		OUTLINE=OUTLINE+"Lv:"+HEX(LABEL8(XNEST),2)+" "
		OUTLINE=OUTLINE+"Ln:"+right("00000"+STR(LineNumber),5)+" "
		OUTLINE=OUTLINE+hex(TARGETPC,4)+" "
		OUTLINE=OUTLINE+hex(PC,4)+"  "
		OUTLINE=OUTLINE+hexout(Build)+"                    "
		OUTLINE=LEFT(OUTLINE,Label8High(XDEBUG)) : rem Length was hardcoded - Now is Label8High(xdebug)
		if Conditional=1 then
			OUTLINE=OUTLINE+"-" 
		else
			OUTLINE=OUTLINE+" "
		endif
		OUTLINE=OUTLINE+left(sourceline,36) : rem Limit the PRN file to 80 columns. 
		PRINT OUTLINE
		
return OUTLINE
End Function

rem #######################################################
rem #######################################################
rem ##                                                   ##
rem ##  Subroutines start here.                          ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem #######################################################
rem #######################################################

Sub Showlabels
REM Show all the labels in the label table.
rem	Print "Label Table."
rem	Print "Label Length:";len(LabelTable)

rem	printhex (LabelTable,Len(Labeltable))
rem	print
	
	Getlabel "*"
	
	While NextLabel <> 0 
		PrintLabel
		GetNextLabel("*",NextLabel)
		Wend
		
	print

		
End Sub


Sub BuildLabels
rem Establish assembler System Variables. 
	Labelpos=1	: rem First Label.

	ADDLABEL ("NULL0123456789ABCDEF0123456",&hFFFF) : Rem Null Label so the table starts at $0020 rather than $0000, so it all fits nicely. Then put this value into Labelbase. 
	GROUP=&h80
	ADDLABEL ("XSYSTEM",&h0000) : rem Value 0 until we reset it to the User Label start location.
rem	Print "XSYSTEM Added"
	GROUP=&h00
	ADDLABEL ("ORGPC",&h0000)	: rem Default ORG if not specified is $0000
	ADDLABEL ("PCOFF",&h0000)	: rem PC Offset starts at 0000
	ADDLABEL ("XWLOC",&h0000)	: rem 
	ADDLABEL ("XPASS",&h0000)	: rem 

	LBASE=LEN(LABELTABLE)-2+3+len("LBASE")		: rem Record where LBASE will go. 
	ADDLABEL ("LBASE",&h0000)	: rem 
	SETLABEL16(LBASE,&h0020)	: rem set initial value to %h0020
								: rem Note that LBASE Must NEVER change - it's a pointer to the variable in the label base - though the value of Labelbase can be anything. 
								: rem At the moment, the base starts at $0020. 

	ADDLABEL ("XSYST",&h0000)	: rem 
	ADDLABEL ("ARGC",&h0000)	: rem How many arguments contained in macro or include?
	ADDLABEL ("ARG1",&h0001)	: rem The arguments broken down from comma separated form. arg1, arg2, arg3 All integers. 
	ADDLABEL ("ARG2",&h0002)	: rem 
	ADDLABEL ("ARG3",&h0003)	: rem 
	ADDLABEL ("ARG4",&h0004)	: rem 
	ADDLABEL ("ARG5",&h0005)	: rem 
	ADDLABEL ("ARG6",&h0006)	: rem 
	ADDLABEL ("ARG7",&h0007)	: rem 
	ADDLABEL ("ARG8",&h0008)	: rem 
	ADDLABEL ("ARG9",&h0009)	: rem 
	ADDLABEL ("XNEST",&h0000)	: rem 
	ADDLABEL ("XDEBUG",&h0000)	: rem PRN output control. 

rem Get system variable locations in table for "Fast Access" even if they are turned off. 
		ORGPC=GETLABEL("ORGPC")+3+len("ORGPC") : rem Locate the label value directly for system variables. 
		PCOFF=GETLABEL("PCOFF")+3+len("PCOFF") : rem Locate the label value directly for system variables. 
		XWLOC=GETLABEL("XWLOC")+3+len("XWLOC") : rem Locate the label value directly for system variables. 
		XPASS=GETLABEL("XPASS")+3+len("XPASS") : rem Locate the label value directly for system variables. 
rem		LBASE=GETLABEL("LBASE")+3+len("LBASE") : rem Locate the label value directly for system variables. 
		XSYST=GETLABEL("XSYST")+3+len("XSYST") : rem Locate the label value directly for system variables. 
		ARGC=GETLABEL("ARGC")+3+len("ARGC") : rem Locate the label value directly for system variables.
		ARG1=GETLABEL("ARG1")+3+len("ARG1") : rem Locate the label value directly for system variables.
		ARG2=GETLABEL("ARG2")+3+len("ARG2") : rem Locate the label value directly for system variables.
		ARG3=GETLABEL("ARG3")+3+len("ARG3") : rem Locate the label value directly for system variables.
		ARG4=GETLABEL("ARG4")+3+len("ARG4") : rem Locate the label value directly for system variables.
		ARG5=GETLABEL("ARG5")+3+len("ARG5") : rem Locate the label value directly for system variables.
		ARG6=GETLABEL("ARG6")+3+len("ARG6") : rem Locate the label value directly for system variables.
		ARG7=GETLABEL("ARG7")+3+len("ARG7") : rem Locate the label value directly for system variables.
		ARG8=GETLABEL("ARG8")+3+len("ARG8") : rem Locate the label value directly for system variables.
		ARG9=GETLABEL("ARG9")+3+len("ARG9") : rem Locate the label value directly for system variables.
		XNEST=GETLABEL("XNEST")+3+len("XNEST") : rem Locate the label value directly for system variables. 
		XDEBUG=GETLABEL("XDEBUG")+3+len("XDEBUG") : rem Locate the label for the system. 
		
	
	rem User labels start here - Set marker for XSYSTEM so it can be turned on and off.
	rem GETLABEL ("XSYSTEM")
	SETLABEL ("XSYSTEM",Len(LabelTable)-2) : rem Set the label XSYSTEM to the value defined by the current end of the label table, so system labels can be bypassed.
rem	SETLABEL ("LBASE",&h0020) : rem Label base location. 
rem 	SHOWLABELS
	
End Sub





Sub	Arithmetic	
rem for the A, type Arithmatic instructions without explicit A, ( eg SUB B )

					Part2=GetwordToEnd (Source)


					if reg(Part2) >= 0 then
						opcode=chr(asc(opcode)+Reg(Part2))
					else
						nn=eval(Part2)
						Operand=chr(nn)
						opcode=chr(asc(opcode)+&h46)
					endif

End Sub

Sub ACommaTarget			
rem For Arithmetic Instructions, involving A, eg, ADD A,?
					Part1=GetWordToEnd (Source)
					Checkcomma (op)
					Part2=GetwordToEnd (Source)

					if Instruction="ADD" and Part1="HL" then opcode=chr(&h09+RegPairSP(Part2)): GOTO COMMAEND
					if Instruction="SBC" and Part1="HL" then Prefix2=chr(&hED) : opcode=chr(&h42+RegPairSP(Part2)): GOTO COMMAEND
					if Instruction="ADC" and Part1="HL" then Prefix2=chr(&hED) : opcode=chr(&h4A+RegPairSP(Part2)): GOTO COMMAEND					
					if Part1="A" and reg(Part2)>=0 then opcode=chr(asc(opcode)+Reg(Part2)) : GOTO COMMAEND
					if Part1="A" then
						opcode=chr(asc(opcode)+&h46)
						operand=chr(eval(Part2))
						GOTO COMMAEND
					endif

					LogError "Invalid Register"

					COMMAEND:
End Sub

Sub Test_Ret
rem Look for a condition after a RET since it may not be alone (ie, wasn't RET followed by EOL ).

IF (EOL<>1) then
	rem TEST EOL first, since we might be at the end anyway, so no condition. 
	DontIgnoreEol=1
	PART1=GetWordToEnd(SOURCE) : rem DON'T search past EOL. 
ENDIF

select case PART1
rem Look for a condition - eg, Z NZ, C, NZ.
		CASE	"NZ"
			opcode=chr(&hC0)

		CASE	"Z"
			opcode=chr(&hC8)

		CASE	"NC"
			opcode=chr(&hD0)

		CASE	"C"
			opcode=chr(&hD8)

		CASE	"PO"
			opcode=chr(&hE0)

		CASE	"PE"
			opcode=chr(&hE8)

		CASE	"P"
			opcode=chr(&hF0)

		CASE	"M"
			opcode=chr(&hF8)
			
		CASE ""
			opcode=chr(&hC9)
			
		CASE else	
			logerror("Condition not recognized.")
	end select
	
if op<>"" then logerror("Numerical operator encountered or other unrecognized symbols.")
	
End Sub

Sub Test_JP
PART1=getwordtoend(SOURCE)  
rem Print "Part1:";PART1

select case PART1
rem Look for a condition - eg, Z NZ, C, NZ.
		CASE	"NZ"
			opcode=chr(&hC2)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  

		CASE	"Z"
			opcode=chr(&hCA)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"NC"
			opcode=chr(&hD2)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"C"
			opcode=chr(&hDA)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"PO"
			opcode=chr(&hE2)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"PE"
			opcode=chr(&hEA)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"P"
			opcode=chr(&hF2)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"M"
			opcode=chr(&hFA)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"(HL)"
rem		PRINT "Got JP (IX)"
			Opcode=chr(&hE9)
			Goto TestJPEnd
			
		CASE else	
			
			opcode=chr( &hC3)	: rem Set default JP
			
	end select

	NN=Eval(Part1)	: rem Get the jump target.
	Operand=String16(NN)
	Word16=1	: rem 16 bit operand. 
	
if op<>"" then logerror("Numerical operator encountered or other unrecognized symbols.")
	
TestJPEnd:
End Sub



Sub Test_CALL
PART1=getwordtoend(SOURCE)  
rem Print "Part1:";PART1

select case PART1
rem Look for a condition - eg, Z NZ, C, NZ.
		CASE	"NZ"
			opcode=chr(&hC4)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  

		CASE	"Z"
			opcode=chr(&hCC)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"NC"
			opcode=chr(&hD4)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"C"
			opcode=chr(&hDC)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"PO"
			opcode=chr(&hE4)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"PE"
			opcode=chr(&hEC)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"P"
			opcode=chr(&hF4)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE	"M"
			opcode=chr(&hFC)
			checkcomma (OP)
			PART1=getwordtoend(SOURCE)  
			
		CASE else	
			
			opcode=chr( &hCD)	: rem Set default CALL
			
	end select

	NN=Eval(Part1)	: rem Get the jump target.
	Operand=String16(NN)
	Word16=1	: rem 16 bit operand. 
	
if op<>"" then logerror("Numerical operator encountered or other unrecognized symbols.")
	

End Sub


Sub TEST_RST
	NN=Eval(GetWordToEnd(Source))
	Select Case NN 
		Case 0
			Opcode=chr(&hC7)
		Case 8
			Opcode=chr(&hCF)
		Case 16
			Opcode=chr(&hD7)
		Case 24
			Opcode=chr(&hDF)
		Case 32
			Opcode=chr(&hE7)
		Case 40
			Opcode=chr(&hEF)
		Case 48
			Opcode=chr(&hF7)
		Case 56
			Opcode=chr(&hFF)			
		Case Else
			LogError ("RST Invalid")
	End Select

End Sub


SUB Test_In
	Part1=GetWordToEnd(Source)
	If Part1="(C)" then
		Rem Undocumented IN (C)
		Prefix2=chr(&hED)
		Opcode=chr(&h70)
		if noundocs=0 then LogWarning ("Undocumented Opcode: IN (C) Line:"+STR(LINENUMBER)) 
		Goto TestInEnd
	Endif
	
	Checkcomma (OP)
	Part2=GetWordToEnd(Source)
	
	If Part2="(C)" then
		Prefix2=chr(&hED)	: rem Set Prefix for After ED.
		Select Case Part1
			Case "B"
				Opcode=chr(&h40)
			Case "C"
				Opcode=chr(&h48)
			Case "D"
				Opcode=chr(&h50)
			Case "E"
				Opcode=chr(&h58)
			Case "H"
				Opcode=chr(&h60)
			Case "L"
				Opcode=chr(&h68)
			Case "A"
				Opcode=chr(&h78)
		End Select
	else
		NN=BracketsEval(Part2)
		Opcode=chr(&hDB)
		Operand=chr(NN)
	Endif
	
TestInEnd:
End Sub

Sub	Test_Out
	Part1=GetWordToEnd(source)
	Checkcomma (OP)
	Part2=GetWordToEnd(source)
	
	if Part1="(C)" then
		Prefix2=chr(&hED)
	
		Select Case Part2
			Case "B"
				Opcode=chr(&h41)
	
			Case "C"
				Opcode=chr(&h49)

			Case "D"
				Opcode=chr(&h51)

			Case "E"
				Opcode=chr(&h59)

			Case "H"
				Opcode=chr(&h61)

			Case "L"
				Opcode=chr(&h69)

			Case "0"
				Opcode=chr(&h71)
				if noundocs=0 then LogWarning ("Undocumented Opcode: OUT (C),0 Line:"+STR(LINENUMBER)) 

			Case "A"
				Opcode=chr(&h79)
		
		End Select
	
	else
		NN=BracketsEval(Part1)
		Opcode=chr(&hD3)
		Operand=chr(NN)
	endif
End Sub


Sub INC_Opcode
	TOEND=1: rem Ignore spaces here. 
	PART1=GETWORDTOEND(SOURCE)
	Select CASE Part1
		CASE	"BC"
			opcode=chr( &h03)
		CASE	"DE"
			opcode=chr( &h13)
		CASE	"HL"
			opcode=chr( &h23)
		CASE	"SP"
			opcode=chr( &h33)
		CASE	"B"
			opcode=chr( &h04)
		CASE	"C"
			opcode=chr( &h0C)
		CASE	"D"
			opcode=chr( &h14)
		CASE	"E"
			opcode=chr( &h1C)
		CASE	"H"
			opcode=chr( &h24)
		CASE	"L"
			opcode=chr( &h2C)
		CASE	"(HL)"
			opcode=chr( &h34)
		CASE	"A"
			opcode=chr( &h3C)
		CASE else 
			Logerror("Register not recognized.")

	End Select
End Sub

Sub DEC_Opcode
	TOEND=1: rem Ignore spaces here. 
	PART1=GetWordToEnd(SOURCE)
	Select CASE Part1
		CASE	"BC"
			opcode=chr( &h0B)
		CASE	"DE"
			opcode=chr( &h1B)
		CASE	"HL"
			opcode=chr( &h2B)
		CASE	"SP"
			opcode=chr( &h3B)
		CASE	"B"
			opcode=chr( &h05)
		CASE	"C"
			opcode=chr( &h0D)
		CASE	"D"
			opcode=chr( &h15)
		CASE	"E"
			opcode=chr( &h1D)
		CASE	"H"
			opcode=chr( &h25)
		CASE	"L"
			opcode=chr( &h2D)
		CASE	"(HL)"
			opcode=chr( &h35)
		CASE	"A"
			opcode=chr( &h3D)
		CASE else 
			logerror("Register not recognized.")

	End Select
End Sub

sub Exchange
	Part1=GetWordToEnd (Source)
	Checkcomma (op)
	Part2=GetWordToEnd (Source)
	
	If Part1="DE" and Part2="HL" then Opcode=chr(&hEB) : GOTO EXEND
	If Part1="AF" and Part2="AF" then Opcode=chr(&h08) : GOTO EXEND
	If Part1="(SP)" and Part2="HL" then Opcode=chr(&hE3) : GOTO EXEND
	
	LogError ("*FMA Alchemy Error* Equivalent Exchange violated")
EXEND:

End sub

sub Test_Load
rem LD instruction processing.
rem Order of tests.
rem Single Reg
rem Double Reg
rem (BC)
rem (DE)
rem R
rem I
rem A,(nn) - inc (BC) and (DE)
rem Unknown Error. 

		Part1=GetWordToEnd (Source)			: rem Get the first operand, or part thereof...

		if left(part1,1)="(" and OP <> "" and OP <> "," and Part1 <> "(HL" then
			rem It might be an eval...
			NN=OneBracketEval(Part1)
			Part1="($"+hex(NN,4)+")" : rem re-encode as the result. 
		Endif	

		Checkcomma (op)	: rem We should have a comma after the first operand, and we know it's a single byte variable, so not a number. 
		Part2=GetwordToEnd (Source)			: rem Get the next operand. 

		if left(part2,1)="(" and OP <> "" and OP <> "," and Part2 <> "(HL" then
			rem It might be an eval...
			NN=OneBracketEval(Part2)
			Part2="($"+hex(NN,4)+")" : rem re-encode as the result. 
		Endif	

	
			rem First we do the quick single bytes and (NN)  single bytes. 	
			rem Quick matches for exceptions. lD A,(BC), LD A,(NN) etc. 

			if Part1="A" and Part2="(BC)" then Opcode=chr(&h0A) : Goto LDEND
			if Part1="A" and Part2="(DE)" then Opcode=chr(&h1A) : Goto LDEND
			if Part1="(BC)" and Part2="A" then Opcode=chr(&h02) : goto LDEND
			if Part1="(DE)" and Part2="A" then Opcode=chr(&h12) : goto LDEND
			
			rem Check for A,B,C,D,E,H,L,(HL)..... eg, LD A,B and LD B,A next. 
			if reg(Part1)>=0 and reg(Part2)>=0 then 
				opcode=chr((reg(Part1)*8)+&h40+reg(Part2))
				GOTO LDEND										: rem and we're done. 
			endif			
									
			rem LD (NN),HL,BC,DE,SP
				if left(Part1,1)="(" and right (part1,1)=")" and Part2="HL" then
					Opcode=chr(&h22)
					NN=BracketsEval(Part1)	: rem Get the value in the brackets.
					Operand=string16(NN) : rem record the location. 
					WORD16=1 : rem Note a 16 bit payload. 
					Goto LDEND
				endif
				if left(Part1,1)="(" and right (part1,1)=")" and Part2="BC" then
					Opcode=chr(&h43)
					Prefix2=chr(&hED)
					NN=BracketsEval(Part1)	: rem Get the value in the brackets.
					Operand=string16(NN) : rem record the location. 
					WORD16=1 : rem Note a 16 bit payload. 
					Goto LDEND
				endif
				if left(Part1,1)="(" and right (part1,1)=")" and Part2="DE" then
					Opcode=chr(&h53)
					Prefix2=chr(&hED)
					NN=BracketsEval(Part1)	: rem Get the value in the brackets.
					Operand=string16(NN) : rem record the location. 
					WORD16=1 : rem Note a 16 bit payload. 
					Goto LDEND
				endif
				if left(Part1,1)="(" and right (part1,1)=")" and Part2="SP" then
					Opcode=chr(&h73)
					Prefix2=chr(&hED)
					NN=BracketsEval(Part1)	: rem Get the value in the brackets.
					Operand=string16(NN) : rem record the location. 
					WORD16=1 : rem Note a 16 bit payload. 
					Goto LDEND
				endif


				if left(Part1,1)="(" and right (part1,1)=")" and Part2="A" then
					Opcode=chr(&h32)
					NN=BracketsEval(Part1)	: rem Get the value in the brackets.
					Operand=string16(NN) : rem record the location. 
					WORD16=1 : rem Note a 16 bit payload. 
					Goto LDEND
				endif
				
			

			if left(Part2,1)="(" and right (part2,1)=")" and Part1="HL" then
				Opcode=chr(&h2A)
				NN=BracketsEval(Part2)	: rem Get the value in the brackets.
				Operand=string16(NN) : rem record the location. 
				WORD16=1 : rem Note a 16 bit payload. 
				Goto LDEND
			endif

			if left(Part2,1)="(" and right (part2,1)=")" and Part1="A" then
				Opcode=chr(&h3A)
				NN=BracketsEval(Part2)	: rem Get the value in the brackets.
				Operand=string16(NN) : rem record the location. 
				WORD16=1 : rem Note a 16 bit payload. 
				Goto LDEND
			endif				

		rem LD A,??? eg,
		rem LD A,I A,R R,A I,A and A,N as well as R,N
		
			if Part1="A" and Part2="I" then
					opcode=chr(&h57)
					Prefix2=chr(&hED)
					Goto LDEND	
			endif

			if Part1="A" and Part2="R" then
					opcode=chr(&h5F)
					Prefix2=chr (&hED)
					Goto LDEND	
			endif
			
		rem Check for r,N
			if reg(Part1)>=0 then
				opcode=chr((reg(Part1)*8)+&h06)					: rem 06,0E,16,1E etc.
				operand=chr(eval(Part2))			
				GOTO LDEND
			endif

			if PART1="I" and Part2="A" then 
					opcode=chr(&h47)
					Prefix2=chr(&hED)
					Goto LDEND
			endif
			
			if part1="R" and Part2="A" then
					opcode=chr(&h4F)
					Prefix2=chr(&hED)
					Goto LDEND
			endif
							
							
			
		REM Regiter Pair Loads.
			if RegPairSP(Part1)>=0 then					: rem Check for BC,DE,HL,SP
					
					rem LD HL,NN
					rem LD HL,(NN)
					rem LD IX,IY ( HL ).
					rem SP,HL.
					
					rem First do the (nn).
					if left(Part2,1)="(" and right (part2,1)=")" then
						if Part1="HL" then opcode=chr(&h2A) : goto LDHLCODE : rem Bypass the AfterED opcode for HL. 
						opcode=chr(RegPairSP(Part1)+&h4B)
						Prefix2=chr(&hED)
					LDHLCODE: rem Bypass the ED if it's just HL. 
						Part2=right(Part2,len(Part2)-1)
						if right (Part2,1)=")" then Part2=Left(Part2,len(Part2)-1) : rem Correct for Right bracket. 
						Special_Operator=")"
						NN=Eval(Part2)	: rem Get the value in the brackets.
						Special_Operator=""
						Operand=string16(NN) : rem record the location. 
						WORD16=1 : rem Note a 16 bit payload. 

						Goto LDEND
					endif	
					
					if Part1="SP" and Part2="HL" then
						opcode=chr(&hF9) : rem This is simple because it's only going to be LD SP,HL, LD IX,HL or LD IY,HL. 
						Goto LDEND
					endif		
				
					NN=Eval(Part2)
					Operand=String16(NN)
					Word16=1 : rem 16 bit value
					opcode=chr(RegPairSP(Part1)+&h01)
										
					Goto LDEND

			endif
			
		




					
		
			rem Something is wrong here. 
			logerror "Invalid Register"
		


					
	LDEND:
End sub

Function DeleteLabel (byref Labelname as string) as integer
dim result as integer
dim Shift as integer : rem How much we should shift the label table by. It's the size of the label we found.
dim PostNextLabel as integer : rem What is the label after the next label.
dim ThisPos as integer
dim NextPos as integer
dim ValueVector as integer : rem NN location of Value Vector for the selected label. 
dim StartVector as integer : rem WHere we started - need to know for second vector. 

rem To delete a label, we need to shorten the table by the label's length. Since we use a linked list with absolute pointers,
rem  those pointers need to be updated. Also, if we delete a label or group within a group, we need to update pointers
rem  before the label we deleted. Complex process. 

	result=-1
	rem Find the label, error if not existing, and set NN to location of label. 
		NN=GetLabel(Labelname)	: rem Only use the label routines for this much.
		IF NN=0 then logerror ("Label does not exist") : Goto DeleteLabelEnd	

	
	rem print "NN:";NN,"Label16(NN)";Label16(NN),"Label16(label16(NN))";Label16(label16(NN))
	rem If this is an end of table matter, just end the table now. 
		if Label16(label16(NN))=0 then
			SetLabel16(NN),0 : rem End the table here - Nothing more to think of. This is the end. 
			Goto DeleteLabelEnd
		endif

	rem Otherwise understand how much label we're deleting from the table.
		SHIFT=LABEL16(NN)-NN : rem Size of the label we're cutting out.
	rem And cut the label from the table. 
		labeltable=left(labeltable,NN)+right(labeltable,len(labeltable)-NN-SHIFT) : rem Cut out the deleted label.		
		THISPOS=NN		: rem  Get the current THISPOS.
		StartVector=NN	: rem Need to know where we started moving stuff from first. 
rem Print "Start Vector:";hex(startvector,4)		
Forward_Vector_Loop:
			NextPos=LABEL16(ThisPos)-SHIFT : rem Know the new vector
			SETLABEL16(ThisPos,NextPos)	   : rem Set the new vector into the table.
			ThisPos=NextPos
rem			Print "Relocated to:";hex(thispos,4)
			if Label16(NextPos)<>0 then goto Forward_Vector_Loop	: rem change all the forward vectors. 

rem Now we've fixed the forward vectors ( labels after what we removed), fix any group second vectors before the deletion.
ThisPos=label16(LBASE) : rem Start at the beginning.
Second_Vector_Loop:	
			NextPos=LABEL16(ThisPos) : rem The next vector is correct for all labels now - No need for offset.
			if MID(LabelTable,ThisPos+3,1) > chr$(127) then  
			
				rem For Groups Only - Count > 127... 
				ValueVector=ThisPos+3+(Label8(ThisPos+2)and &h7F) : rem MASK the actual length... 
rem Print "Test:";hex(thispos,4),hex (thispos+2,4), hex(asc(MID(LabelTable,ThisPos+3,1)),2)	;" Value at:";hex(valuevector,4),hex(label16(valuevector),4),"Start Vector:";hex(startvector,4)
				If Label16(ValueVector) > StartVector then 		
					SETLABEL16(ValueVector,Label16(ValueVector)-SHIFT)	   : rem Set the new vector into the table.
				Endif
			endif
			ThisPos=NextPos
			if Label16(NextPos)<>0 then goto Second_Vector_Loop	: rem change all the forward vectors. 

rem PRINTHEX (labeltable,len(labeltable))

		result=nextlabel
		if result=0 then goto DeleteLabelEnd
	
DeleteLabelEnd:
return result
End Function



Function RecurseIn ( Byref Text as String ) as integer
dim result as integer

	setlabel16(xnest,label8(xnest)+1)
	depth=label8(xnest)
	result=depth
	if result>30 then logerror ("Too Many Includes. Overrecursion error.")

	Sourcestore(depth)=source
	Pointerstore(depth)=filepointer
	LineNumberStore(depth)=LineNumber
	passstore(depth)=label16(xpass) : rem Store the Global/Local pass of the previous routine. 
	one_more(depth)=One_More_Time : Rem Store previous recursion flag.
		one_more_time=0 : rem Don't assume we want two passes on the iterative process. 
	Two_Pass_Org=Label16(ORGPC) : rem Store PC in case we run again. 

	LineNumber=1
	FilePointer=1
	source=text
return result : rem result is the current level of recursion.
End Function



Function RecurseOut (Byref text as string ) as integer
dim result as integer

	depth=label8(xnest)

	If One_More_Time<>0 and pass(0)<>2 then
		SetLabel16(OrgPC,Two_Pass_Org)
		LineNumber=1
		FilePointer=1
		pass(2)		: rem Set pass 2. 
		result=depth : rem Retain same depth.
		Goto NoExit	: rem Don't exit and recurse out this time. 
	Endif

	one_more_time=one_more(depth)
	setlabel16(xpass,passstore(depth)) : rem restore the Global and Local pass information.
	source=Sourcestore(depth)
	FilePointer=Pointerstore(depth)
	LineNumber=LineNumberStore(depth)
	One_More_Time=One_More(depth)		: rem Recover state of One_More_time from this depth. 

rem Do this bit last after we back out the recursion. 
	setlabel16(xnest,label8(xnest)-1)
	depth=label8(xnest)
	result=depth
	if result<0 then logerror ("Recurse Below Root. Under-recursion error.")
	
NoExit: 
return result : rem result is the current level of recursion.
End Function



Function IntelChecksum (byref text as string) as string
dim result as string 
dim checksum as integer
dim spos as integer

rem	text=left(text,len(text)-2) : rem Strip out old checksum. 
	Checksum=0
	For sPos=2 to len(text) step 2		
		Checksum=checksum+val("&h"+mid(text,sPos,2)) 
	Next sPos
	checksum=(&h100-checksum) and &hFF
	result=hex(checksum,2)
rem	text=text+hex(checksum mod 256,2) 
rem result=text
return result
End function

rem #######################################################
rem #######################################################
rem ##                                                   ##
rem ##  Instruction test Subroutine here... Very         ##
rem ##  important.                                       ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem #######################################################
rem #######################################################


Sub Writecode
rem Write bytes to the output file. 
rem Check conditional writing. (eg Pass 1 )
rem Check overriding condition (eg, Dry coding - no writing ).
rem Check Hex or Binary. 
rem Check PC location.
rem Check Opcode values for 8 bits. 
	
	PC=Label16(orgpc) : rem Get the origin into PC. ONLY do this when writing actual code. 
	TARGETPC=(PC+LABEL16(PCOFF)) and &hFFFF : rem Add offset to PC. For setting labels. ( We assemble at PC=ORGPC - We set position labels with : to Target offset PC=ORGPC+PCOFF 
 	SETLABEL16(XWLOC,TARGETPC) : rem I do this here, and I don't think I do  it again until I write. Need to test both. 

	rem Displacement changes order for some opcodes. 
	if prefix1<>"" and prefix2<>"" then
		build=prefix1+prefix2+displacement+opcode : rem DDCB and FDCB have reversed order. 
	else
		build=prefix1+prefix2+opcode+displacement : rem the instruction to write... From 0 to 5 bytes possible, though 0 to 4 in practice due to opcodes. 
	endif
	
	if Word16=0 then
		build=build+left(operand,1)
	else
		build=build+left(operand,2)
	Endif

	if Label8(XDEBUG)>0 and pass(0)=2 then	PRNOUTPUT(build) : rem Normal /P = Pass 2
	if LABEL8(XDEBUG)=2 and pass(0)=1 then PRNOUTPUT(build) : rem /O both passes - rem was PRNFORMAT instead of Label8
	
	rem Sanity check... do we actually have anything to write, or is it a wasted write?
	if build="" then goto Nothing_To_Write

	if Word16=0 and len(operand)>1 then logwarning "Warning - Operand exceeds 8 bits." : rem Bounds checking. 
	if Word16=1 and len(operand)>2 then logwarning "Warning - Operand exceeds 16 bits."
	

	rem We write code according to PC, but we save the code in memory at TARGETPC. 
	
	if len(build)>0 then 
		if Firstbyte>TARGETPC then Firstbyte=TARGETPC : rem record the earliest byte we've written in memory. 
	endif
	
Rem - Start actually writing the code here. Either to memory  or to the output file. 
	binarycode=insertstring (binarycode,build,TARGETPC+1) : rem Save the code in the "memory". 

rem Intel Hex Output, start of HEX dedicated routines. 
	if IntelHex <> 0 and pass(0)=2 and len(build)<>0 then

		If IntelString="" then 
			IntelString=":00"+hex(TARGETPC,4)+"00"
			HEXADDRESS=TARGETPC : rem Hexaddress is starting anew... So set it now. 
			IntelLastAddress=TARGETPC : rem remember this until the next write also.
		else
			IntelString=left(IntelString,len(IntelString)-2) : rem Remove previous checksum.
		endif
		
		rem Turn the BUILD bytes into a stream of hex characters for the Intel Hex output. 
		IntelSubString=""
		for intelpos=1 to len(build)
			IntelSubString=IntelSubString+hex(asc(mid(build,intelpos,1)),2)
		next Intelpos

		rem If we filled a string, or if the HexAddress is not the same as the PC, then it means our Hex Line needs to be closed off. 
		rem If the anticipated size is 41 characters or more, then we also need to close off the line. 
	
		if HexAddress=TARGETPC then IntelString=IntelString+IntelSubstring : rem If the PC tracker is in order, add it now. 	
		if len(intelstring)>=41 or HexAddress <> TARGETPC then
		
			rem Divide up the stream of characters now... 
			IntelOverflow=right(intelstring,len(intelstring)-41)
			IntelString=left(Intelstring,41)
			IntelString=InsertString(IntelString,hex((len(intelstring)-9)/2,2),2) : rem Update byte count value in string. 
			
			rem Might be here because of this, or because it got too large. Check first. 
			if HexAddress<>TARGETPC then IntelOverflow=IntelOverflow+IntelSubString : rem If the PC has changed, add it to the overflow. 

			INTELSTRING=INTELSTRING+IntelCHECKSUM(INTELSTRING) : rem recalculate checksum. 		
			PRINT #outfile, INTELSTRING : rem Send to file here.
			
			if HexAddress<>TARGETPC then
				rem Records the new PC.
				INTELSTRING=":00"+hex(TARGETPC*256,4)+"00"+INTELOVERFLOW
				IntelLastAddress=TARGETPC : rem remember this until the next write also.
			else
				rem Record the anticipated PC where the overflow continues.
				IntelLastAddress=IntelLastAddress+&h10 : rem We wrote 16 bytes. Update the counter. We don't know how many in overflow.
				INTELSTRING=":00"+hex(IntelLastAddress, 4)+"00"+INTELOVERFLOW			
			endif
		endif

		rem Update Count and Update Checksum before we're done 
		IntelString=InsertString(IntelString,hex((len(intelstring)-9)/2,2),2) : rem Update byte count value in string. 
		IntelString=IntelString+IntelChecksum(IntelString) : rem Write new checksum, in case we terminate without coming back here. 

	Endif
rem End Hex Output routines. 
	
rem Save to CODEBASE so we have a copy of the code. Also check there is nothing there already...
	if pass(0)=2 then
		a=0
		for CODEPTR=TARGETPC to TARGETPC+len(build)
			a=a+asc(mid(CODEBASE,CODEPTR+1,1))
		Next CodePTR
		if a<>0 then logwarning ("Code rewritten in location:"+hex(CODEPTR,4))
	endif
	CODEBASE=INSERTSTRING (CODEBASE,BUILD,TARGETPC+1)
	
	
rem	Update Counters and Positions. 
	PC=LABEL16(ORGPC) : rem Reset the original value of the PC. 	
	PC=PC+len(Build)	: rem Update PC. Linear code until otherwise.
	TARGETPC=(PC+LABEL16(PCOFF)) : rem Update target PC. 


	if PC > 65535 then LogWarning ("Program Counter Overflow")
	if targetPC > 65535 and targetPC < 65540 then logwarning ("Program Counter Target Overflow") : rem only happens on overflow from FFFF onwards for 4 bytes. 

	TARGETPC=TARGETPC and &hFFFF
	PC=PC and &hFFFF
	HEXADDRESS=TARGETPC 	: rem Store the address so if in Intel Hex Format, we can end the previous output stream and start a new one.

	SETLABEL16 (ORGPC,PC)	 : rem Write PC value back to PC. So the source file can find it. 

	if len(build)>0 then 
		if Lastbyte < TARGETPC-1 then Lastbyte=(TARGETPC-1) and &hFFFF : rem The last byte we've written in memory. 
	endif	

Nothing_To_Write: 
rem Jump here if there was nothing to write. 
End sub

Sub Test_DB
DB_LOOP:
	Part1=GetWordToEnd(source)
	N=Eval(Part1)
	Opcode=chr(N)
	WriteCode
	if OP="," then goto DB_LOOP
	Opcode="" : rem Prevent any further writes.
End Sub

Sub Test_DW
	Part1=GetWordToEnd(source)
	NN=eval(Part1)
	Operand=chr(int(NN/256))
	Opcode=chr(NN MOD 256)
End Sub

Sub Test_Block
N=LABEL8(XSYST): rem The character we write.
NN=EVAL(GetWordToEnd(Source))

	While NN > 0 
		Opcode=chr(N)
		WriteCode
		nn=nn-1
	Wend
	Opcode="" : rem Prevent any further writes.
End Sub


sub MakeMacro
rem Make the macro
NoTranslate=1 : rem Don't translate IX/IY to HL - That will occur when the macro os read back. 

If PASS(0)=2 then goto MacroBypass : rem Macro is made during Pass 1 only. 

	Part1=GetWordToEnd (Source)
	if GetLabel(Part1)=0 then
		NN=addlabel(Part1,NN)
	else
		logerror ("Label Exists")
		goto MacroMade
	endif

rem NN holds the start of the label. We can update the vector at the end. 
rem Delete the END of the table.
labeltable=left(labeltable,len(labeltable)-2)

rem Clear any lingering EOL at this point. 
	if EOL=1 then 
		LineNumber=LineNumber+1 : rem We might have ended the last line with a new line. 
		EOL=0
	endif
	
Macroloop:
	ToEnd=0 : rem Just to make sure, since this can linger. 
	Part1=GetWord (source)
	If Part1="MEND" then goto MacroEnd : rem Escape Macro process.	

rem PRINT "MacroAdd:[";Part1;"][";op;"]",toend
	LabelTable=LabelTable+Part1+op+" "

	if EOL=1 then 
		LineNumber=LineNumber+1 : rem We might have ended the last line with a new line. 
		EOL=0
		LabelTable=LabelTable+"|" : rem EOL marker. 
		Goto Macroloop:
	endif

MacroInnerLoop:	
	DontIgnoreEol=1 : rem Don't read past end of line. 
	Part1=GetWordToEnd (source)
	LabelTable=LabelTable+Part1+op
	
	if EOL=0 then goto MacroInnerLoop
	
	LineNumber=LineNumber+1 : rem We might have ended the last line with a new line. 
	EOL=0
	LabelTable=LabelTable+"|" : rem EOL marker. 	
	
	Goto MacroLoop	

MacroEnd:	
	
	Rem Mark the end of the label. 
	LabelTable=LabelTable+chr(0)+chr(0)
	Setlabel16(NN,len(LabelTable)-2)	: rem Set the vector correctly. 
	GetNextLabel("*",NN) : rem Fill in the Macro Details.
	SetLabel16(LabelValueLocation,len(macrotext)) : rem Set the value of the label to be the Macro Length.
rem Done here - Exit label. 
	goto MacroMade

rem And a quick routine to just bypass the macro if it already was made in Pass1. 	
MacroBypass:
		part1=GetWord (source)
		if part1 <> "MEND" then goto MacroBypass
	
	
MacroMade: 
NoTranslate=0
End Sub




sub GetParameters
rem print "Finding pararemeters."
rem Let's look for more parameters after the macro/include call and shift them to Arg1, Arg2 etc.
	n=0
	if EOL=1 then goto GetParametersEnd : rem if we start with an EOL, just move on.
	nn=Arg2-Arg1 : rem offset to variable from ARG1 to ARG9

rem Zero Parameters. 
	for n=0 to 8
	setlabel16((n*nn)+arg1,0) : rem not sure if the z80 version clears these or just sets them.
	next n
	n=0 : rem now use N as character count. 
	
	DontIgnoreEol=1 : rem We're hunting on the same line.
GetParaLoop:
	part1=getwordtoend (source) : rem Get the next parameter, or the EOL. 
	if Part1="" then goto GetParametersEnd : rem nothing read? We're at the end. 
	setlabel16((n*nn)+arg1,eval(Part1)) : rem Set the label. 
	n=n+1 : rem we got a parameter.
	if n>9 then logerror ("Too Many Parameters"): goto GetParametersEnd
	if op = "," then goto Getparaloop	

GetParametersEnd:
	setlabel16(argc,n) : rem Number of arguments transferred. 
End Sub

Sub GetFileName
rem Get a filename 
rem sfilename = file name.
	n=0
	sfilename=""
GETFILENAMELOOP:
rem	Part1=GetWordToEnd (source)
	Part1=GetWord(source) : rem No spaces in a quote... 
rem	sfilename=sfilename+chr(eval(Part1))
	sfilename=sfilename+mid(Part1,2,1)
	if op="," then goto GETFILENAMELOOP
	
End Sub


Sub LoadInclude
	GetFileName
	GETPARAMETERS	 
rem	Print "Recursion Filename:";SFileName
	RecurseIn(Loadfile(SFileName))
End Sub


Sub LoadBinclude
	GetFileName
	
rem	PRINT "OP1:";OP,SfileName
	
	If op="+" then goto LoadBinclude_GotPlus : rem We don't need to look if it was already found by Getword.
	
	DontIgnoreEol=1
	Part1=GetWordToEnd (source): rem Look further for a PLUS
	
rem	PRINT "OP2:";OP,Part1

LoadBinclude_GotPlus:	
	if op<>"+" then 
		logerror ("Missing binary size (expected 'Filename.ext' +<size> Where size is a number from 0(64K) to FFFF")
		goto Binclude_Exit
	endif
	Part1=GetWordToEnd (source)
	BINSize=eval(Part1) : rem Get size of binary file to transfer... 
	
rem Print "Filename:";SFileName
	BINFILE=LoadFile(SFileName)
rem Print "Moving Bytes:";BINSize
	
	if BINSIZE=0 then BINSIZE=65536

rem Package the binary file up in groups of 4 so the PRN isn't so messy. 
	For n=1 to BinSize step 4
		Prefix1=mid(Binfile,n,1)
		Prefix2=mid(Binfile,n+1,1)
		Displacement=mid(Binfile,n+2,1)
		opcode=mid(Binfile,n+3,1)
		if Binsize+1-n<4 then Opcode="" : rem remember OPCODE comes last when Prefix 1 and 2 both exist. 
		if Binsize+1-n<3 then Displacement=""
		if Binsize+1-n<2 then Prefix2=""		
		Writecode
	Next n
Binclude_Exit:
rem Clean out any lingering instructional data - since WRITECODE still gets called once more. 
Opcode=""
Displacement=""
Prefix1=""
Prefix2=""
End Sub



Sub Test_Instruction

if debug=1 then print "Testing Instruction...";instruction;"."

prefix1=""
prefix2=""
postfix=""

if OP=":" and conditional=0 then goto Test_Label : rem We can ignore everything else if we know it's a label. (except when not processing )

rem Check for a : since if we follow a label with a ':' it's going to be a special label declaration.
rem We can use other operators here to bypass other checking too if we want.

select case INSTRUCTION				: rem Only non-conditional cases.
rem	CASE	"IF"					: rem Test for conditional statements, because DONT DO ANYTHING IF WE'RE IN ONE.
	CASE	"IFZ"					: rem If result is Zero. 
		Part1=GetWordToEnd(Source)
		if eval(Part1)<>0 then 
			conditional=1
		else
			conditional=0
		endif
	CASE	"IFNZ"					: rem If result is NOT ZERO.
		Part1=GetWordToEnd(Source)
		if eval(Part1)=0 then 
			conditional=1
		else
			conditional=0
		endif
	CASE	"IFPOS"					: rem If Bit15=0
		Part1=GetWordToEnd(Source)
		if (eval (Part1) and &H8000) <> 0 then 
			conditional=1	
		else
			conditional=0
		endif
	CASE	"IFNEG"					: rem If Bit15=1
		Part1=GetWordToEnd(Source)
		if (eval (Part1) and &H8000)  <> &h8000  then 
			conditional=1
		else
			conditional=0
		endif
	CASE	"ENDIF"					: rem End all conditional statements. 
		conditional=0
	CASE	"END" 
		if conditional=1 then logwarning ("Conditional code not complete before end of source") 
	CASE ELSE
	rem Everything else is else...
	IF F_EOF=1 and conditional=1 then logerror ("Conditional code not complete before end of source") 
End Select

if conditional=0 then

	select case INSTRUCTION 

		CASE	"ENDIF"		
		CASE	"IFZ"
		CASE	"IFNZ"
		CASE	"IFPOS"
		CASE	"IFNEG"
			rem Nothing to do here, It's valid. 

		CASE	"2PASS" 			: rem Are we forcing an additional second pass ( within the current global pass - for modules only )
			if one_more_time=0 and label16(XPASS)=&h0202 then SetLabel16(XPASS,&h0201) : rem Correct for extra pass in globalpass 2. 
			one_more_time=1 		: rem Flag to repeat . 
			rem post_select
			rem Second Pass control code goes here. 

		REM Now we test opcodes.

			CASE	"INC"			: rem All INC instructions. 
						INC_OPCODE

			CASE	"DEC"			: rem All DEC instructions. 
						DEC_OPCODE	
						
			CASE	"PUSH"			: rem All PUSH instructions.
						
						Part1=GetWordToEnd (Source)
						opcode=chr((5+RegPair(Part1)))
						
						
						
			CASE	"POP"			: rem All POP instructions. 
						Part1=GetWordToEnd (Source)
						opcode=chr((1+RegPair(Part1)))

			CASE	"LD"			: rem All LD instructions... Begin with the 8 bit group. Still need to add special and 16 bit groups. 
									: rem All instructions also have two parts, separated by a comma. 
									: rem (IX??) is processed as (HL)
					TEST_LOAD			: rem LOAD. 

		

	rem		CASE	"ARITHMETIC"	: rem All Arithmetic instructions. Break them out each here. 
					CASE	"ADD"
						opcode=chr(&h80)
						ACOMMATARGET
						

					CASE	"ADC"
						opcode=chr(&h88)			:rem Prefix for ADC A,
						ACOMMATARGET

					CASE	"SBC"
						opcode=chr(&h98)			:rem Prefix for SBC A,
						ACOMMATARGET
						
					CASE	"SUB"
						opcode=chr(&h90)			:rem Prefix for SUB
						ARITHMETIC

					CASE	"AND"
						opcode=chr(&hA0)			:rem Prefix for AND
						ARITHMETIC
						
					CASE	"XOR"
						opcode=chr(&hA8)		:rem Prefix for XOR
						ARITHMETIC
						
					CASE	"OR"
						opcode=chr(&hB0)			:rem Prefix for OR
						ARITHMETIC
						
					CASE	"CP"
						opcode=chr(&hB8)			:rem Prefix for CP
						ARITHMETIC

			CASE	"RET"			: rem All RET instructions, including conditional. 
	rem					opcode=chr( &hC9)	: rem Set default RET first.
	rem					if EOL=0 then TEST_RET	: rem If there might be more than just a RET, TEST IT FURTHER. 
						TEST_RET
										
			CASE	"JP"			: rem All JP instructions 
						TEST_JP
						
			CASE	"CALL"			: rem All CALL instructions. 
						TEST_CALL

			
			CASE	"JR"			: rem All Jump Relative instructions. Add DJNZ-D in here also. But we call it separately.
						PC=label16(orgpc)				
						Part1=GetWordToEnd (Source)
						if op="," then 
							Part2=GetWordToEnd (Source)
							opcode2=eval(Part2)
							Select Case Part1
								Case "NZ"
									opcode=chr(&h20)
								Case "NC"
									opcode=chr(&h30)
								Case "Z"
									opcode=chr(&h28)
								Case "C"
									opcode=chr(&h38)
								Case Else
									Logerror "Invalid flag condition."
							End Select
						else
							opcode2=eval(Part1)
							opcode=chr(&h18)
						endif
						operand=chr((Opcode2-PC-2) and &hFF)
						if Opcode2-PC-2 > 127 or Opcode2-PC-2 < -128 then
							if pass(0) <> 1 then logerror ("Jump Invalid. PC:"+hex(PC,4)+" DEST:"+hex(Opcode2)+" Diff:"+hex(opcode2-PC-2,4))
						endif

			CASE	"DJNZ"			: rem DJNZ
						opcode=chr(&h10)
						PC=LABEL16(orgpc)					
						Part1=GetWordToEnd (Source)
						opcode2=eval(Part1)
						operand=chr((Opcode2-PC-2) and &hFF)
						if Opcode2-PC > 127 or Opcode2-PC < -128 then
							logerror ("Jump Invalid.")
						endif

	rem		CASE	"SINGLE_OPCODE"	: rem All the single opcodes ( no arguments )
					CASE	"NOP"
						opcode=chr( &h00)
					CASE	"RLCA"
						opcode=chr( &h07)
					CASE	"RRCA"
						opcode=chr( &h0F)
					CASE	"RLA"
						opcode=chr( &h17)
					CASE	"RRA"
						opcode=chr( &h1F)
					CASE	"DAA"
						opcode=chr( &h27)
					CASE	"CPL"
						opcode=chr( &h2F)
					CASE	"SCF"
						opcode=chr( &h37)
					CASE	"CCF"
						opcode=chr( &h3F)
					CASE	"HALT"
						opcode=chr( &h76)
	rem				CASE	"RET"						: rem Dealt with earlier as a possible conditional instruction. 
	rem					opcode=chr( &hC9)
	rem
					CASE	"EXX"
						opcode=chr( &hD9)	
					CASE	"DI"
						opcode=chr( &hF3)
					CASE	"EI"
						opcode=chr( &hFB)
					REM  Now do extended ED codes with ONE_ED_OPCODE
					CASE	"NEG"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &h44)
					CASE	"RETN"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &h45)
					CASE	"RETI"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &h4D)
					CASE	"RRD"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &h67)
					CASE	"RLD"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &h6F)
					CASE	"LDI"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hA0)
					CASE	"CPI"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hA1)
					CASE	"INI"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hA2)
					CASE	"OUTI"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hA3)
					CASE	"LDD"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hA8)
					CASE	"CPD"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hA9)
					CASE	"IND"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hAA)
					CASE	"OUTD"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hAB)
					CASE	"LDIR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hB0)
					CASE	"CPIR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hB1)
					CASE	"INIR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hB2)
					CASE	"OTIR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hB3)
					CASE	"LDDR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hB8)
					CASE	"CPDR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hB9)
					CASE	"INDR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hBA)
					CASE	"OTDR"
						PREFIX2=chr(&hED)	: rem After ED. 
						opcode=chr( &hBB)


					CASE	"RST"			: rem All the RST codes
						TEST_RST

						
			CASE	"IN"			: rem All the IN codes. 
						TEST_IN

			CASE	"OUT"			: rem All the IN codes. 
						TEST_OUT
						
			CASE	"EX"			: rem Multiple EXCHANGE codes. 
					EXCHANGE		: rem Exchange Instructions.
	rem		CASE	"BITTEST"		: rem All Bit Related Instructions. 
				CASE	"RLC"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h00+reg(Part1))
					endif
				CASE	"RRC"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h08+reg(Part1))
					endif
				CASE	"RL"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h10+reg(Part1))
					endif
				CASE	"RR"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h18+reg(Part1))
					endif
				CASE	"SLA"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h20+reg(Part1))
					endif
				CASE	"SRA"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h28+reg(Part1))
					endif
				CASE	"SLL"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h30+reg(Part1))
					endif
					if noundocs=0 then LogWarning ("Undocumented Opcode: SLL r Line:"+STR(LINENUMBER)) 
				CASE	"SRL"
					PART1=GetWordToEnd(source)
					if reg(Part1)>=0 then
						Prefix2=chr(&hCB)
						Opcode=chr(&h38+reg(Part1))
					endif
				CASE	"BIT"
					PART1=GetWordToEnd(source)
					checkcomma (op)
					Part2=GetWordToEnd(source)
					NN=eval(part1)
					if NN < 0 or NN > 7 then 
						logerror ("Invalid Bit.")
						endif
					Prefix2=chr(&hCB)
					Opcode=chr(&h40+(8*NN)+reg(Part2))
				CASE	"RES"
					PART1=GetWordToEnd(source)
					checkcomma (op)
					Part2=GetWordToEnd(source)
					NN=eval(part1)
					if NN < 0 or NN > 7 then 
						logerror ("Invalid Bit.")
						endif
					Prefix2=chr(&hCB)
					Opcode=chr(&h80+(8*NN)+reg(Part2))
				CASE	"SET"
					PART1=GetWordToEnd(source)
					checkcomma (op)
					Part2=GetWordToEnd(source)
					NN=eval(part1)
					if NN < 0 or NN > 7 then 
						logerror ("Invalid Bit.")
						endif
					Prefix2=chr(&hCB)
					Opcode=chr(&hC0+(8*NN)+reg(Part2))
					
					
			CASE	"IM"			: rem Test Interrupt Modes.
						NN=eval(GetWordToEnd (Source))
						Prefix2=chr(&hED)
						Select Case NN 
							Case 0
								Opcode=chr(&h46)
							Case 1
								Opcode=chr(&h56)
							Case 2
								Opcode=chr(&h5E)
							Case else
								LogError ("Invalid IM")
						End Select
									: rem And other assembler directives. 
			CASE	"EQU","MODID"			: rem See if it's EQU.
						Part1=GetWordToEnd (Source)
						Checkcomma (op)
						Part2=GetWordToEnd (Source)

						rem Check that label isn't being reassigned in GPASS 1, PASS 1.
						if pass(0)=1 and gpass(0)=1 then
							if GetLabel(Part1)=0 then
								NN=Eval(Part2)
								addlabel(Part1,NN)
							else
								LogError("Label reassignment attempted.")
							endif
						endif
						
						rem Either create or reassign label if we're already in GPASS 2, Pass1.
						if pass(0)=1 and gpass(0)=2 then
							if getlabel(Part1)=0 then
								NN=Eval(Part2)
								Addlabel(Part1,NN)
							else
								NN=Eval(Part2)
								Setlabel(Part1,NN)
							endif
						endif
						
						rem If it's Pass2, no matter the GPASS, the label SHOULD exist already - so just re-evaluate it and reset it. 
						if pass(0)=2 then
							if GetLabel(Part1)<>0 then
								NN=Eval(Part2)
								setlabel(Part1,NN)
							else
								LogError("CROSS-Label-Not-Found-PASS_2!.")
							endif
						endif
						
			CASE	"SETVAR"		: rem See if it's a label reassignment. 
						Part1=GetWordToEnd (Source)
						Checkcomma (op)
						Part2=GetWordToEnd (Source)
						NN=Eval(Part2)
						if Getlabel(Part1)=0 then
							LogError("Label does not exist.")
						else
							setlabel(Part1,NN)
						endif
			CASE	"DB"			: rem DB strings. Can be a byte, a word or a series of characters/bytes in a comma separated list.  
					Test_DB
			CASE	"DW"			: rem DW values. Two bytes. As a number. 
									: rem These two operations can build the table... We still need to process instruction encoding of the label process
									: rem to identify the correct PC. 
									: rem But we don't need to evaluate anything.
					Test_DW						
			CASE	"BLOCK"			: rem blocks of characters to fill space.  
					Test_Block
			
			CASE	"ORG"			: rem ORG instructions will affect the code base. Offset doesn't - Offset only changes where the code goes.
					Part1=GetWordToEnd (Source)
					SETLABEL16(ORGPC,EVAL(Part1)) : rem Default eval the rest of the line. 

					
			CASE	"RORG"			: rem Remote Org - Change both PC and Offset to maintain the current ORG.
					Part1=GetWordToEnd (Source)
					NN=LABEL16(ORGPC) : rem Store current org.
					SETLABEL16(ORGPC,EVAL(Part1)) : rem Update the ORG.
					SETLABEL16(PCOFF,(NN-EVAL(Part1)) MOD 65536)				
			CASE 	"REND"			: rem Collapse remote org - Go back to where the PC should be. 
					SETLABEL16(ORGPC,LABEL16(ORGPC)+LABEL16(PCOFF))
					SETLABEL16(PCOFF,0)


			CASE	"END"			: rem Have we reached the stated EOF before the physical EOF?
					F_EOF=1
					EOL=1				: rem We got to the end of the file...

			CASE	"MSG"			: rem Messages to the console...  
					Part1=GetWordToEnd (Source)
					Print Part1;
			CASE	"SHEX"			: rem Show any hex? 
					Part1=GetWordToEnd (Source)
					Print HEX (eval(part1),4);
			CASE	"SDEC"			: rem Show Decimal
					Part1=GetWordToEnd (Source)
					Print eval(part1) and &hFFFF;				
			CASE	"SBIN"			: rem Show binary?
					Part1=GetWordToEnd (Source)
					Print BIN (eval(part1),16);
			CASE	"SCR"			: rem Show any Carriage Returns?
					Print 
			CASE	"OFFSET"			: rem Are we assembling to a different location?
					Part1=GetWordToEnd (Source)
					rem Print "Setting OFFSET:";part1
					SETLABEL("PCOFF",EVAL(Part1)) : rem Default eval the rest of the line.
			CASE	"TARGET"			: rem Set a target PC, but assemble at the current location. 
					Part1=GetWordToEnd (Source)
					PC=Label16(OrgPC) 	: rem get current PC.
					SETLABEL16(PCOFF,(EVAL(Part1)-PC) MOD 65536)

			CASE	"DELGROUP"
					Part1=GetWordToEnd (Source)
					CloseGroup (Part1) : rem Close group first, so it contains all the labels within.
					DeleteLabel (Part1) : rem Then delete the label. 
				
			CASE	"DELETE"
					DeleteLabel (GetWordToEnd(Source))		
				
	rem 		CASE	"CLNUP"			: rem Clean up unwanted local label entries. SAME AS CLEAN. 
	rem Need to rename one of them. This cleans temporary labels starting with a ~
			CASE	"INCLUDE"			: rem ASM Includes
						LoadInclude
			CASE	"BINCLUDE"			: rem Binary Includes
						LoadBinclude
			CASE	"SHOWLABELS"			: rem Show label table. 
					SHOWLABELS		
			CASE	"SHOWLABEL"			: rem Show single label in the label table. 
						If GetLabel ( GetWordToEnd ( Source )) <> 0 then
							printlabel
						else
							logerror "Show Label not found."
						endif

			CASE	"SHOWGROUP"		: rem Alternative
				
						If GetLabel ( GetWordToEnd ( Source )) <> 0 then
							printlabel
						else
							logerror "Show Label not found."
						endif		
			
			CASE	"MACRO"			: rem Process any macro setups. 
						MakeMacro

			CASE	"GROUP"			: rem Was it a group command to establish a group?
						Part1=GetWordToEnd (Source)
						if pass(0)=1 then	: rem Only during pass 1.
							if GetLabel(Part1)=0 then
								rem NN=Eval(Part2) : rem What is this doing here? WHere did part 2 come from? There is no part2. 
								GROUP=&h80	: rem Set for group label. 
								addlabel(Part1,0)	: rem Just set the label to zero for the moment. 
								getlabel(Part1) : rem recover the label and it's own pointer. 
								setlabel(part1,nextlabel) : rem Set the label to it's own next pointer. 
								GROUP=&h00 : rem and change back to normal label operation. 
							else
								LogError("Label reassignment attempted.")
							endif		
						endif
			CASE	"ENDGROUP"		: rem Was it the end mark of a group?
						Part1=GetWordToEnd (Source)
						if pass(0)=1 then EndGroup (Part1) : rem Establish the end of the group only in pass 1. 
			CASE	"OPEN"			: rem Open a group. Process labels within the group.
						Part1=GetWordToEnd (Source)
						OpenGroup(Part1)
			CASE	"CLOSE"			: rem Close a group - Don't process labels within this group.
						Part1=GetWordToEnd (Source)
						CloseGroup(Part1)
			CASE	"FATAL"			: rem FATAL error forced. 
					Logerror ("Source forced fatal error.")
			CASE	";"				: rem Comment - Do nothing. 
			
			CASE ELSE
				rem LABEL HERE - Figure out how to do it between here and TEST_LABEL. 

	TEST_LABEL:						: rem If we got a :, it's a label no matter what it looks like. We need to see if it's valid.

		if Instruction <> "" then
	rem		PRINT "LABEL FOUND...";instruction,">";op;"<"
			
			if op=":" and pass(0)=1 then 
				PC=LABEL16(ORGPC)
				ADDLABEL(instruction,PC)
				
	rem			Print "ADDED LABEL >";instruction;"=";hex(PC,4);"<"
				
				Goto Post_Select
			else
					if op=":" then 
						if vallabel(instruction) <> label16(ORGPC) then 
							logwarning ("Positional label value changed between passes.")
							
							print "Positional label error - Value returned:";vallabel(instruction)," At PC location:";PC," Conditional:";conditional
							
							Goto Post_Select
						else
							rem print "Label Sanity Check:";vallabel(instruction),PC
							Goto Post_Select
						endif
					endif

					if op<>":" then 
	rem 				Print "Instruction:";instruction
						If GetLabel(Instruction)=0 then 
							LogError ("Macro or Instruction not recognized")
						else
	rem 						Print "Macro Found - contents:";macrotext
							GETPARAMETERS	 : rem Look for any further parameters after the macro, and turn them into arguments. a
							RECURSEIN(MacroText)
							Goto Post_Select
						Endif
					Endif
			endif
				



		endif
	rem We should have written an instruction here.
	rem LABEL will take care of labels.
	rem We can check for errors here too by reviewing ERRORMESSAGE.


			if Instruction <> "" then 
				LOGERROR ("Invalid Instruction Line:"+str(linenumber) +"   "+instruction )
			endif
			
	End Select
	
endif : rem ENDIF of SELECT... For Conditional.


POST_SELECT:
rem We might jump here if we validate "non-instructions" such as labels. 

rem We got our code now, let's write it out....
if debug=1 then PRINT "OPCODE:";hex(asc(opcode),2)
						
End Sub



Sub Assemble
rem Main routines called to assemble stuff. Assemble a single line at a time. 

	rem Per Assembly Call variables. 
	LineNumber=1
	EOL=0
	INSTRING="" : rem We are NOT in quotes. 
	
rem Create code base space.
CODEBASE=STRING(66000,0)
rem Make it bigger in case we overwrite. Test for that later. 
	
	Fetch_Next_Instruction:
	
	rem Set up variables here. 
	rem INITIALISE:
	rem Set up the instruction variables. 
	TOEND=0
	op=""
	
	rem Clear instruction-relevant variables.
	NOTRANSLATE=0
	PREFIX1=""
	PREFIX2=""
	POSTFIX=""
	DISPLACEMENT=""
	DontIgnoreEOL=0 : rem Treat EOL as "whitespace" before finding the next word. 
	opcode=""
	OPERAND=""
	WORD16=0	: rem Note that any operand is only 8 bit at this time. 
	SPECIAL_OPERATOR="" : rem No special operators at this stage. 
	SOURCELINE="" : Rem Clear the recorded source being processed. 
		

	
	if EOL=1 then 
		LineNumber=LineNumber+1 : rem We might have ended the last line with a new line. 
		EOL=0
	endif
	
	part1=""
	part2="" : rem blank them out. Nothing carried over. 
	INSTRUCTION = GetWord (SOURCE)
	TEST_INSTRUCTION : rem Test the instruction.
	
	
if debug=1 then
		print "Instruction:";hexout(prefix1);":";hexout(prefix2);":";
		print hexout(opcode);
		print ":";hexout(displacement);":";hexout(operand)
		Print "EOF:";F_EOF,EOL
	endif

	WriteCode : rem Write the bytes to memory / hex / PRN. 

	if FAIL > 1 then print "Assembly Halted due to last failure.": goto ASSEMBLY_DONE
	
	if F_EOF <> 0 and depth=0 then 
		goto ASSEMBLY_DONE
	endif
	
	if F_EOF <> 0 and depth>0 then
rem	print "Depth:";depth,"LenSource:";len(source)
		RecurseOut("null")
		F_EOF=0
rem	print "Depth:";depth,"LenSource:";len(source)
	endif	
		
	goto Fetch_Next_Instruction
	
ASSEMBLY_DONE:	

End Sub

sub Preassemble
	rem Set up initialisation variables for an assembly pass here. 
	FILEPOINTER=1 : REM CRITICAL START
	F_EOF=0 : REM CRITICAL START
	DEBUG=0

	conditional=0
	noundocs=1 : rem Don't show undocumented code warnings. 

	LASTBYTE=0 

	ASMFILE=loadfile(asmfilename) : rem Load up the file once or twice... 
	if ASMFILE="" then logerror ("Source File Empty or Does Not Exist.") : rem ASMFILE=loadfile("DEFAULT.ASM")
	SOURCE=ASMFILE	: rem Load the main file into the source string. 

	Outfile=openfile(outfilename) : rem Open the output file. 
	One_More_Time=0 : rem No Recursive passes in global. 
	
	SETLABEL16 (ORGPC,&h0100) 	:rem Set default start location if we don't see an ORG. 
	Setlabel16 (PCOFF,0)		:rem Clear any offset unless specified.  	
End Sub

rem #######################################################
rem #######################################################
rem ##                                                   ##
rem ##  Main routines start here.                        ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem ##                                                   ##
rem #######################################################
rem #######################################################

SETUPVARIABLES:	
Rem fill the memory with 0's
For Firstbyte=1 to 65536
BINARYCODE=BINARYCODE+chr(0)
Next Firstbyte

rem BUILD LABELS FIRST - Otherwise we might damage system variables. 
LABELTABLE=CHR(0)+CHR(0) : rem CRITICAL START
BUILDLABELS	: rem Build the system labels. 
rem userlabels=eval("XSYSTEM")
rem print "User labels start:";hex(userlabels,4)

gpass(1)
pass(1)


comline=command
ASMFILENAME=GetFileCLI()
OUTFILENAME=GetFileCLI()

while len(comline) > 0 
rem	Print "Getting Option..."
select case GetFileCLI()
	Case "/P"
rem		PRNFORMAT=1
		SETLABEL16(XDEBUG,&h2101)
	Case "/O"
rem		PRNFORMAT=2
		SETLABEL16(XDEBUG,&h2102)
	Case "/H"
		rem Intel Hex Output.
		INTELHEX=1 : rem Intel Hex Format 
	Case "/C"
		rem Write all output to console. But THIS version always IS the console. 
	Case "/I"
		rem Ignore Errors.
	Case "/D"
		rem Disable Output. 
	Case else
		LogError ("CLI Switch unknown")
		Print "ERROR IN CLI SWITCH"
End Select
Wend

if ASMFILENAME="" or OUTFILENAME="" then
	Print "No file specified."
	Print "Format of command is LOKICROSS <SOURCE-FILE> <OUTPUT-FILE> <SWITHCES>"
	Print " Currently supported switches are;"
	Print "  /P - Show PRN output"
	Print "  /O - Show PRN output for both passes"
	Print "  /H - Intel HEX format output."
	Print "  /C - Write output to CONSOLE.TXT"
	Print "  /I - Ignore Errors."
	Print "  /D - Disable Output."
	Print "Example: Lokicross source.asm command.bin /O/C"
	Goto HardExit : rem Do not go any further. 
Endif
	
rem Print "PRNFORMAT:";PRNFORMAT





rem MAIN CODE STARTS HERE:
MAIN:

rem IF PRNFORMAT=1 and pass(0)=2 then print "GPASS LINE MEM  ORG    CODE     SOURCE"
IF LABEL8(XDEBUG)=1 and pass(0)=2 then print "GPASS LINE MEM  ORG    CODE     SOURCE"

Setlabel16 (XPASS,&h0101) : rem Global pass one, Local pass one.
Print "Starting Pass 1"
PreAssemble
ASSEMBLE

Setlabel16 (XPASS,&h0202) : rem Global pass two, Local pass two.
Print "Starting Pass 2"
PreAssemble
ASSEMBLE


If IntelHex <> 0 then
	Print #OUTFILE, IntelString
	Print #OUTFILE, ":00000001FF"
else
	 Print #OUTFILE,mid(Codebase,Firstbyte+1,lastbyte-firstbyte+1); : rem Make sure no CR/LF at the end. 
Endif

rem SHOWLABELS

if fail <> 0 then 
	print "WARNING The following errors were detected during assembly."
	Print errormessage
else
	Print "No Errors Detected."
endif

Print "First Byte At:";hex(firstbyte,4)
Print "Final Byte At:";hex(lastbyte,4)

rem ASMFILE=LoadFile(ASMFILENAME)
rem PRINT ASMFILE

Close #Outfile : rem Close the output file. 

HARDEXIT:

END

