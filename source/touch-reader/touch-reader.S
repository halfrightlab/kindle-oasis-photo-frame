/* Project-only ARM EABI touch reader. No libc, network, or persistent hooks.
 * EVIOCGRAB is released by the kernel when this process closes/exits.
 * Output: READY, then hex event type/code/value lines. */
.syntax unified
.arm
.text
.global _start
_start:
    sub sp, sp, #96
    adr r0, device_path
    mov r1, #0
    mov r2, #0
    mov r7, #5
    svc #0
    cmp r0, #0
    blt open_failed
    mov r8, r0
    movw r1, #0x4590
    movt r1, #0x4004
    mov r2, #1
    mov r7, #54
    svc #0
    cmp r0, #0
    blt grab_failed
    mov r0, #53
    bl read_slot_zero
    mov r9, r0
    mov r0, #54
    bl read_slot_zero
    mov r11, r0
    mov r0, #1
    adr r1, ready_message
    mov r2, #6
    mov r7, #4
    svc #0
    /* evdev suppresses unchanged axes across contacts. Seed both coordinates
     * from slot zero so the first tap works even at the previous tap's Y. */
    mov r0, #3
    strh r0, [sp, #8]
    mov r0, #53
    strh r0, [sp, #10]
    str r9, [sp, #12]
    bl emit_event
    mov r0, #54
    strh r0, [sp, #10]
    str r11, [sp, #12]
    bl emit_event
read_event:
    mov r0, r8
    mov r1, sp
    mov r2, #16
    mov r7, #3
    svc #0
    cmn r0, #4
    beq read_event
    cmp r0, #16
    bne read_failed
    bl emit_event
    b read_event
emit_event:
    mov r10, lr
    ldrh r0, [sp, #8]
    add r1, sp, #32
    mov r2, #4
    bl write_hex
    mov r6, #32
    strb r6, [r1], #1
    ldrh r0, [sp, #10]
    mov r2, #4
    bl write_hex
    strb r6, [r1], #1
    ldr r0, [sp, #12]
    mov r2, #8
    bl write_hex
    mov r6, #10
    strb r6, [r1], #1
    mov r0, #1
    add r1, sp, #32
    mov r2, #19
    mov r7, #4
    svc #0
    cmp r0, #19
    bne read_failed
    bx r10
read_failed:
    mov r0, #3
    b exit_now
open_failed:
    mov r0, #1
    b exit_now
grab_failed:
    mov r0, #2
    b exit_now
query_failed:
    mov r0, #4
exit_now:
    mov r7, #1
    svc #0
read_slot_zero:
    mov r12, lr
    str r0, [sp]
    mov r3, #0
    str r3, [sp, #4]
    mov r0, r8
    movw r1, #0x450a
    movt r1, #0x8008
    mov r2, sp
    mov r7, #54
    svc #0
    cmp r0, #0
    blt query_failed
    ldr r0, [sp, #4]
    bx r12
write_hex:
    sub r2, r2, #1
    mov r3, r2, lsl #2
    mov r4, r0, lsr r3
    and r4, r4, #15
    adr r5, hex_digits
    ldrb r4, [r5, r4]
    strb r4, [r1], #1
    cmp r2, #0
    bne write_hex
    bx lr
hex_digits:
    .ascii "0123456789abcdef"
ready_message:
    .ascii "READY\n"
.align 2
device_path:
    .asciz "/dev/input/event8"
.align 2
