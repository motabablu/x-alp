// Copyright 2026 Politecnico di Torino
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// CPU SDK example: the core sleeps for N cycles with cpu_sleep_cycles(),
// first clock gated, then switched off and restored through the boot ROM.
// Needs the default configs/soc.py: power domain cpu and the power manager
// wake-up timer on the PLIC.
//
// Modes the cpu power domain does not support do not compile, e.g.
//   cpu_sleep_cycles(kPmModeRetentive, 100);  // cpu: clock_gate, off

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "cpu_sdk.h"
#include "printf.h"
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

static bool check(bool ok, const char *what) {
  PRINTF("%s: %s\n", what, ok ? "OK" : "FAIL");
  return ok;
}

// Clock-gated sleep: the cycle counter of the core stops with its clock
static bool clock_gated_nap(void) {
  uint64_t start = cpu_cycles();
  cpu_sleep_cycles(kPmModeClockGate, SLEEP_CYCLES);
  return cpu_cycles() - start < SLEEP_CYCLES;
}

int main(void) {
  bool ok = true;
  volatile uint32_t canary = 0xC0FFEE;

  ok &= check(clock_gated_nap(), "cpu clock gating");
  ok &= check(cpu_sleep_cycles(kPmModeOff, SLEEP_CYCLES) == 1 && canary == 0xC0FFEE, "cpu power gating and restore");

  PRINTF("CPU SDK example %s\n", ok ? "passed" : "FAILED");
  return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
