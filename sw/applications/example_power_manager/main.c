// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Power manager example, subsystem by subsystem (as in X-HEEP), with the
// power manager SDK. The core itself sleeps in example_cpu_sdk. Needs the
// default configs/soc.py: power domains cpu and llc (follows_cpu), clock
// gate on the uart, power manager wake-up timer on the PLIC.
//
//   Peripherals UART clock gating
//   Memory      LLC clock gated and retentive together with the CPU, and
//               switched off after a flush when the program runs from DRAM
//
// Calls the configuration does not allow do not compile, e.g.
//   pm_soc_ctrl_clock_gate(true);  // soc_ctrl is always on
//   pm_llc_off();                  // llc follows the cores: pm_llc_off_with_cpu()

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "axi_llc_regs.h"
#include "core_v_mcu.h"
#include "cpu_sdk.h"
#include "power_manager_sdk.h"
#include "printf.h"
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

#define SLEEP_CYCLES 2000

#define REG32(addr) (*(volatile uint32_t *)(addr))

static bool check(bool ok, const char *what) {
  PRINTF("%s: %s\n", what, ok ? "OK" : "FAIL");
  return ok;
}

// Clock-gated sleep: the cycle counter of the core stops with its clock.
// On FPGA the clock gate is a bypass: check the wake-up timer woke the core.
static bool clock_gated_nap(void) {
  uint64_t start = cpu_cycles();
  cpu_sleep_cycles(kPmModeClockGate, SLEEP_CYCLES);
#if TARGET_SIM
  return cpu_cycles() - start < SLEEP_CYCLES;
#else
  return cpu_cycles() - start >= SLEEP_CYCLES;
#endif
}

// Write back and invalidate every cache way. At the end the LLC clears
// CFG_FLUSH (FLUSHED goes back to the scratchpad ways).
static void llc_flush(void) {
  uint32_t ways = (1u << REG32(AXI_LLC_BASE_ADDRESS + AXI_LLC_SET_ASSO_LOW_REG_OFFSET)) - 1;
  ways &= ~REG32(AXI_LLC_BASE_ADDRESS + AXI_LLC_CFG_SPM_LOW_REG_OFFSET);
  REG32(AXI_LLC_BASE_ADDRESS + AXI_LLC_CFG_FLUSH_LOW_REG_OFFSET) = ways;
  REG32(AXI_LLC_BASE_ADDRESS + AXI_LLC_COMMIT_CFG_REG_OFFSET) = 1;
  while (REG32(AXI_LLC_BASE_ADDRESS + AXI_LLC_CFG_FLUSH_LOW_REG_OFFSET) != 0) {}
}

int main(void) {
  bool ok = true;
  volatile uint32_t canary = 0xC0FFEE;

  // ------------ PERIPHERALS ------------
  PRINTF("Testing peripherals...\n");

  // Do not touch the UART while its clock is gated: wait for the TX to drain
  while (!(REG32(UART_BASE_ADDRESS + UART_STATUS_REG_OFFSET) & (1u << UART_STATUS_TXIDLE_BIT))) {}
  pm_uart_clock_gate(true);
  for (volatile int i = 0; i < 100; i++) {}
  pm_uart_clock_gate(false);
  ok &= check(true, "uart clock gating");

  // ------------ MEMORY SUBSYSTEM (LLC) ------------
  PRINTF("Testing memory subsystem...\n");

  // The code runs from the LLC: it sleeps together with the core
  pm_llc_clock_gate_with_cpu();
  ok &= check(clock_gated_nap() && canary == 0xC0FFEE, "llc clock gating");

  pm_llc_retention_with_cpu();
  ok &= check(clock_gated_nap() && canary == 0xC0FFEE, "llc retention");

  // Off loses the LLC content: only with the program in DRAM, after a flush
  if ((uintptr_t)&main >= DRAM_START_ADDRESS) {
    llc_flush();
    pm_llc_off_with_cpu();
    ok &= check(clock_gated_nap() && canary == 0xC0FFEE, "llc power gating");
  }

  PRINTF("Power manager example %s\n", ok ? "passed" : "FAILED");
  return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
