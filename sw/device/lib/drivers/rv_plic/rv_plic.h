// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Minimal driver of the PLIC (OpenTitan rv_plic), target 0 = hart 0 M-mode.
// Interrupt IDs are the <NAME> defines of core_v_mcu.h.

#ifndef RV_PLIC_H_
#define RV_PLIC_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enable or disable source `id`, with priority `prio` (0 masks it).
void plic_irq_set_enabled(uint32_t id, bool enabled, uint32_t prio);

// Sources with priority <= threshold are masked.
void plic_set_threshold(uint32_t threshold);

// Claim the highest priority pending source (0: none).
uint32_t plic_claim(void);

// Signal the end of the handling of source `id`.
void plic_complete(uint32_t id);

#ifdef __cplusplus
}
#endif

#endif // RV_PLIC_H_
