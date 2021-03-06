;The MIT License
;
;Copyright (c) 2008 Dylan Smith
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
;
; Functions for querying DNS.
;
.include	"sysvars.inc"
.include	"dnsdefs.inc"
.include	"w5100_defs.inc"	
.include	"sockdefs.inc"

;========================================================================
; F_gethostbyname
; Subset of the Unix 'gethostbyname' call. It returns only a list of
; addresses (currently, either zero or one entries long). The parameter
; can either be an IP address in dotted decimal format, or a hostname.
; No lookup is performed if an IP address is detected; the address is
; simply converted to a 4-byte big endian representation of the address.
; Carry flag is set on error, and A contains the return code when an
; error occurs.
; 
; Parameters: HL = pointer to null-terminated string containing address
;             DE = pointer to a buffer in which to return the result
.text
.globl F_gethostbyname
F_gethostbyname:
	push hl
	push de
	call F_ipstring2long	; Was a dotted decimal IP address passed?
	pop de
	pop hl
	ld a, 0			; ensure status is 0 (flags unchanged)
	ret nc			; was an IP - so it's now in the buffer.
	call F_dnsAquery	; no - so try a DNS lookup instead.
	ret

;========================================================================
; F_dnsAquery
; Queries a DNS server for an A record, using the servers enumerated
; in system variables v_nameserver1 and v_nameserver2
;
; Parameters: HL = pointer to null-terminated string containing address
;                  to query
;             DE = pointer to a 4 byte buffer in which to return result
; Returns   : A  = Status (carry is set on error)
;
.globl F_dnsAquery
F_dnsAquery:
	ld (v_queryresult), de	; save the query result pointer

	; set up the query string to resolve in the workspace area
	ld de, buf_workspace+12	; write it after the header
	call F_dnsstring	; string to convert in hl

	xor a
	ld b, 1			; query type A and IN is both 0x01
	ld (hl), a		; MSB of query type (A)
	inc hl
	ld (hl), b		; LSB of query type (A)
	inc hl
	ld (hl), a		; MSB of class (IN)
	inc hl
	ld (hl), b		; LSB of class (IN)
	ld de, buf_workspace-1	; find out the length
	sbc hl, de		; of the query block
	ld (v_querylength), hl	; and save it in sysvars
	
	ld hl, v_nameserver1	; set up the first resolver
	ld (v_cur_resolver), hl	; and save it in sysvars area

	call F_rand16		; generate the DNS query ID
	ld (buf_workspace), hl	; store it at the start of the workspace

	ld hl, query		; start address of standard query data
	ld de, buf_workspace+2	; destination
	ld bc, queryend-query	; bytes to copy
	ldir			; build the query header

	ld hl, dns_port		; set query UDP port
	ld (v_dnssockinfo+4), hl ; to port 53
	ld hl, 0
	ld (v_dnssockinfo+6), hl ; make sure source port is unset

.resolveloop2:
	ld c, SOCK_DGRAM	; Open a UDP socket
	call F_socket
	ret c			; bale out on error
	ld (v_dnsfd), a		; save the file descriptor

	ld hl, (v_cur_resolver)	; get pointer to current resolver address
	ld de, v_dnssockinfo	; point de at sockinfo structure
	ldi			; copy the resolver's ip address
	ldi
	ldi
	ldi

	ld a, 3			; number of retries
	ld (v_dnsretries), a
.sendquery2:
	ld a, (v_dnsfd)
	ld hl, v_dnssockinfo	; reset hl to the sockinfo structure
	ld de, buf_workspace	; point de at the workspace
	ld bc, (v_querylength)	; bc = length of query
	call F_sendto		; send the block of data
	jr c, .errorcleanup2	; recover if there's an error

	; Wait for only a finite amount of time before giving up
	call F_waitfordnsmsg
	jr nc, .getresponse2
	ld a, (v_dnsretries)
	dec a
	ld (v_dnsretries), a
	jr nz, .sendquery2
	ld a, DNS_TIMEOUT
	jr .errorcleanup2	; retries exhausted
	
.getresponse2:
	ld a, (v_dnsfd)
	ld hl, v_dnssockinfo	; reset hl to the socket info structure
	ld de, buf_message	; set de to the message buffer
	ld bc, 512		; maximum message size
	call F_recvfrom
	jr c, .errorcleanup2

	ld a, (v_dnsfd)
	call F_sockclose

	ld hl, buf_workspace	; compare the serial number of
	ld de, buf_message	; the sent query and received
	ld a, (de)		; answer to check that
	cpi			; they are the same. If they
	jr nz, .badmsg2		; are different this indicates something
	inc e			; is seriously borked.
	ld a, (de)
	cpi
	jr nz, .badmsg2

	ld a, (buf_message+dns_bitfield2)
	and 0x0F		; Did we successfully resolve something?
	jr z, .result2		; yes, so process the answer.

	; TODO: query remaining resolvers
	ld a, HOST_NOT_FOUND
	scf
	ret

.errorcleanup2:
	push af
	ld a, (v_dnsfd)		; free up the socket we've opened
	call F_sockclose
	pop af
	ret

