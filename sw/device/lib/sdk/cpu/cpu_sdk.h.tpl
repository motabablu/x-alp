// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// CPU SDK, generated from configs/soc.py by mcu-gen: do not edit.
//
// cpu_sleep_cycles(mode, cycles) and cpu_sleep_until(mode, irq_mask) put the
// calling core to sleep in its power domain; domains armed with
// pm_<pd>_<mode>_with_cpu() (power_manager_sdk.h) sleep and wake with it.
// `mode` must be a constant pm_mode_t the domain supports, or the call fails
// to compile. Both return 1 when the core was switched off and restored.
<%
    pm = xalp.get_power_manager()
    pds = pm.get_power_domains() if pm else []
    cpu_pd = next((pd for pd in pds if 0 in pd.cores), None)
    follow = [pd for pd in pds if pd.follows_cpu]
    interrupts = xalp.get_interrupts()
    has_timer = interrupts is not None and interrupts.get_interrupt("power_manager_wakeup_timer") is not None
    has_plic = "rv_plic" in xalp.get_configured_peripheral_names()
    enc = {"clock_gate": 0, "retentive": 1, "off": 2}
    why_not = None
    if not pm:
        why_not = "no power manager in the configuration"
    elif cpu_pd is None:
        why_not = "the core is not in a power domain (configs/soc.py)"
    elif not has_plic:
        why_not = "no rv_plic: the core leaves WFI through the PLIC"
%>\

#ifndef CPU_SDK_H_
#define CPU_SDK_H_

#include <stdbool.h>
#include <stdint.h>

#include "core_v_mcu.h"
% if not why_not:
#include "power_manager.h"
#include "power_manager_regs.h"
#include "rv_plic_regs.h"
% endif

// mie bits
#define CPU_IRQ_SW (1u << 3)
#define CPU_IRQ_TIMER (1u << 7)
#define CPU_IRQ_EXT (1u << 11)

static inline void cpu_wfi(void) { asm volatile("wfi"); }
static inline void cpu_fence(void) { asm volatile("fence" ::: "memory"); }

static inline uint64_t cpu_hartid(void) {
  uint64_t h;
  asm volatile("csrr %0, mhartid" : "=r"(h));
  return h;
}

static inline uint64_t cpu_cycles(void) {
  uint64_t c;
  asm volatile("csrr %0, mcycle" : "=r"(c));
  return c;
}

static inline void cpu_irq_global_enable(void) { asm volatile("csrsi mstatus, 8" ::: "memory"); }
static inline void cpu_irq_global_disable(void) { asm volatile("csrci mstatus, 8" ::: "memory"); }
static inline void cpu_irq_enable(uint64_t mask) { asm volatile("csrs mie, %0" ::"r"(mask) : "memory"); }
static inline void cpu_irq_disable(uint64_t mask) { asm volatile("csrc mie, %0" ::"r"(mask) : "memory"); }

% if why_not:
#define cpu_sleep_cycles(mode, cycles) _Static_assert(0, "cpu_sleep_cycles: ${why_not}")
#define cpu_sleep_until(mode, irq_mask) _Static_assert(0, "cpu_sleep_until: ${why_not}")
% else:
<%
    P = "POWER_MANAGER_PD_" + cpu_pd.name.upper()
%>\
#define PM_CPU_REG(offset) (*(volatile uint32_t *)(POWER_MANAGER_BASE_ADDRESS + (offset)))
#define PLIC_CPU_REG(offset) (*(volatile uint32_t *)(RV_PLIC_BASE_ADDRESS + (offset)))

// Modes of power domain ${cpu_pd.name}, as a mask of pm_mode_t
#define CPU_PD_MODES ${hex(sum(1 << enc[m] for m in cpu_pd.modes))}u
#define CPU_PD_SUPPORTS(mode) ((CPU_PD_MODES >> (mode)) & 1u)

