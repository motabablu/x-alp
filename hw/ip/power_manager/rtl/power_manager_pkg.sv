// Copyright 2024 EPFL
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

package power_manager_pkg;

  typedef struct packed {logic pwrgate_ack_n;} power_manager_in_t;

  typedef struct packed {
    logic clkgate_en_n;
    logic pwrgate_en_n;
    logic isogate_en_n;
    logic retentive_en_n;
    logic rst_n;
  } power_manager_out_t;

  // Sleep modes, encoding of the PD_<name>_MODE registers
  typedef enum logic [1:0] {
    MODE_CLOCK_GATE = 2'd0,
    MODE_RETENTIVE  = 2'd1,
    MODE_OFF        = 2'd2
  } pd_mode_e;

  // Value driven while a domain is fully on
  localparam power_manager_out_t PD_ON = '{
      clkgate_en_n: 1'b1,
      pwrgate_en_n: 1'b1,
      isogate_en_n: 1'b1,
      retentive_en_n: 1'b1,
      rst_n: 1'b1
  };

endpackage
