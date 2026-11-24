// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Power manager SDK, generated from configs/soc.py by mcu-gen: do not edit.
//
// Clock gating, per block:   pm_<block>_clock_gate(gated)
// Power gating, per domain:  pm_<pd>_clock_gate() / _retention() / _off(),
//                            pm_<pd>_on()          (blocking)
// Domains the code depends on (follows_cpu) only sleep with the cores:
//                            pm_<pd>_clock_gate_with_cpu() / ...  then
//                            cpu_sleep_cycles() / cpu_sleep_until() (cpu_sdk.h)
// A call the configuration does not allow (block not configured, always on,
// not clock gated, mode not supported, ...) fails to compile with the reason.
<%
    pm = xalp.get_power_manager()
    pds = pm.get_power_domains() if pm else []
    cgs = pm.get_clock_gates() if pm else []
    configured = xalp.get_configured_peripheral_names()
    cores = [f"{xalp.cpu().get_name()}_0"] if xalp.cpu() else []
    blocks = cores + [p for p in xalp.AVAILABLE_PERIPHERALS]
    modes = [("clock_gate", "clock_gate", 0), ("retention", "retentive", 1), ("off", "off", 2)]

    clash = [pd.name for pd in pds if pd.name.lower() in blocks]
    if clash:
        raise ValueError(f"power domain names {clash} clash with block names in the SDK (pm_<name>_clock_gate)")

    def why_not_cg(name):
        if not pm:
            return "no power manager in the configuration"
        if name not in cores and name not in configured:
            return f"{name} is not in the configuration"
        if name in pm.NOT_GATEABLE:
            return f"{name} is always on"
        return f"{name} is not in clock_gates of Power_manager (configs/soc.py)"
%>\

#ifndef POWER_MANAGER_SDK_H_
#define POWER_MANAGER_SDK_H_

#include <stdbool.h>
#include <stdint.h>

#include "core_v_mcu.h"
% if pm:
#include "power_manager_regs.h"

#define PM_SDK_REG(offset) (*(volatile uint32_t *)(POWER_MANAGER_BASE_ADDRESS + (offset)))
#define PM_SDK_ALL_CORES ((1u << NUM_CORES) - 1)
% endif

// ------------ Clock gating ------------

% for name in blocks:
  % if name in cgs:
static inline void pm_${name}_clock_gate(bool gated) {
  PM_SDK_REG(POWER_MANAGER_CG_${name.upper()}_REG_OFFSET) = gated;
}
  % else:
#define pm_${name}_clock_gate(gated) _Static_assert(0, "pm_${name}_clock_gate: ${why_not_cg(name)}")
  % endif
% endfor

// ------------ Power gating ------------
% for pd in pds:
<%
    P = "POWER_MANAGER_PD_" + pd.name.upper()
    n = pd.name.lower()
    who = ", ".join(pd.blocks) if pd.blocks else "external"
%>\

// ${pd.name}: ${who} (${", ".join(pd.modes)})
  % if pd.cores:
    % for fn, _, _ in modes:
#define pm_${n}_${fn}() _Static_assert(0, "pm_${n}_${fn}: power domain ${pd.name} holds the cores, use cpu_sleep_cycles() or cpu_sleep_until()")
#define pm_${n}_${fn}_with_cpu() _Static_assert(0, "pm_${n}_${fn}_with_cpu: power domain ${pd.name} holds the cores, use cpu_sleep_cycles() or cpu_sleep_until()")
    % endfor
#define pm_${n}_on() _Static_assert(0, "pm_${n}_on: power domain ${pd.name} holds the cores, it wakes on its wake sources")
  % else:
    % for fn, mode, enc in modes:
      % if mode not in pd.modes:
#define pm_${n}_${fn}() _Static_assert(0, "pm_${n}_${fn}: power domain ${pd.name} does not support ${mode}")
#define pm_${n}_${fn}_with_cpu() _Static_assert(0, "pm_${n}_${fn}_with_cpu: power domain ${pd.name} does not support ${mode}")
      % elif pd.follows_cpu:
#define pm_${n}_${fn}() _Static_assert(0, "pm_${n}_${fn}: power domain ${pd.name} follows the cores, use pm_${n}_${fn}_with_cpu() then cpu_sleep_*()")
// Arm ${pd.name} to enter ${mode} when every core sleeps (cpu_sleep_*), it wakes with them
static inline void pm_${n}_${fn}_with_cpu(void) {
  PM_SDK_REG(${P}_WFI_MASK_REG_OFFSET) = PM_SDK_ALL_CORES;
  PM_SDK_REG(${P}_MODE_REG_OFFSET)     = ${enc};
  PM_SDK_REG(${P}_SLEEP_EN_REG_OFFSET) = 1;
}
      % else:
#define pm_${n}_${fn}_with_cpu() _Static_assert(0, "pm_${n}_${fn}_with_cpu: power domain ${pd.name} does not follow the cores (follows_cpu in configs/soc.py)")
// Put ${pd.name} in ${mode} and wait until it is
static inline void pm_${n}_${fn}(void) {
  PM_SDK_REG(${P}_WFI_MASK_REG_OFFSET) = 0;
  PM_SDK_REG(${P}_MODE_REG_OFFSET)     = ${enc};
  PM_SDK_REG(${P}_SLEEP_EN_REG_OFFSET) = 1;
  while (!(PM_SDK_REG(${P}_STATUS_REG_OFFSET) & (1u << ${P}_STATUS_SLEEPING_BIT))) {}
}
      % endif
    % endfor
    % if pd.follows_cpu:
#define pm_${n}_on() _Static_assert(0, "pm_${n}_on: power domain ${pd.name} follows the cores, it wakes with them")
    % else:
// Switch ${pd.name} on and wait until it is
static inline void pm_${n}_on(void) {
  PM_SDK_REG(${P}_SLEEP_EN_REG_OFFSET) = 0;
  while (!(PM_SDK_REG(${P}_STATUS_REG_OFFSET) & (1u << ${P}_STATUS_AWAKE_BIT))) {}
}
    % endif
  % endif
% endfor

#endif // POWER_MANAGER_SDK_H_