// Wake sources of the core domain and of the domains following it
static inline void cpu_set_wake_(uint64_t irq_mask, bool timer) {
  % for pd in [cpu_pd] + follow:
<%
    Q = "POWER_MANAGER_PD_" + pd.name.upper()
%>\
  PM_CPU_REG(${Q}_WAKE_MASK_LO_REG_OFFSET) = (uint32_t)irq_mask;
  PM_CPU_REG(${Q}_WAKE_MASK_HI_REG_OFFSET) = (uint32_t)(irq_mask >> 32);
  PM_CPU_REG(${Q}_WAKE_TIMER_REG_OFFSET)   = timer;
  % endfor
}

static inline int cpu_sleep_until_(pm_mode_t mode, uint64_t irq_mask) {
  cpu_set_wake_(irq_mask, false);
  cpu_irq_enable(CPU_IRQ_EXT);  // WFI returns on the PLIC (no trap if mstatus.MIE = 0)
  return pm_cpu_sleep(PD_${cpu_pd.name.upper()}, mode);
}

// Sleep until one of the PLIC sources of irq_mask (bit = source ID) fires.
// The application enables those sources in the PLIC and handles them.
#define cpu_sleep_until(mode, irq_mask) ({ _Static_assert(CPU_PD_SUPPORTS(mode), "cpu_sleep_until: mode not supported by power domain ${cpu_pd.name}"); cpu_sleep_until_(mode, irq_mask); })

  % if has_timer:
static inline int cpu_sleep_cycles_(pm_mode_t mode, uint32_t cycles) {
  uint32_t id = POWER_MANAGER_WAKEUP_TIMER;
  // Interrupts off while sleeping: the timer only makes WFI return, it must
  // not trap into the application handler (mstatus.MIE restored at the end)
  uint64_t mstatus;
  asm volatile("csrrci %0, mstatus, 8" : "=r"(mstatus)::"memory");
  // The timer reaches the core through the PLIC with priority 7, reserved to it
  PLIC_CPU_REG(RV_PLIC_PRIO0_REG_OFFSET + 4 * id) = 7;
  PLIC_CPU_REG(RV_PLIC_IE0_0_REG_OFFSET + 4 * (id / 32)) |= 1u << (id % 32);
  cpu_set_wake_(0, true);
  cpu_irq_enable(CPU_IRQ_EXT);

  PM_CPU_REG(POWER_MANAGER_WAKEUP_TIMER_EN_REG_OFFSET) = 0;
  PM_CPU_REG(POWER_MANAGER_WAKEUP_TIMER_REG_OFFSET)    = cycles;
  PM_CPU_REG(POWER_MANAGER_WAKEUP_TIMER_EN_REG_OFFSET) = 1;
  int restored = pm_cpu_sleep(PD_${cpu_pd.name.upper()}, mode);
  PM_CPU_REG(POWER_MANAGER_WAKEUP_TIMER_EN_REG_OFFSET) = 0;

  // Acknowledge the timer only: when pending, its priority 7 makes it the
  // source a claim returns. (Do not read THRESHOLD0: on the 64-bit bus that
  // read also reads CC, i.e. claims.)
  if (PLIC_CPU_REG(RV_PLIC_IP_0_REG_OFFSET + 4 * (id / 32)) & (1u << (id % 32))) {
    if (PLIC_CPU_REG(RV_PLIC_CC0_REG_OFFSET) == id) PLIC_CPU_REG(RV_PLIC_CC0_REG_OFFSET) = id;
  }
  PLIC_CPU_REG(RV_PLIC_IE0_0_REG_OFFSET + 4 * (id / 32)) &= ~(1u << (id % 32));
  if (mstatus & 8) cpu_irq_global_enable();
  return restored;
}

// Sleep for `cycles` clock cycles (power manager wake-up timer)
#define cpu_sleep_cycles(mode, cycles) ({ _Static_assert(CPU_PD_SUPPORTS(mode), "cpu_sleep_cycles: mode not supported by power domain ${cpu_pd.name}"); cpu_sleep_cycles_(mode, cycles); })
  % else:
#define cpu_sleep_cycles(mode, cycles) _Static_assert(0, "cpu_sleep_cycles: add the power_manager_wakeup_timer interrupt (configs/soc.py)")
  % endif
% endif

#endif // CPU_SDK_H_
