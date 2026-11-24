// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#ifndef _COREV_MCU_H_
#define _COREV_MCU_H_

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

#define MEMORY_BANKS 1

// AXI slave windows. Primary macro is <NAME>_START_ADDRESS; <NAME>_BASE_ADDRESS
// is provided as an alias so firmware can use either name.
% for s in xalp.bus().get_axi_addr_rules():
#define ${s["macro"]}_START_ADDRESS 0x${f'{s["base"]:016X}'}
#define ${s["macro"]}_BASE_ADDRESS ${s["macro"]}_START_ADDRESS
#define ${s["macro"]}_SIZE 0x${f'{s["size"]:016X}'}
#define ${s["macro"]}_END_ADDRESS (${s["macro"]}_START_ADDRESS + ${s["macro"]}_SIZE)

% endfor

// Register-interface slaves. Primary macro is <NAME>_BASE_ADDRESS;
// <NAME>_START_ADDRESS is provided as an alias so firmware can use either name.
% for r in xalp.bus().get_reg_slaves():
#define ${r["macro"]}_BASE_ADDRESS 0x${f'{r["base"]:016X}'}
#define ${r["macro"]}_START_ADDRESS ${r["macro"]}_BASE_ADDRESS
#define ${r["macro"]}_SIZE 0x${f'{r["size"]:016X}'}
#define ${r["macro"]}_END_ADDRESS (${r["macro"]}_BASE_ADDRESS + ${r["macro"]}_SIZE)

% endfor
<%
    base_axi = [s for s in xalp.bus().get_axi_addr_rules() if "Peripheral" not in s["name"] and s["name"] not in ("llc", "dram")]
    base_reg = xalp.bus().get_reg_slaves()
%>
// Linker-defined base address symbols (from common.ldh). The *address* of each
// symbol is the corresponding base address; use as &__base_<name>.
#ifndef __ASSEMBLER__
% for s in base_axi:
extern char __base_${s["name"]};
% endfor
% for r in base_reg:
extern char __base_${r["name"]};
% endfor
extern char __base_spm;
extern char __base_dram;
#endif // __ASSEMBLER__

// PLIC interrupt sources (IDs)
<%
    interrupts = xalp.get_interrupts()
%>\
#define QTY_INTR 64
% for name, id in (interrupts.get_interrupts().items() if interrupts else []):
#define ${name.upper()} ${id}
% endfor

// Power manager: harts, power domains and clock gate groups
<%
    pm = xalp.get_power_manager()
%>\
#define NUM_CORES ${max(pm.num_cores(), 1) if pm else 1}
% for i, pd in enumerate(pm.get_power_domains() if pm else []):
#define PD_${pd.name.upper()} ${i}
% endfor
#define NUM_PD ${len(pm.get_power_domains()) if pm else 0}
% if pm and pm.get_power_domains():
// Lets the driver check its view of the register layout
#define PM_FIRST_PD_MODE_REG_OFFSET POWER_MANAGER_PD_${pm.get_power_domains()[0].name.upper()}_MODE_REG_OFFSET
% endif
% for i, cg in enumerate(pm.get_clock_gates() if pm else []):
#define CG_${cg.upper()} ${i}
% endfor
#define NUM_CG ${len(pm.get_clock_gates()) if pm else 0}

#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus

#endif // _COREV_MCU_H_
