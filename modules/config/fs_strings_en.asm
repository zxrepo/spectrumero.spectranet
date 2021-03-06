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

; English strings for the configuration utility.
.include	"ctrlchars.inc"
.data
.globl STR_ident
.globl STR_basicinit
.globl STR_basinsterr
.globl STR_curfs
.globl STR_under
.globl STR_proto
.globl STR_host
.globl STR_rempath
.globl STR_user
.globl STR_unset
.globl STR_null
.globl STR_passwd
STR_ident: defb	"Configtool  1.0",0
STR_basicinit: defb	"configtool initialized",NEWLINE,0
STR_basinsterr: defb	"Failed to initialize configtool",NEWLINE,0

STR_curfs: defb	"Current settings for FS",0
STR_under: defb	NEWLINE,"========================",NEWLINE,NEWLINE,0
STR_proto: defb	"Proto: ",0
STR_host: defb	"Host : ",0   
STR_rempath: defb	"Path : ",0
STR_user: defb	"User : ",0
STR_unset: defb	"Not set",0
STR_null: defb	"Null",0
STR_passwd: defb	"Password: ",0

.globl STR_show0and1
.globl STR_show1and2
.globl STR_chguser
.globl STR_chgproto
.globl STR_chghost
.globl STR_chgpath
.globl STR_saveexit
.globl STR_abandon
STR_show0and1: defb	"Show details for FS 0 and 1",0
STR_show1and2: defb	"Show details for FS 2 and 3",0
STR_chgproto: defb	"Select protocol for an FS",0
STR_chghost: defb	"Select a host for an FS",0
STR_chgpath: defb	"Select the path on the host",0
STR_chguser: defb	"Set user/password for the host",0
STR_saveexit: defb	"Save configuration and exit",0
STR_abandon: defb	"Abandon changes and exit",0

.globl STR_fsnum
.globl STR_invalidfs
STR_fsnum: defb	"Filesystem (0-3): ",0
STR_invalidfs: defb	"Invalid FS number.",NEWLINE,0

.globl STR_updating
.globl STR_flashdone
.globl STR_erasebork
.globl STR_writebork
STR_updating: defb	"Updating flash...",NEWLINE,0
STR_flashdone: defb	"Complete.",NEWLINE,0
STR_erasebork: defb	"Erase failed!",NEWLINE,0
STR_writebork: defb	"Write failed!",NEWLINE,0

