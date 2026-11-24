// Copyright 2022 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Nicole Narr <narrn@student.ethz.ch>
// Christopher Reinwardt <creinwar@student.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>

.section .text._start

// Minimal CRT0
.global _start
.align 4
_start:
    // Globally disable Machine and Supervisor interrupts
    csrrc x0, mstatus, 10

    // Park SMP harts
    csrr t0, mhartid
    beqz t0, 2f
1:
    wfi
    j 1b
2:
    // Init stack and global pointer iff linked as nonzero
    mv t1, sp
    la t0, __stack_pointer$
    beqz t0, 1f
    mv sp, t0
1:  .option push
    .option norelax
    la t0, __global_pointer$
    beqz t0, 1f
    mv gp, t0
1:  .option pop

    // Store existing stack, global, return pointers on new stack
    addi sp, sp, -24
    sd t1, 0(sp)
    sd gp, 8(sp)
    sd ra, 16(sp)

    // Set the trap vector table (vectored mode, see vectors.S)
    la t0, __vector_start
    ori t0, t0, 1
    csrrw x0, mtvec, t0

    // Zero the .bss section
    la t0, __bss_start      // t0 = bss start address
    la t1, __bss_end        // t1 = bss end address
    sub t2, t1, t0          // t2 = #bytes to zero
    li a0, 0

_zero_bss_loop:
    addi t4, t2, -32
    blez t2, _fp_init           // t2 <= 0? => No bss to zero
    blt t4, x0, _zero_bss_rem   // t4 <  0? => Less than 4 words left
    sd a0, 0(t0)
    sd a0, 8(t0)
    sd a0, 16(t0)
    sd a0, 24(t0)
    addi t2, t2, -32
    addi t0, t0, 32
    bgt t2, x0, _zero_bss_loop  // Still more to go
    j _fp_init

_zero_bss_rem:
    sb a0, 0(t0)
    addi t2, t2, -1
    addi t0, t0, 1
    bgt t2, x0, _zero_bss_rem

_fp_init:
    // Set FS state to "Initial", enabling FP instructions
    li t1, 1
    slli t1, t1, 13
    csrs mstatus, t1

    // Clear all 32 double FP registers
    fcvt.d.l f0, x0
    fmv.d f1, f0
    fmv.d f2, f0
    fmv.d f3, f0
    fmv.d f4, f0
    fmv.d f5, f0
    fmv.d f6, f0
    fmv.d f7, f0
    fmv.d f8, f0
    fmv.d f9, f0
    fmv.d f10, f0
    fmv.d f11, f0
    fmv.d f12, f0
    fmv.d f13, f0
    fmv.d f14, f0
    fmv.d f15, f0
    fmv.d f16, f0
    fmv.d f17, f0
    fmv.d f18, f0
    fmv.d f19, f0
    fmv.d f20, f0
    fmv.d f21, f0
    fmv.d f22, f0
    fmv.d f23, f0
    fmv.d f24, f0
    fmv.d f25, f0
    fmv.d f26, f0
    fmv.d f27, f0
    fmv.d f28, f0
    fmv.d f29, f0
    fmv.d f30, f0
    fmv.d f31, f0

    // Set FS state to "Clean"
    csrrc x0, mstatus, t1

    // Call initialization function
    call cvm_init

    // Full fence, then jump to main
    fence
    call main

// If main returns, we end up here. This is a local label (not the libc _exit,
// which lives in syscalls.c) used solely to hand control back to the boot context.
.align 4
_crt_return:
    // Restore the original context registers (sp last)
    ld ra, 16(sp)
    ld gp, 8(sp)
    ld sp, 0(sp)
    // Publish the return value and raise the exit flag (value first): the
    // caller may be the boot ROM, or nobody at all under JTAG.
    la t1, __base_soc_ctrl
    sw a0, 4(t1)     // SOC_CTRL.EXIT_VALUE
    li t0, 1
    sw t0, 0(t1)     // SOC_CTRL.EXIT_VALID
    // Hand over to whatever called us, passing return
    ret

