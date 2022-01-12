format ELF64 executable 3

; syscalls
SYS_WRITE = 1
SYS_EXIT = 60

; files
STDOUT = 1

segment readable writeable
itoa_buff rb 10
itoa_buff_end = $-1

here db 'Here',0xA
here_size = $-here

newline db 0xA
newline_size = $-newline

segment readable executable

; r15 is a counter
entry $
	mov	r15, 10		; var counter <- 10;
	
loop_start: 			; for i < 10 => {
	push	r15			; (buff:string, rax:int) <- itoa(64)
	call	itoa
	pop	r15

	mov	rdi, STDOUT		; print(buff)
	mov	rax, SYS_WRITE
	syscall
	
	mov	rdx, newline_size	; print("\n")
	lea	rsi, [newline]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	
	dec 	r15			; counter <- counter -1;
	cmp 	r15, 0
	jle	loop_end
	jmp 	loop_start	
loop_end:			;}

_end:
	xor	rdi, rdi 	; exit(0)
	mov	rax, SYS_EXIT
	syscall

; itoa takes one argument:
;	a 64 bit integer
; and returns two results:
;	rdx -> the size of the string
; 	rsi -> address of string
;
; registers:
;	rax: parameter
;	r8:  address inside itoa_buffer
itoa:
	push 	rbp
	mov	rbp, rsp
	mov 	rax, [rbp+16] 		; gets the parameter (int64)
	mov 	r8, itoa_buff_end	; start at end of itoa_buffer
	
	cmp 	rax, 0 		; we need to check if the number is less than zero
	jge	itoa_plus	; because the method only works with positive integers
	mov 	cl, '-'		; so to support negatives we append an '-'
	imul 	rax, -1		; and we convert the number to positive
	jmp 	itoa_loop	
itoa_plus:
	mov 	cl, '+'		; case positive => cl <- '+'
itoa_loop:
	xor 	rdx, rdx	; rdx holds remainder
	mov 	rbx, 10		; rbx holds the dividend
	div	rbx		; rax / rbx
				; rdx now holds a number between 0 and 9
	add 	rdx, 48		; convert rdx to char
	mov 	[r8], dl	; and store in itoa_buffer
	dec	r8
	
	cmp 	rax, 0
	jne 	itoa_loop
	
	mov 	[r8], cl	; puts sign at the beginning
	mov	rdx, itoa_buff_end
	inc	rdx		; itoa_buff_end is exclusive
	sub 	rdx, r8		; computes size of string
	mov 	rsi, r8		; r8 is the start of the string
				
itoa_ret:
	mov 	rsp, rbp
	pop 	rbp
	ret
