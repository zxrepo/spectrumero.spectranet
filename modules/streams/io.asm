;The MIT License
;
;Copyright (c) 2009 Dylan Smith
;
;Permission is hereby granted, free of charge, to any person obtaining a copy
;of this software and associated documentation files (the "Software"), to deal
;in the Software without restriction, including without limitation the rights
;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the Software is
;furnished to do so, subject to the following conditions:
;
;The above copyright notice and this permission notice shall be included in
;all copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;THE SOFTWARE.
; IO routines for streams
.include	"spectranet.inc"
.include	"streamvars.inc"
.include	"zxsysvars.inc"
.include	"sysvars.inc"
.include	"zxrom.inc"
.include	"defs.inc"
.text
.globl J_modcall
J_modcall:
	call F_fetchpage	; get our memory page
	bit 5, l		; Control stream?
	jp nz, F_control
	bit 6, l		; Listen stream?
	jp nz, F_ctrlstream
	bit 7, l		; MSB set?
	jr nz, F_input		; Call the input routine
	call F_feedbuffer	; Pass writes to the buffer
	jp F_leave

;----------------------------------------------------------------------------
; F_input
; Process input to a stream.
.globl F_input
F_input:
	push hl
	ld hl, ZX_TV_FLAG	; the mode is considered unchanged
	res 3, (hl)
	pop hl

	call F_findmetadata	; get a pointer to metadata in IX
	ld d, (ix+STRM_WRITEBUF); get tx buffer number
	ld a, (ix+STRM_WRITEPTR); get tx buffer pointer
	and a			; if nonzero, flush the buffer
	call nz, .flush1

.isinkey1:
	push hl
	ld hl, (ZX_ERR_SP)	; fetch the current ERR_SP
	ld e, (hl)
	inc hl
	ld d, (hl)
	and a
	ld hl, 0x107F		; Compare with ED_ERROR
	sbc hl, de
	pop hl
	jp nz, .doinkey1

.input1:
	ld d, (ix+STRM_READBUF)	; get the read buffer number
	ld e, (ix+STRM_READPTR)	; and the pointer
	ld a, (ix+STRM_FD)	; get the fd
	ld (v_asave), a		; save it for the loop operation
	xor a			; Is the buffer pointer at 
	cp e			; the start of the buffer?
	jr z, .getdata1		; Yes - so read more data from the network
	
	ld b, (ix+STRM_REMAINING) ; remaining bytes in buffer
	ex de, hl		; and put the buffer pointer in HL
	jr .unloadloop1

.getdata1:
	ld a, (v_asave)		; Get the descriptor
	ld bc, 255		; read up to 255 chars
	ld l, (ix+STRM_FLAGS)	; check flags bit
	bit BIT_ISFILE, l	; is a file?
	jr nz, .readfromfile1
	bit BIT_ISDIR, l	; is a directory?
	jr nz, .readdir1
	push de			; save bufptr
	call RECV
	pop hl			; retrieve bufptr into hl
.readdone1:
	jp c, .readerr1
.readdirdone1:
	ld b, c			; get the length returned into B for djnz

.unloadloop1:
	ld a, (hl)
	cp 0x0d			; This is how the Interface 1 does it...
	jr z, .checkformore1	; Either a CR
	cp 0x0a
	jr z, .checkformore1	; or a linefeed
	cp '"'		
	call z, .addquote1	; Escape the " character to prevent error C
	push hl
	push bc
	rst CALLBAS
	defw 0x0F85		; ROM ADD-CHAR subroutine
	pop bc
	pop hl
	inc l
	djnz .unloadloop1
	ld d, (ix+STRM_READBUF)	; reset everything to get the next set
	ld e, 0			; of bytes
	ld (ix+STRM_READPTR), e	
	ld (ix+STRM_REMAINING), e
	jr .getdata1		; go get it

.addquote1:			; small routine to add an extra "
	push hl			; character to the input stream to
	push bc			; prevent C Nonsense in BASIC
	rst CALLBAS
	defw 0x0F85
	pop bc
	pop hl
	ld a, '"'
	ret

.readfromfile1:
	push de
	push ix
	call READ
	pop ix
	pop hl			; unloadloop uses hl as pointer
	jr .readdone1
.readdir1:
	ld de, INTERPWKSPC	; %opendir does not allocate a buffer
	call READDIR		; so use temporary workspace.
	jp c, .readerr1		; 
	ld hl, INTERPWKSPC
