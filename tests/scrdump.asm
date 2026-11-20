; scrdump - write the text screen to standard output, for tests/run.sh
;
; Writes each row of the current text screen (the BIOS's column count,
; 0040:004A, and row count, 0040:0084 plus 1, or 25 if that is 0) as a
; line, without trailing spaces, ending in CR LF.  Video memory is at
; B000h for a monochrome adapter (CRTC port 3B4h at 0040:0063), else
; B800h, page 0.  With standard output redirected to a file, this shows
; what a program wrote to the console before it, such as ls's default
; multi-column output.
;
;   nasm -f bin -o scrdump.com scrdump.asm

        cpu     8086
        org     100h

start:
        mov     ax, 40h
        mov     es, ax
        mov     cx, [es:4Ah]            ; columns
        mov     [cols], cx
        mov     al, [es:84h]            ; rows - 1 (EGA and later)
        xor     ah, ah
        inc     ax
        cmp     ax, 1
        jne     .rows
        mov     ax, 25
.rows:  mov     [rows], ax
        mov     ax, 0B800h
        cmp     word [es:63h], 3B4h
        jne     .seg
        mov     ax, 0B000h
.seg:   mov     es, ax
        xor     si, si                  ; offset of the row in video memory

.row:   mov     cx, [cols]
        mov     di, line
        push    si
.copy:  mov     al, [es:si]
        mov     [di], al
        inc     di
        add     si, 2
        loop    .copy
        pop     si
.trim:  cmp     di, line
        je      .eol
        cmp     byte [di-1], ' '
        jne     .eol
        dec     di
        jmp     .trim
.eol:   mov     word [di], 0A0Dh
        add     di, 2
        mov     cx, di
        sub     cx, line
        mov     dx, line
        mov     bx, 1
        mov     ah, 40h
        int     21h
        mov     ax, [cols]
        shl     ax, 1
        add     si, ax
        dec     word [rows]
        jnz     .row

        mov     ax, 4C00h
        int     21h

cols:   dw      0
rows:   dw      0
line:   times   260 db 0
