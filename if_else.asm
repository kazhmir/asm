format ELF64 executable 3

; syscalls
SYS_WRITE = 1
SYS_EXIT = 60

; files
STDOUT = 1

segment readable

newline db 0xA
newline_size = $-newline

true db "true"
true_size = $-true

false db "false"
false_size = $-false

branch1 db "first branch", 0xA
branch1_size = $-branch1

branch2 db "second branch", 0xA
branch2_size = $-branch2

segment readable writeable
itoa_buff rb 10
itoa_buff_end = $-1

segment readable executable

; r15 is a counter
entry $
	mov	r15, 10		;
	xor	rbx, rbx	;
	cmp	r15, 10		; a = b
	sete	bl		;
	push	rbx		;

	mov	r15, 9		;
	xor	rbx, rbx	;
	cmp	r15, 10		; a > b
	setg	bl		;
	push	rbx		;

	pop	rdx		;
	pop	rax		;
	add	rdx, rax	;
	xor	rbx, rbx	;
	cmp	rdx, 2		; a and b, both must be 1 so 1 + 1 = 2
	sete	bl
	push	rbx

	pop	r15
	push	r15
	cmp	r15, 1
	jne	L0
	
	mov	rdx, branch1_size	; print("first branch")
	lea	rsi, [branch1]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	jmp 	L1
L0:
	mov	rdx, branch2_size	; print("second branch")
	lea	rsi, [branch2]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	
L1:
	call	btoa
	pop	rbx

	mov	rdi, STDOUT		; print(buff)
	mov	rax, SYS_WRITE
	syscall
	
	mov	rdx, newline_size	; print("\n")
	lea	rsi, [newline]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	
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

	
; btoa takes one argument:
;	a i64 representing a boolean
; and returns two results:
;	rdx -> the size of the string
; 	rsi -> address of string
;
; registers:
;	rax: parameter
btoa:
	push 	rbp
	mov	rbp, rsp
	mov 	rax, [rbp+16] 	; gets the parameter (i64)

	cmp 	rax, 0
	je	btoa_false
	
	mov	rdx, true_size
	mov	rsi, true
	jmp	btoa_ret

btoa_false:
	mov	rdx, false_size
	mov	rsi, false
btoa_ret:
	mov 	rsp, rbp
	pop 	rbp
	ret
