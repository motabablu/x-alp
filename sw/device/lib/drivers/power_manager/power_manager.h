// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Power manager driver.
//
// Power domains (PD_<NAME>) and clock gate groups (CG_<NAME>) come from the
// configuration (configs/soc.py) and are numbered in core_v_mcu.h.
//
// A power domain sleeps when it is armed (pm_pd_sleep) and every core of its
// WFI mask is in WFI (an empty mask: at once). It wakes when it is disarmed
// (pm_pd_wake), when an interrupt source of its wake mask fires, when the
// wake-up timer expires (if enabled), or on a debug request of its cores.
// The wake disarms it again.
//
// Do not access the registers of a gated block: the bus stalls until it wakes.

#ifndef POWER_MANAGER_H_
#define POWER_MANAGER_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  kPmModeClockGate = 0,  // clock gated, state kept, fast wake
  kPmModeRetentive = 1,  // + isolation and memory retention
  kPmModeOff       = 2,  // + reset and power switch off, state lost
} pm_mode_t;

void pm_pd_set_mode(uint32_t pd, pm_mode_t mode);
void pm_pd_set_wfi_mask(uint32_t pd, uint32_t cores);
// intr_mask: one bit per PLIC source ID; timer: wake on the wake-up timer
void pm_pd_set_wake_mask(uint32_t pd, uint64_t intr_mask, bool timer);
void pm_pd_set_delay(uint32_t pd, uint16_t cycles);
void pm_pd_sleep(uint32_t pd);
void pm_pd_wake(uint32_t pd);
bool pm_pd_is_sleeping(uint32_t pd);

void pm_cg_set(uint32_t cg, bool gated);

// Wake-up timer: expires `cycles` clock cycles after the start. When expired
// it is a wake source and the PLIC source POWER_MANAGER_WAKEUP_TIMER.
void pm_wakeup_timer_start(uint32_t cycles);
void pm_wakeup_timer_stop(void);

// Put the calling hart to sleep in power domain `pd` with `mode`, then return
// once woken. Set the wake mask first. In kPmModeClockGate/kPmModeRetentive
// the core leaves WFI on an interrupt enabled in mie (mstatus.MIE may be 0),
// so the wake source must also reach the core. In kPmModeOff the core is
// reset on wake and its context is restored from memory: that memory must
// stay powered.
// Returns 1 when the core was switched off and restored, 0 when it only
// slept (or did not sleep at all), -1 on error.
int pm_cpu_sleep(uint32_t pd, pm_mode_t mode);

#ifdef __cplusplus
}
#endif

#endif // POWER_MANAGER_H_
