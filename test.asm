section .text
bits 64
default rel

sys_write	equ		1
sys_open	equ		2
sys_close	equ		3
sys_mmap	equ		9
sys_munmap	equ		11
sys_brk		equ		12
sys_ioctl	equ		16
sys_nsleep	equ		35
sys_exit	equ		60

O_RDWR		equ 	2

FBIOGET_VSCREENINFO	equ	0x4600
FBIOGET_FSCREENINFO	equ	0x4602
FBIOPAN_DISPLAY		equ 0x4606
FBIO_WAITFORVSYNC	equ 0x40044620

PROT_READ			equ 0x0001
PROT_WRITE			equ 0x0002
MAP_SHARED			equ 0x0001


;-------------------------------------------------------------------------------
; It draws a rectangle on the screen using src X and Y and dest X and Y encoded
; in RAX
;-------------------------------------------------------------------------------
draw_rectangle:
	mov rsi,rcx

	mov rbx,rax
	shr rbx,32
	mov eax,eax			; id ands rax with 0xffffffff

	mov ecx,eax
	shr ecx,16			; cx = dest_Y
	movzx eax,ax		; ax = dest_X

	mov edx,ebx
	shr edx,16			; dx = src_Y
	movzx ebx,bx		; bx = src_X

	mov rdi,rbx			; save start_X

drawloop:
	push rax
	push rbx
	push rcx
	mov rax,rdx
	mov rcx,rsi
	call display_pixel
	pop rcx
	pop rbx
	pop rax

	inc rbx
	cmp rbx,rax
	jb drawloop

	mov rbx,rdi			; restore original X

	inc rdx
	cmp rdx,rcx
	jb drawloop

drawexit:
	ret

;-------------------------------------------------------------------------------
; Reads the color of a pixel using X and Y
;-------------------------------------------------------------------------------
; rbx = X
; rax = Y
get_pixel:
	push rbx
	push rdx
	push rdi
	xor rdx,rdx
	mov rdi,r12
	mul rdi
	add rax,rbx
	shl rax,2
	;add rax,[fb_addr]
	add rax,backbuffer
	mov rax,[rax]
	pop rdi
	pop rdx
	pop rbx
	ret
;-------------------------------------------------------------------------------
; It displays a pixel on the screen using X and Y
;-------------------------------------------------------------------------------
; rbx = X
; rax = Y
; rcx = color
display_pixel:
	push rax
	push rbx
	push rcx
	push rdx
	push rdi

	xor rdx,rdx
	mov rdi,r12
	mul rdi
	add rax,rbx
	shl rax,2
	add rax,backbuffer
	mov [rax],ecx
	
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	pop rax
	ret

;----------------------------------------------------------------------
; It uses rdrand so your processor should be fairly recent
;----------------------------------------------------------------------
; rsi = max_val
rand:
	push rdx
	mov edx,0x7FF

verify_rand:
	rdrand rax
	and rax,rdx			; modulo 2048
	cmp rax,rsi
	jae verify_rand

ret_rand:
	pop rdx
	ret


;---------------------------------------------------------------------
; This is the "main" of this program
;---------------------------------------------------------------------
_start:
	mov rdi,fb
	mov esi,O_RDWR
	mov eax,sys_open
	syscall

	test rax,rax
	js error

	mov [fd],rax			; save fd

	mov rdi,rax				; get fd
	mov esi,FBIOGET_VSCREENINFO
	mov rdx,vinfo				; address of the local buffer
	mov eax,sys_ioctl
	syscall

	test rax,rax
	js close_fb_and_exit

	;--------------------------- now we have the framebuffer details
	
	mov eax,[rdx]
	mov r12,rax					; X
	mov ebx,[rdx+4]
	mov r13,rbx					; Y
	mov ecx,[rdx+24]
	xor rdx,rdx
	shr rcx,3					; divide by 8
	mul rbx
	mul rcx

	mov r15,rax					; r15 = fbsize
	shr rax,2					;
	mov r14,rax					; fbsize in pixels


	mov rsi,r15				; framebuffer size
	xor rdi,rdi
	mov edx,PROT_READ | PROT_WRITE
	mov r10,MAP_SHARED
	mov r8,[fd]
	mov r9,rdi
	mov eax,sys_mmap
	syscall

	mov [fb_addr],rax

	;------------------------------ now the fb is mapped. Let's clear it

keep_adding_flakes:
	xor rsi,rsi
	mov edi,timespec
	mov eax,sys_nsleep
	syscall

waitvsync:
	mov rdi,[fd]
	mov esi,FBIO_WAITFORVSYNC
	mov rdx,zero
	mov eax,sys_ioctl
	syscall						; wait for vsync

	; copy the buffer on the screen
	mov rsi,backbuffer
	push rsi
	mov rdi,[fb_addr]
	mov rcx,r15
	push rcx
	shr rcx,3
	rep movsq

	; clear the back buffer
	pop rcx
	shr rcx,3
	xor rax,rax
	pop rdi
	rep stosq

	mov rax,0x03000400031004A0
	mov ecx,0xFFAF0000
	call draw_rectangle

	mov rax,0x020004A002100540
	mov ecx,0xFFAFAF00
	call draw_rectangle

	mov rax,0x02A0054002B005F0
	mov ecx,0xFF0000AF
	call draw_rectangle

;--------------------------------- buffers exchanged and cleared

	xor rsi,rsi
	dec rsi
	call rand
	mov ebp,eax					; pixels per line
	and ebp,0x07				; 4 pixels max per line
	or ebp,ebp
	jz fixed_pixels

	cmp ebp,2
	ja fixed_pixels

