// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Power manager registers, generated from the Power_manager configuration.
// PD_<name>_* registers exist for every power domain, CG_<name> for every
// clock gate group, *_<h> for every hart.
<%
    pm = xalp.get_power_manager()
    pds = pm.get_power_domains() if pm else []
    cgs = pm.get_clock_gates() if pm else []
    num_cores = max(pm.num_cores(), 1) if pm else 1
    wfi_bits = "0" if num_cores == 1 else str(num_cores - 1) + ":0"
%>\
{ name: "power_manager",
  clock_primary: "clk_i",
  bus_interfaces: [
    { protocol: "reg_iface", direction: "device" }
  ],
  regwidth: "32",
  registers: [
% for h in range(num_cores):
    { name:     "WAKEUP_STATE_${h}",
      desc:     "Set by SW before switching hart ${h} off: the boot ROM then resumes from RESTORE_ADDR instead of booting",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "none",
      fields: [
        { bits: "0", name: "WAKEUP_STATE", desc: "1: hart ${h} resumes from RESTORE_ADDR after reset" }
      ]
    }
    { name:     "RESTORE_ADDR_LO_${h}",
      desc:     "Restore address of hart ${h}, low 32 bits",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "none",
      fields: [
        { bits: "31:0", name: "RESTORE_ADDR_LO", desc: "Restore address, bits 31:0" }
      ]
    }
    { name:     "RESTORE_ADDR_HI_${h}",
      desc:     "Restore address of hart ${h}, high 32 bits",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "none",
      fields: [
        { bits: "31:0", name: "RESTORE_ADDR_HI", desc: "Restore address, bits 63:32" }
      ]
    }
% endfor
    { name:     "WAKEUP_TIMER",
      desc:     "Wake-up timer reload value, in clock cycles",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "31:0", name: "WAKEUP_TIMER", desc: "Cycles from WAKEUP_TIMER_EN rising to expiry" }
      ]
    }
    { name:     "WAKEUP_TIMER_EN",
      desc:     "Wake-up timer enable",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "0", name: "WAKEUP_TIMER_EN", desc: "0->1 loads WAKEUP_TIMER and starts counting, 0 stops and clears EXPIRED" }
      ]
    }
    { name:     "WAKEUP_TIMER_STATUS",
      desc:     "Wake-up timer status",
      swaccess: "ro",
      hwaccess: "hwo",
      hwext:    "true",
      fields: [
        { bits: "0", name: "EXPIRED", desc: "The timer reached zero (wake source)" }
      ]
    }
% for pd in pds:
<%
    n = pd.name.upper()
    wfi_resval = sum(1 << c for c in pd.cores)
%>\
    { name:     "PD_${n}_MODE",
      desc:     "Sleep mode of power domain ${pd.name} (supports: ${", ".join(pd.modes)})",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "1:0", name: "MODE", desc: "0: clock_gate, 1: retentive, 2: off. An unsupported mode falls back to clock_gate" }
      ]
    }
    { name:     "PD_${n}_SLEEP_EN",
      desc:     "Arms the sleep of power domain ${pd.name}",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hrw",
      fields: [
        { bits: "0", name: "SLEEP_EN", desc: "1: sleep once every core in WFI_MASK is in WFI. 0 wakes the domain. Cleared by HW on wake" }
      ]
    }
    { name:     "PD_${n}_WFI_MASK",
      desc:     "Cores of power domain ${pd.name} must wait for",
      resval:   "${wfi_resval}",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "${wfi_bits}", name: "WFI_MASK", desc: "Cores that must be in WFI before sleeping (0: sleep at once). Their debug requests wake the domain" }
      ]
    }
    { name:     "PD_${n}_WAKE_MASK_LO",
      desc:     "Interrupt sources 31:0 that wake power domain ${pd.name}",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "31:0", name: "WAKE_MASK_LO", desc: "One bit per PLIC source" }
      ]
    }
    { name:     "PD_${n}_WAKE_MASK_HI",
      desc:     "Interrupt sources 63:32 that wake power domain ${pd.name}",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "31:0", name: "WAKE_MASK_HI", desc: "One bit per PLIC source" }
      ]
    }
    { name:     "PD_${n}_WAKE_TIMER",
      desc:     "Wake power domain ${pd.name} when the wake-up timer expires",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "0", name: "WAKE_TIMER", desc: "1: the wake-up timer wakes the domain" }
      ]
    }
    { name:     "PD_${n}_DELAY",
      desc:     "Cycles between two steps of the sleep/wake sequence of power domain ${pd.name}",
      resval:   "4",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "15:0", name: "DELAY", desc: "Cycles between steps" }
      ]
    }
    { name:     "PD_${n}_WAIT_ACK",
      desc:     "Wait for the power switch ack of power domain ${pd.name} when switching on",
      resval:   "1",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "0", name: "WAIT_ACK", desc: "1: wait for the ack, 0: ignore it" }
      ]
    }
    { name:     "PD_${n}_STATUS",
      desc:     "Status of power domain ${pd.name}",
      swaccess: "ro",
      hwaccess: "hwo",
      hwext:    "true",
      fields: [
        { bits: "0", name: "SLEEPING", desc: "The domain is fully asleep" }
        { bits: "1", name: "ACK", desc: "Power switch ack (1: powered)" }
        { bits: "2", name: "AWAKE", desc: "The domain is fully on" }
      ]
    }
% endfor
% for cg in cgs:
    { name:     "CG_${cg.upper()}",
      desc:     "Clock gate of ${cg}",
      resval:   "0",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "0", name: "CG", desc: "1: clock gated" }
      ]
    }
% endfor
  ]
}
