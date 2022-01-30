format ELF64 executable 3

; syscalls
SYS_WRITE = 1
SYS_EXIT = 60

; files
STDOUT = 1

segment readable

docs db 'usage: calc <expression>',0xA,\
	'only works with integers',0xA,\
	'grammar:',0xA,\
	0x9,'Expr = Mult {("-" | "+") Mult}.',            0xA,\
	0x9,'Mult = Term {("-" | "+") Term}.',            0xA,\
	0x9,'Term = ("+" | "-") (integer | "(" Expr ")").', 0xA,\
	0x9,'integer = digit {digit}.',                   0xA
docs_len = $-docs

newline db 0xA
newline_len = $-newline

quotes db 0x22
quotes_len = $-quotes

pos_msg db ' position: '
pos_msg_len = $-pos_msg

error_eof	db 'Unexpected EOF near '
error_eof_len = $-error_eof

error_op	db 'Expected Operator near '
error_op_len = $-error_op

error_num	db 'Expected Number near '
error_num_len = $-error_num

error_paren	db 'Unclosed Parenthesis near '
error_paren_len = $-error_paren

error_sym	db 'Unexpected Symbol near '
error_sym_len = $-error_sym

fatal_div	db 'Fatal Division by zero', 0xA
fatal_div_len = $-fatal_div

segment readable writeable

itoa_buff rb 10
itoa_buff_end = $-1

buff_initial_len rq 1	; for pretty printing errors
buff_start rq 1		; points to the current position in the string
buff_len rq 1		; remaining lenght of string

last_tk_len rq 1	; for unreadind

segment readable executable

;---------------START OF EXECUTION-----------------
entry $
	pop	r14	; argc
	cmp 	r14, 2	; we expect <&filename> <&arg1>
	jne	print_docs

	pop	r14	; discard &filename
	call	len_str
	pop 	r14

	; initialize globals
	mov 	qword [buff_len], rax
	mov 	qword [buff_initial_len], rax
	mov 	qword [buff_start], r14
	mov	qword [last_tk_len], 0

	call	eval
	push	rax
	call	itoa
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	mov	rdx, newline_len	; print("\n")
	lea	rsi, [newline]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	jmp 	main_end
	
print_docs:
	mov	rdx, docs_len	; print(docs)
	lea	rsi, [docs]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
main_end:
	xor	rdi, rdi 	; exit(0)
	mov	rax, SYS_EXIT
	syscall
;---------------END OF EXECUTION-----------------

; eval takes no arguments
; and returns one result
;	rax -> 64bit signed integer
;
; its the start of the recursive descent
; equivalent to:
;	Expr = Mult {("-" | "+") Mult}.
eval:
	push 	rbp
	mov	rbp, rsp
	call	mult
	push	rax
eval_loop:
	call	next
	cmp	rbx, 0		; EOF
	jl	eval_ret
	cmp	rbx, 1		; Operators have lenght 1, we're expecting '-' or '+'
	jne	eval_expect_op
	mov	bl, [rax]
	cmp	bl, '-'
	je	eval_minus
	cmp	bl, '+'
	je	eval_plus
	
	call	unread
	jmp	eval_ret
eval_minus:
	call	mult
	pop	rbx
	sub	rbx, rax
	push	rbx
	jmp	eval_loop

eval_plus:
	call	mult
	pop	rbx
	add	rbx, rax
	push	rbx
	jmp	eval_loop

eval_unexp_symbol:
	push	error_sym
	push	error_sym_len
	call	error
eval_expect_op:
	push	error_op
	push	error_op_len
	call	error
eval_ret:
	pop	rax
	mov 	rsp, rbp
	pop 	rbp
	ret

; mult takes no arguments
; and returns one result
;	rax -> 64bit signed integer
;
; Implements a second level of precedence for * and /
; Equivalent to:
;	Mult = Term {("-" | "+") Term}.
mult:
	push 	rbp
	mov	rbp, rsp
	call	term
	push	rax
mult_loop:
	call	next
	cmp	rbx, 0		; EOF
	jl	mult_ret
	cmp	rbx, 1		; Operators have lenght 1, we're expecting '*' or '/'
	jne	mult_expect_op
	mov	bl, [rax]
	cmp	bl, '*'
	je	mult_mult
	cmp	bl, '/'
	je	mult_div

	call	unread
	jmp	mult_ret
	