.readdirloop1:
	ld a, (hl)		; never have a partial read doing READDIR.
	and a			; End of string?
	jr z, .exitnopop1	; Return to BASIC
	push hl
	rst CALLBAS		; Feed INPUT
	defw 0x0F85
	pop hl
	inc hl
	jr .readdirloop1

.exitnopop1:
	ld a, 0x0d		; BASIC expects this to end INPUT
	ld l, 0			; signal "munge the stack"
	scf
	jp F_leave

.checkformore1:
	dec b			; do what djnz would have done if it
	xor a			; had got to the end...
	cp b			; no more chars left?
	jr z, .cleardown1
	inc l			; next byte in the buffer
	ld a, (hl)		; see what it is
	cp 0x0d
	jr z, .checklastcr1
	cp 0x0a
	jr z, .checklastcr1
.saveposition1:
	ld (ix+STRM_READPTR), l	; save the current position
	ld (ix+STRM_REMAINING), b	; save bytes remaining
	jr .exitnopop1
.cleardown1:
	ld (ix+STRM_READPTR), 0	; clear bufpos
	ld (ix+STRM_REMAINING), 0	; clear bufsz
	jr .exitnopop1

.checklastcr1:
	dec b			; have we finally finished?
	xor a
	cp b
	jr z, .cleardown1	; yes, just leave now.
	inc l			; otherwise advance the buffer
	jr .saveposition1	; and save where we got to

.flush1:
	dec a			; make actual end position, not new char pos
	ld e, a			; make buffer LSB
	call F_flushbuffer
	ret

.doinkey1:
	ld a, (ix+STRM_FD)	; get the socket
	ld (v_asave), a		; save it
	call POLLFD		; anything to receive?
	jr c, .readerr1		; Read error?
	jr z, .nodata1		; No hay nada

	ld a, (v_asave)		; get the fd back
	ld de, INTERPWKSPC
	ld bc, 1		; read one byte
	call RECV
	jr c, .readerr1
	ld a, (INTERPWKSPC)
	ld l, 1			; signal "don't munge the stack"
	scf			; signal 'character available'
	ret
	
.nodata1:
	xor a			; carry and zero reset - no data
	ld l, 1			; signal "don't munge the stack"
	jp F_leave

.readerrpop1:
	pop hl			; fix the stack
.readerr1:			; TODO error handling
	ld hl, (oneof_line)	; see if we have a line number to go to
	ld a, h
	or l
	jr nz, .eof_jump1

	ld hl, INTERPWKSPC
	call ITOH8
	ld hl, INTERPWKSPC
	call PRINT42
	or 1			; reset carry, reset zero: EOF
	ld l, 1			; signal "don't munge the stack"
	jp F_leave

.eof_jump1:
	ld (ZX_NEWPPC), hl	; set the line number
	xor a
	ld (ZX_NSPPC), a	; and statement number to 0
	jp .exitnopop1		; exit *without* error

;--------------------------------------------------------------------------
; F_ctrlstream
; Handle a control stream (read only) - at the moment, only listening
; sockets.
.globl F_ctrlstream
F_ctrlstream:
	ld a, l			; convert the function
	and 0x0F		; number to the stream number
	rlca
	rlca
	rlca			; LSB of control stream metadata
	ld h, 0x10		; MSB of metadata
	add a, 4		; A=LSB of fd
	ld l, a
	ld a, (hl)		; get the socket descriptor
	
	call POLLFD		; Poll this fd and see if it's ready
	
	ld hl, ZX_TV_FLAG	; the mode is considered unchanged
	res 3, (hl)

	jr z, .nodata2		; Socket has no events

	ld a, '1'		; indicate event
	ld l, 1			; signal "don't munge the stack"
	scf			; signal 'character available'
	ret
	
.nodata2:
	xor a			; carry and zero reset - no data
	ld l, 1			; signal "don't munge the stack"
	jp F_leave

;-------------------------------------------------------------------------
; F_findmetadata
; Finds the data block for the stream in L
.globl F_findmetadata
F_findmetadata:
	ld a, l			; convert the function number to the 
.globl F_findmetadata_a
F_findmetadata_a:		; stream number.
	and 0x0F
	rlca
	rlca
	rlca			; A now = LSB
	ld h, 0x10		; H now = MSB
	ld l, a
	push hl
	pop ix			; transfer the address to IX
	ret

