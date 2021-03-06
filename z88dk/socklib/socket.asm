; CALLER linkage for socket()
XLIB socket
LIB socket_callee
XREF ASMDISP_SOCKET_CALLEE

; int socket(int domain, int type, int protocol);
.socket
	pop hl		; return addr
	pop de		; int protocol
	pop bc		; int type
	pop af		; int domain
	push af
	push bc
	push de
	push hl
	jp socket_callee + ASMDISP_SOCKET_CALLEE

