format ELF64 executable 3

; syscalls
SYS_WRITE = 1
SYS_EXIT = 60

; files
STDOUT = 1

segment readable

docs db 'usage: calc <expression>', 0xA, 'only works with integers', 0xA
docs_len = $-docs

newline db 0xA
newline_size = $-newline

segment readable writeable

itoa_buff rb 10
itoa_buff_end = $-1

segment readable executable

;---------------START OF EXECUTION-----------------
; r15 is a counter
entry $
	pop	r14	; argc
	cmp 	r14, 2	; we expect <&filename> <&arg1>
	jne	print_docs

	pop	r14	; discard &filename
	pop	r14	; &arg1
	
	jmp _end

print_docs:
	mov	rdx, docs_len	; print(docs)
	lea	rsi, [docs]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
_end:
	xor	rdi, rdi 	; exit(0)
	mov	rax, SYS_EXIT
	syscall
;---------------END OF EXECUTION-----------------

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


; atoi takes two arguments:
;	start address of a string
;	size of the string
; and returns one result in rax:
;	the integer
; registers:
;	r15 -> size
; 	r14 -> &string
atoi:
	push 	rbp
	mov	rbp, rsp
	
	mov 	r15, [rbp+16] 	; size
	mov	r14, [rbp+24]	; &string

	; unimplemented

ret_atoi:
	mov 	rsp, rbp
	pop 	rbp
	ret
