// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Interrupt example: the UART TX-empty interrupt, forced with INTR_TEST,
// reaches the core through the PLIC and is claimed and completed in
// handler_irq_external(). Needs the default configs/soc.py: PLIC with the
// UART.

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "core_v_mcu.h"
#include "cpu_sdk.h"
#include "handler.h"
#include "printf.h"
#include "rv_plic.h"
#include "uart_regs.h"
#include "x-alp.h"

#define PRINTF_IN_FPGA 1
#define PRINTF_IN_SIM 0

#if TARGET_SIM && PRINTF_IN_SIM
#define PRINTF(fmt, ...) printf(fmt, ##__VA_ARGS__)
#elif PRINTF_IN_FPGA && !TARGET_SIM
#define PRINTF(fmt, ...) printf(fmt, ##__VA_ARGS__)
#else
#define PRINTF(...)
#endif

#define REG32(addr) (*(volatile uint32_t *)(addr))

static volatile uint32_t g_irq_id;

void handler_irq_external(void) {
  uint32_t id = plic_claim();
  if (id == UART_INTR_TX_EMPTY) {
    REG32(UART_BASE_ADDRESS + UART_INTR_ENABLE_REG_OFFSET) = 0;
    REG32(UART_BASE_ADDRESS + UART_INTR_STATE_REG_OFFSET) = 1u << UART_INTR_STATE_TX_EMPTY_BIT;
  }
  g_irq_id = id;
  plic_complete(id);
}

int main(void) {
  plic_set_threshold(0);
  plic_irq_set_enabled(UART_INTR_TX_EMPTY, true, 1);
  cpu_irq_enable(CPU_IRQ_EXT);
  cpu_irq_global_enable();
  REG32(UART_BASE_ADDRESS + UART_INTR_ENABLE_REG_OFFSET) = 1u << UART_INTR_STATE_TX_EMPTY_BIT;
  REG32(UART_BASE_ADDRESS + UART_INTR_TEST_REG_OFFSET) = 1u << UART_INTR_STATE_TX_EMPTY_BIT;
  for (volatile int i = 0; i < 1000 && !g_irq_id; i++) {}
  cpu_irq_global_disable();
  plic_irq_set_enabled(UART_INTR_TX_EMPTY, false, 0);

  bool ok = g_irq_id == UART_INTR_TX_EMPTY;
  PRINTF("uart interrupt via plic: %s\n", ok ? "OK" : "FAIL");
  PRINTF("Interrupt example %s\n", ok ? "passed" : "FAILED");
  return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