add_line_flakes:
	mov ecx,[nr_flakes]
	cmp rcx,r14
	ja unmap

	push rcx
	shl rcx,2
	mov rsi,rcx
	shl rcx,1
	add rcx,rsi					; mul by 12
	add rcx,flakes

	mov rsi,r12
	call rand
	mov [rcx+4],eax

	xor rax,rax					; Y is always 0
	mov [rcx+8],eax

	pop rcx
	inc rcx
	mov [nr_flakes],ecx

	sub ebp,1
	jnz add_line_flakes
	
;---------------------------------- let's display the fixed ones
fixed_pixels:
	mov ecx,[nr_flakes]
	mov rsi,flakes
	jrcxz animate

loop_process_fixed:
	lodsd
	or rax,rax
	jnz process_fixed_pixel
	lodsq					; skip this pixel
	jmp fixed_go_back

process_fixed_pixel:
	push rcx
	lodsd
	mov rbx,rax
	lodsd
	mov ecx,0xFFFFFFFF
	call display_pixel
	pop rcx

fixed_go_back:
	loop loop_process_fixed
	

;---------------------------------- let's advance all the flakes
animate:
	mov ecx,[nr_flakes]
	mov rsi,flakes
	mov rdi,rsi
	or rcx,rcx
	jnz loop_processing
	jmp display_flakes

loop_processing:
	lodsd
	stosd					; advance rdi as well
	or rax,rax
	jz process_pixel
	lodsq					; skip this pixel
	stosq
	loop loop_processing

	jmp display_flakes

process_pixel:
	push rsi
	xor rsi,rsi
	dec rsi
	call rand
	pop rsi

	mov rbx,rax
	and ebx,3
	dec rbx

	lodsd					; get X
	mov [original_x],eax

	cmp bl,2
	jne not_three

	push rax
	push rsi
	xor rsi,rsi
	dec rsi
	call rand
	pop rsi
	mov rbx,rax
	pop rax
	and ebx,1
	jnz not_three

	dec rbx				; make it -1

not_three:
	add rax,rbx
	or rax,rax
	jns check_upper_x

	xor rax,rax
	jmp store_it_is_fine

check_upper_x:
	cmp rax,r12
	jb store_it_is_fine

adjust_x:
	mov eax,1919

store_it_is_fine:
	stosd

	lodsd
	mov [original_y],eax
	inc rax					; increment Y
	cmp rax,r13
	jb store_y

y_too_big:
	mov eax,1079
	mov edx,[rsi-12]			; make it fixed
	inc rdx
	mov [rsi-12],edx

store_y:
	stosd

	; let's verify if the pixel is already set on the screen

	push rbx
	mov ebx,[rsi-8]
	mov eax,[rsi-4]
	call get_pixel
	pop rbx

	or rax,rax
	jz next_pixel

we_have_to_revert_changes:
	xor rax,rax
	mov ebx,[original_x]
	mov eax,[rsi-4]
	call get_pixel
	or rax,rax
	jnz try_left_right

	mov eax,[original_x]

store_x:
	mov [rsi-8],eax
	jmp next_pixel

try_left_right:
	mov ebx,[original_x]
	sub ebx,1
	js try_right
	mov eax,[rsi-4]
	push rbx
	call get_pixel
	pop rbx
	or rax,rax
	jnz try_right
	
	mov rax,rbx
	jmp store_x

try_right:
	mov ebx,[original_x]
	add ebx,1
	cmp rbx,r12
	jae make_it_fixed

	mov eax,[rsi-4]
	push rbx
	call get_pixel
	pop rbx
	or rax,rax
	jnz make_it_fixed
	
	mov rax,rbx
	jmp store_x
	
make_it_fixed:
	mov eax,[original_y]				; get Y
	mov [rsi-4],eax
	mov eax,[rsi-12]
	inc rax
	mov [rsi-12],eax			; set pixel to fixed
	jmp next_pixel

next_pixel:
	sub ecx,1
	jz display_flakes
	jmp loop_processing



;-----------------------------------------------------------------------
display_flakes:
	mov rsi,flakes
	mov ecx,[nr_flakes]
	or rcx,rcx
	jnz loop_display
	jmp keep_adding_flakes

loop_display:
	lodsd
	or rax,rax
	jz just_display
	lodsq
	jmp last_display_loop

just_display:
	push rcx
	lodsd
	mov rbx,rax
	lodsd
	mov ecx,0xFFFFFFFF
	call display_pixel
	pop rcx

last_display_loop:
	loop loop_display

	jmp keep_adding_flakes

;-----------------------------------------------------------------------------
unmap:
	mov rdi,[fb_addr]
	mov rsi,r15
	mov rax,sys_munmap
	syscall

close_fb_and_exit:
	mov rdi,rax
	mov eax,sys_close
	syscall
	
	jmp exit

error:
exit:
	xor rdi,rdi
	mov al,sys_exit
	syscall

;----------------------------------------------
;section .data

fb	db '/dev/fb0',0
fblen equ $ - fb

timespec	dq 0
			dq 5000000

;---------------------------------------------
section .bss
X			dd 0
Y			dd 0
zero		dq 0
original_x	dd 0
original_y	dd 0
fd			dq 0
buffbrk		dq 0
fbmap		dq 0
fb_addr		dq 0
nr_flakes	dd 0
vinfo:		resb 10000
flakes:		resb 1920*1080*12
backbuffer	resd 1920*1080

global _start

