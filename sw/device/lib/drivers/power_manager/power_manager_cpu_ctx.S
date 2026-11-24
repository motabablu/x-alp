// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Context save/restore of a hart switched off by the power manager (RV64).
//
// Context layout (8-byte slots, PM_CTX_WORDS in power_manager.c):
//   1-31 x1-x31, 32 mstatus, 33 mie, 34 mtvec, 35 mscratch, 36 mepc,
//   37 fcsr, 38-69 f0-f31 (only when mstatus.FS != Off)

#define CTX_MSTATUS  256
#define CTX_MIE      264
#define CTX_MTVEC    272
#define CTX_MSCRATCH 280
#define CTX_MEPC     288
#define CTX_FCSR     296
#define CTX_BYTES    560
#define MSTATUS_MIE  0x8
#define MSTATUS_FS   0x6000

.section .text

// int pm_cpu_save_and_wfi(uint64_t *ctx, volatile uint32_t *sleep_en)
// Saves the context, arms the power domain and waits for the switch off.
// Returns 0 if WFI returns (the hart was never switched off), 1 when the
// hart is switched off and later resumed by pm_cpu_restore.
.global pm_cpu_save_and_wfi
.type pm_cpu_save_and_wfi, @function
pm_cpu_save_and_wfi:
    sd x1, 8(a0)
    sd x2, 16(a0)
    sd x3, 24(a0)
    sd x4, 32(a0)
    sd x5, 40(a0)
    sd x6, 48(a0)
    sd x7, 56(a0)
    sd x8, 64(a0)
    sd x9, 72(a0)
    sd x10, 80(a0)
    sd x11, 88(a0)
    sd x12, 96(a0)
    sd x13, 104(a0)
    sd x14, 112(a0)
    sd x15, 120(a0)
    sd x16, 128(a0)
    sd x17, 136(a0)
    sd x18, 144(a0)
    sd x19, 152(a0)
    sd x20, 160(a0)
    sd x21, 168(a0)
    sd x22, 176(a0)
    sd x23, 184(a0)
    sd x24, 192(a0)
    sd x25, 200(a0)
    sd x26, 208(a0)
    sd x27, 216(a0)
    sd x28, 224(a0)
    sd x29, 232(a0)
    sd x30, 240(a0)
    sd x31, 248(a0)
    csrr t0, mstatus
    sd   t0, CTX_MSTATUS(a0)
    csrr t1, mie
    sd   t1, CTX_MIE(a0)
    csrr t1, mtvec
    sd   t1, CTX_MTVEC(a0)
    csrr t1, mscratch
    sd   t1, CTX_MSCRATCH(a0)
    csrr t1, mepc
    sd   t1, CTX_MEPC(a0)
    li   t1, MSTATUS_FS
    and  t1, t0, t1
    beqz t1, 1f
    frcsr t1
    sd   t1, CTX_FCSR(a0)
    fsd f0, 304(a0)
    fsd f1, 312(a0)
    fsd f2, 320(a0)
    fsd f3, 328(a0)
    fsd f4, 336(a0)
    fsd f5, 344(a0)
    fsd f6, 352(a0)
    fsd f7, 360(a0)
    fsd f8, 368(a0)
    fsd f9, 376(a0)
    fsd f10, 384(a0)
    fsd f11, 392(a0)
    fsd f12, 400(a0)
    fsd f13, 408(a0)
    fsd f14, 416(a0)
    fsd f15, 424(a0)
    fsd f16, 432(a0)
    fsd f17, 440(a0)
    fsd f18, 448(a0)
    fsd f19, 456(a0)
    fsd f20, 464(a0)
    fsd f21, 472(a0)
    fsd f22, 480(a0)
    fsd f23, 488(a0)
    fsd f24, 496(a0)
    fsd f25, 504(a0)
    fsd f26, 512(a0)
    fsd f27, 520(a0)
    fsd f28, 528(a0)
    fsd f29, 536(a0)
    fsd f30, 544(a0)
    fsd f31, 552(a0)