mult_div:
	call	term
	mov	rbx, rax
	pop	rax
	xor	rdx, rdx
	cmp	rbx, 0
	je	mult_div_zero
	div	rbx
	push	rax
	jmp	mult_loop

mult_mult:
	call	term
	pop	rbx
	imul	rbx, rax
	push	rbx
	jmp	mult_loop
	
mult_div_zero:
	mov	rdx, fatal_div_len	; print(docs)
	lea	rsi, [fatal_div]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	mov	rdi, 1	 	; exit(1)
	mov	rax, SYS_EXIT
	syscall
mult_expect_op:
	push	error_op
	push	error_op_len
	call	error
mult_ret:
	pop	rax
	mov 	rsp, rbp
	pop 	rbp
	ret


; term takes no arguments
; and returns one result
;	rax -> 64bit signed integer
;
; Here's where the parser calls atoi
; Equivalent to:
;	Term = ("+" | "-") (integer | "(" Expr ")").
term:
	push 	rbp
	mov	rbp, rsp
	call	next
	cmp	rbx, 0 		; EOF
	jl	term_ret
	
	mov	dl, [rax]
	cmp	dl, '+'
	je	term_plus
	
	cmp	dl, '-'
	je	term_minus

	push	1	; signal
	jmp	term_number
term_plus:
	push	1	; signal
	jmp	term_next_number
term_minus:
	push	-1	; signal
	jmp	term_next_number
term_next_number:
	call	next
	cmp	rbx, 0	;EOF
	jl	term_unexp_eof
	mov	dl, [rax]
term_number:
	cmp	dl, '('
	je	term_nested
	cmp	dl, '0'
	jl	term_exp_number
	cmp	dl, '9'
	jg	term_exp_number
	push	rax
	push	rbx
	call	atoi
	pop	r15
	pop	r15
	push	rax
	jmp	term_ret
term_nested:
	call	eval
	push	rax
	call	next
	cmp	rbx, 0	;eof
	jl	term_unexp_eof
	mov	dl, [rax]
	cmp	dl, ')'	;discard ')'
	je	term_ret
	jmp	term_exp_right_paren
term_exp_number:
	push	error_num
	push	error_num_len
	call	error
term_exp_right_paren:
	push	error_paren
	push	error_paren_len
	call	error
term_unexp_eof:
	push	error_eof
	push	error_eof_len
	call	error
term_ret:
	pop	rax
	pop	rbx	; signal
	imul	rax, rbx
	mov 	rsp, rbp
	pop 	rbp
	ret

; takes two arguments:
;	pointer to error message
;	size of error message
error:
	push 	rbp
	mov	rbp, rsp
	
	call	unread
	
	mov 	r15, [rbp+16]	; get parameter (message size)
	mov 	r14, [rbp+24]	; get parameter (message pointer)
	
	mov	rdx, r15	; print(error)
	lea	rsi, [r14]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall

	mov	rdx, quotes_len	; print("\"")
	lea	rsi, [quotes]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall

	mov	rdx, [buff_len]	; print(remaining_buffer)
	mov	rsi, [buff_start]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall
	
	mov	rdx, quotes_len	; print("\"")
	lea	rsi, [quotes]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall

	mov	rdx, pos_msg_len	; print(" position: ")
	lea	rsi, [pos_msg]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall

	mov	r14, qword [buff_initial_len]
	mov	r15, qword [buff_len]
	sub	r14, r15
	push	r14
	call	itoa
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall

	mov	rdx, newline_len	; print("\n")
	lea	rsi, [newline]
	mov	rdi, STDOUT
	mov	rax, SYS_WRITE
	syscall

error_end:
	xor	rdi, rdi 	; exit(1)
	mov	rax, SYS_EXIT
	syscall

; next takes no arguments
; returns
;	rax -> pointer to start of token
;	rbx -> size of token
; Registers
; 	r14 -> pointer inside the string
; 	r15 -> remaining size
; 	rbx -> holds current char
;
; this represents the LEXER, it depends on global variables
; to represent the state of the lexer
next:
	push 	rbp
	mov	rbp, rsp
	mov 	r15, qword [buff_len]	; size
	mov 	r14, qword [buff_start]	; &string

	cmp	r15, 0
	jle	next_eof

