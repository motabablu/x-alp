// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "power_manager.h"

#include "core_v_mcu.h"
#include "power_manager_regs.h"

#ifdef POWER_MANAGER_BASE_ADDRESS // only when the power manager is configured

#define PM_REG(offset) (*(volatile uint32_t *)(POWER_MANAGER_BASE_ADDRESS + (offset)))

// Register layout of power_manager.hjson.tpl: after the wake-up timer, one
// block of kPdRegs registers per power domain, then one per clock gate group.
enum { kPdMode, kPdSleepEn, kPdWfiMask, kPdWakeLo, kPdWakeHi, kPdWakeTimer, kPdDelay, kPdWaitAck, kPdStatus, kPdRegs };

#define PD_BASE (POWER_MANAGER_WAKEUP_TIMER_STATUS_REG_OFFSET + 4)
#define PD_REG(pd, r) PM_REG(PD_BASE + 4 * ((pd) * kPdRegs + (r)))
#define CG_REG(cg) PM_REG(PD_BASE + 4 * (NUM_PD * kPdRegs + (cg)))
// Per-hart registers: WAKEUP_STATE, RESTORE_ADDR_LO, RESTORE_ADDR_HI
#define HART_REG(hart, reg) PM_REG(POWER_MANAGER_##reg##_0_REG_OFFSET + 12 * (hart))

#ifdef PM_FIRST_PD_MODE_REG_OFFSET
_Static_assert(PD_BASE == PM_FIRST_PD_MODE_REG_OFFSET, "power_manager register layout changed");
#endif

// Context saved before switching a hart off: x0-x31, mstatus, mie, mtvec,
// mscratch, mepc, fcsr, f0-f31 (see power_manager_cpu_ctx.S)
#define PM_CTX_WORDS 70
uint64_t pm_cpu_ctx[NUM_CORES][PM_CTX_WORDS];

int pm_cpu_save_and_wfi(uint64_t *ctx, volatile uint32_t *sleep_en);
void pm_cpu_restore(void);

void pm_pd_set_mode(uint32_t pd, pm_mode_t mode) {
  PD_REG(pd, kPdMode) = mode;
}

void pm_pd_set_wfi_mask(uint32_t pd, uint32_t cores) {
  PD_REG(pd, kPdWfiMask) = cores;
}

void pm_pd_set_wake_mask(uint32_t pd, uint64_t intr_mask, bool timer) {
  PD_REG(pd, kPdWakeLo) = (uint32_t)intr_mask;
  PD_REG(pd, kPdWakeHi) = (uint32_t)(intr_mask >> 32);
  PD_REG(pd, kPdWakeTimer) = timer;
}

void pm_pd_set_delay(uint32_t pd, uint16_t cycles) {
  PD_REG(pd, kPdDelay) = cycles;
}

void pm_pd_sleep(uint32_t pd) {
  PD_REG(pd, kPdSleepEn) = 1;
}

void pm_pd_wake(uint32_t pd) {
  PD_REG(pd, kPdSleepEn) = 0;
}

bool pm_pd_is_sleeping(uint32_t pd) {
  return PD_REG(pd, kPdStatus) & 1u; // STATUS.SLEEPING
}

void pm_cg_set(uint32_t cg, bool gated) {
  CG_REG(cg) = gated;
}

void pm_wakeup_timer_start(uint32_t cycles) {
  PM_REG(POWER_MANAGER_WAKEUP_TIMER_EN_REG_OFFSET) = 0;
  PM_REG(POWER_MANAGER_WAKEUP_TIMER_REG_OFFSET) = cycles;
  PM_REG(POWER_MANAGER_WAKEUP_TIMER_EN_REG_OFFSET) = 1;
}

void pm_wakeup_timer_stop(void) {
  PM_REG(POWER_MANAGER_WAKEUP_TIMER_EN_REG_OFFSET) = 0;
}

int pm_cpu_sleep(uint32_t pd, pm_mode_t mode) {
  uint64_t hart;
  asm volatile("csrr %0, mhartid" : "=r"(hart));

  pm_pd_set_mode(pd, mode);
  if (mode != kPmModeOff) {
    pm_pd_sleep(pd);
    asm volatile("wfi");
    // The wake disarms the domain; disarm it anyway if WFI did not stall
    pm_pd_wake(pd);
    return 0;
  }

#if defined(PD_LLC) && defined(LLC_START_ADDRESS)
  // The context must survive: not in the LLC scratchpad if the LLC goes off
  uintptr_t ctx = (uintptr_t)pm_cpu_ctx[hart];
  if (ctx >= LLC_START_ADDRESS && ctx < LLC_END_ADDRESS && PD_REG(PD_LLC, kPdMode) == kPmModeOff &&
      PD_REG(PD_LLC, kPdSleepEn)) {
    return -1;
  }
#endif

  uintptr_t restore = (uintptr_t)&pm_cpu_restore;
  HART_REG(hart, RESTORE_ADDR_LO) = (uint32_t)restore;
  HART_REG(hart, RESTORE_ADDR_HI) = (uint32_t)(restore >> 32);
  HART_REG(hart, WAKEUP_STATE) = 1;

  int restored = pm_cpu_save_and_wfi(pm_cpu_ctx[hart], &PD_REG(pd, kPdSleepEn));

  // Restored (1) or WFI returned before the switch off (0): next reset boots
  HART_REG(hart, WAKEUP_STATE) = 0;
  pm_pd_wake(pd);
  return restored;
}

#endif // POWER_MANAGER_BASE_ADDRESS