1:
    // The D-cache is write-through: the fence is enough for memory to hold it
    li   t0, 1
    sw   t0, 0(a1)
    fence
    wfi
    // Not switched off
    li   a0, 0
    ret
.size pm_cpu_save_and_wfi, .-pm_cpu_save_and_wfi

// Entered from the boot ROM (RESTORE_ADDR) after the hart is switched on.
// Resumes after the pm_cpu_save_and_wfi call that saved the context.
.global pm_cpu_restore
.type pm_cpu_restore, @function
pm_cpu_restore:
    csrr t0, mhartid
    li   t1, CTX_BYTES
    mul  t0, t0, t1
    // gp is not restored yet: no gp-relative relaxation
    .option push
    .option norelax
    la   a0, pm_cpu_ctx
    .option pop
    add  a0, a0, t0
    // Interrupts stay off until the very end
    ld   t0, CTX_MSTATUS(a0)
    li   t1, MSTATUS_MIE
    not  t1, t1
    and  t1, t0, t1
    csrw mstatus, t1
    li   t1, MSTATUS_FS
    and  t1, t0, t1
    beqz t1, 1f
    ld   t1, CTX_FCSR(a0)
    fscsr t1
    fld f0, 304(a0)
    fld f1, 312(a0)
    fld f2, 320(a0)
    fld f3, 328(a0)
    fld f4, 336(a0)
    fld f5, 344(a0)
    fld f6, 352(a0)
    fld f7, 360(a0)
    fld f8, 368(a0)
    fld f9, 376(a0)
    fld f10, 384(a0)
    fld f11, 392(a0)
    fld f12, 400(a0)
    fld f13, 408(a0)
    fld f14, 416(a0)
    fld f15, 424(a0)
    fld f16, 432(a0)
    fld f17, 440(a0)
    fld f18, 448(a0)
    fld f19, 456(a0)
    fld f20, 464(a0)
    fld f21, 472(a0)
    fld f22, 480(a0)
    fld f23, 488(a0)
    fld f24, 496(a0)
    fld f25, 504(a0)
    fld f26, 512(a0)
    fld f27, 520(a0)
    fld f28, 528(a0)
    fld f29, 536(a0)
    fld f30, 544(a0)
    fld f31, 552(a0)
1:
    ld   t1, CTX_MIE(a0)
    csrw mie, t1
    ld   t1, CTX_MTVEC(a0)
    csrw mtvec, t1
    ld   t1, CTX_MSCRATCH(a0)
    csrw mscratch, t1
    ld   t1, CTX_MEPC(a0)
    csrw mepc, t1
    fence.i
    ld x1, 8(a0)
    ld x2, 16(a0)
    ld x3, 24(a0)
    ld x4, 32(a0)
    ld x5, 40(a0)
    ld x6, 48(a0)
    ld x7, 56(a0)
    ld x8, 64(a0)
    ld x9, 72(a0)
    ld x11, 88(a0)
    ld x12, 96(a0)
    ld x13, 104(a0)
    ld x14, 112(a0)
    ld x15, 120(a0)
    ld x16, 128(a0)
    ld x17, 136(a0)
    ld x18, 144(a0)
    ld x19, 152(a0)
    ld x20, 160(a0)
    ld x21, 168(a0)
    ld x22, 176(a0)
    ld x23, 184(a0)
    ld x24, 192(a0)
    ld x25, 200(a0)
    ld x26, 208(a0)
    ld x27, 216(a0)
    ld x28, 224(a0)
    ld x29, 232(a0)
    ld x30, 240(a0)
    ld x31, 248(a0)
    // a0 is the return value, so it is free to restore mstatus (MIE) last
    ld   a0, CTX_MSTATUS(a0)
    csrw mstatus, a0
    li   a0, 1
    ret
.size pm_cpu_restore, .-pm_cpu_restore