next_loop:			; for r15 >= 0 {
	xor 	rbx, rbx
	mov	bl, [r14]
	cmp	bl, '+'
	je	next_OP		; 	case bl {
	cmp	bl, '-'		;		'+', '-', '(', ')', '*', '/' then return new {size => 1, start => r14};
	je	next_OP		;	}
	cmp	bl, '('		
	je	next_OP
	cmp	bl, ')'
	je 	next_OP
	cmp	bl, '*'
	je 	next_OP
	cmp	bl, '/'
	je 	next_OP
	cmp	bl, '0'
	jl	next_continue	;	case bl >= '0' and bl <= '9' then goto next_number;
	cmp	bl, '9'
	jg	next_continue
	jmp	next_number

next_continue:
	dec	r15
	inc	r14
	cmp	r15, 0
	jg	next_loop	; }
next_eof:
	mov	rbx, -1		; end of string
	jmp	next_ret
	
next_number:
	mov	rax, r14	; save the start of the token
	mov	r13, 1		; r13 -> current size of token
	inc	r14
	dec	r15
next_number_loop:
	mov	bl, [r14]
	cmp	bl, '0'
	jl	next_number_ret
	cmp 	bl, '9'
	jg	next_number_ret
	
	inc	r13
	inc	r14
	dec	r15
	
	cmp 	r15, 0
	jg	next_number_loop
next_number_ret:
	mov	rbx, r13
	jmp 	next_ret
	
next_OP:
	mov	rbx, 1
	mov	rax, r14
	inc	r14
	dec	r15
	
next_ret:
	; update globals
	mov 	qword [buff_len], r15
	mov 	qword [buff_start], r14
	mov	qword [last_tk_len], rbx
	
	mov 	rsp, rbp
	pop 	rbp
	ret

; unreads previous token
; can only be called once after a next() call
unread:
	push 	rbp
	mov	rbp, rsp
	mov	r15, qword [last_tk_len]
	mov	r14, qword [buff_len]
	mov	r13, qword [buff_start]

	sub	r13, r15
	add	r14, r15

	mov	qword [last_tk_len], 0
	mov	qword [buff_len], r14
	mov	qword [buff_start], r13
	
unread_ret:
	mov 	rsp, rbp
	pop 	rbp
	ret

; itoa takes one argument:
;	a 64 bit signed integer
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
;	a 64bit signed integer (rax)
; registers:
;	r15 -> size
; 	r14 -> pointer into string
;	rax -> result
;	bl  -> current char
atoi:
	push 	rbp
	mov	rbp, rsp
	
	mov 	r15, [rbp+16] 	; size
	mov	r14, [rbp+24]	; pointer into string
	mov	r13, 1		; signal (positive)

	xor	rax, rax
	xor	rbx, rbx	; we will be working with the bl part
				; but using the entire register to add
				
	cmp	byte [r14], '+'
	je	atoi_plus
	cmp	byte [r14], '-'
	je	atoi_minus
	jmp	atoi_loop
atoi_minus:
	mov	r13, -1
atoi_plus:
	inc	r14
	dec	r15

atoi_loop:
	mov	bl, [r14]	; take a char
	sub	bl, '0'		; convert to number
	imul	rax, 10
	add	rax, rbx

	inc	r14
	dec	r15
	cmp 	r15, 1
	jge 	atoi_loop

	imul	rax, r13

atoi_ret:
	mov 	rsp, rbp
	pop 	rbp
	ret


; takes one argument
;	pointer to null terminated string
; returns one argument
;	rax -> the size of the string
len_str:
	push 	rbp
	mov	rbp, rsp
	mov 	r15, [rbp+16] 	; pointer into string
	
	xor	rax, rax
	xor	rbx, rbx
len_str_loop:
	mov	bl, [r15]
	cmp	bl, 0
	je	len_str_ret	; we don't count the \0
	inc	r15
	inc	rax
	jmp	len_str_loop

len_str_ret:
	mov 	rsp, rbp
	pop 	rbp
	ret
