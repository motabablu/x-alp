// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "rv_plic.h"

#include "core_v_mcu.h"
#include "rv_plic_regs.h"

#ifdef RV_PLIC_BASE_ADDRESS  // only when the PLIC is configured

#define PLIC_REG(offset) (*(volatile uint32_t *)(RV_PLIC_BASE_ADDRESS + (offset)))

void plic_irq_set_enabled(uint32_t id, bool enabled, uint32_t prio) {
  volatile uint32_t *ie = &PLIC_REG(RV_PLIC_IE0_0_REG_OFFSET + 4 * (id / 32));
  PLIC_REG(RV_PLIC_PRIO0_REG_OFFSET + 4 * id) = prio;
  if (enabled) {
    *ie |= 1u << (id % 32);
  } else {
    *ie &= ~(1u << (id % 32));
  }
}

void plic_set_threshold(uint32_t threshold) { PLIC_REG(RV_PLIC_THRESHOLD0_REG_OFFSET) = threshold; }

uint32_t plic_claim(void) { return PLIC_REG(RV_PLIC_CC0_REG_OFFSET); }

void plic_complete(uint32_t id) { PLIC_REG(RV_PLIC_CC0_REG_OFFSET) = id; }

#endif // RV_PLIC_BASE_ADDRESS