.result2:
	call F_getdnsarec	; retrieve the A record from the answer
	jr c, .noaddr2
	ld de, (v_queryresult)	; retrieve pointer to result buffer
	ldi			; copy the IP address
	ldi
	ldi
	ldi
	xor a			; clear return status
	ret

.badmsg2:
	ld a, NO_RECOVERY
	scf
	ret
.noaddr2:
	ld a, NO_ADDRESS	; carry is already set
	ret

;========================================================================
; F_dnsstring
; Convert a string (such as 'spectrum.alioth2.net2') into the format
; used in DNS queries and responses. The string is null terminated.
;
; The format adds an 8 bit byte count in front of every part of the
; complete host/domain, replacing the dots, so 'spectrum.alioth2.net2'
; would become [0x08]spectrum[0x06]alioth[0x03]net - the values in
; square brackets being a single byte (8 bit integer).
;
; Parameters: HL - pointer to string to convert
;             DE - destination address of finished string
; On exit   : HL - points at next byte after converted data
;	      DE is preserved.
.globl F_dnsstring
F_dnsstring:
	ld (v_fieldptr), de	; Set current field byte count pointer
	inc e			; Intial destination address.
.findsep3:
	ld c, 0xFF		; byte counter, decremented by LDI
.loop3:
	ld a, (hl)		; What are we looking at?
	cp '.'			; DNS string field separator?
	jr z, .dot3
	and a			; Null terminator?
	jr z, .done3
	ldi			; copy (hl) to (de), incrementing both
	jr .loop3
.dot3:
	push de			; save current destination address
	ld a, c			; low order of byte counter (255 - bytes)
	cpl			; turn it into the byte count
	ld de, (v_fieldptr)	; retrieve field pointer
	ld (de), a		; store byte counter
	pop de			; get current destination address back
	ld (v_fieldptr), de	; save it
	inc e			; and update pointer to new address
	inc hl			; address pointer at next character
	jr .findsep3		; and get next bit
.done3:
	push de			; save current destination address
	xor a			; put a NULL on the end of the result
	ld (de), a
	ld a, c			; low order of byte count (255 - bytes)
	cpl			; turn it into a byte count
	ld de, (v_fieldptr)	; retrieve field pointer
	ld (de), a		; save byte count
	pop hl			; get current address pointer
	inc hl			; add 1 - hl points at next byte after end
	ret			; finished.

;==========================================================================
; F_getdnsarec
; Gets a DNS 'A' record from an answer. The assumption is that the DNS
; answer is in buf_message (0x3C00).
;
; Returns: HL = pointer to IP address
; Carry flag is set if no A records were in the answer.
.globl F_getdnsarec
F_getdnsarec:
	xor a
	ld (v_ansprocessed), a	; set answers processed = 0
	ld hl, buf_message + dns_headerlen
.questionloop4:
	ld a, (hl)		; advance to the end of the question record
	and a			; null terminator?
	inc hl
	jr nz, .questionloop4	; not null, check the next character
	inc hl			; go past QTYPE
	inc hl
	inc hl			; go past QCLASS
	inc hl
.decodeanswer4:
	ld a, (hl)		; Test for a pointer or a label
	and 0xC0		; First two bits are 1 for a pointer
	jr z, .skiplabel4	; otherwise it's a label so skip it
	inc hl
	inc hl
.recordtype4:
	inc hl			; skip MSB
	ld a, (hl)		; what kind of record?
	cp dns_Arecord		; is it an A record?
	jr nz, .skiprecord4	; if not, advance HL to next answer
.getipaddr4:
	ld bc, 9		; The IP address is the 9th byte
	add hl, bc		; further on in an A record response
	ret			; so return this.
.skiplabel4:
	ld a, (hl)
	and a			; is it null?
	jr z, .recordtype4	; yes - process the record type
	inc hl
	jr .skiplabel4
.skiprecord4:
	ld a, (buf_message+dns_ancount+1)
	ld b, a			; number of RR answers in B
	ld a, (v_ansprocessed)	; how many have we processed already?
	inc a			; pre-increment processed counter
	cp b			; compare answers processed with total
	jr z, .baleout4		; no A records found
	ld (v_ansprocessed), a
	ld bc, 7		; skip forward
	add hl, bc		; 7 bytes - now pointing at data length
	ld b, (hl)		; big-endian length MSB
	inc hl
	ld c, (hl)		; LSB
	inc hl
	add hl, bc		; advance hl to the end of the data
	jr .decodeanswer4	; decode the next answer
.baleout4:
	scf			; set carry flag to indicate error
	ret

;------------------------------------------------------------------------
; F_waitfordnsmsg
; Polls for a response from the DNS server to implement a timeout.
.globl F_waitfordnsmsg
F_waitfordnsmsg:
	ld bc, dns_polltime
.loop5:
	ld a, (v_dnsfd)
	push bc
	call F_pollfd
	pop bc
	ret nz			; data ready
	dec bc
	ld a, b
	or c
	jr nz, .loop5
	scf			; indicate timeout
	ret

.data
query:           defb 0x01,0x00  ; 16 bit flags field - std. recursive query
qdcount:         defb 0x00,0x01  ; we only ever ask one question at a time
ancount:         defw 0x0000     ; No answers in a query
nscount:         defw 0x0000     ; No NS RRs in a query
arcount:         defw 0x0000     ; No additional records
queryend:
