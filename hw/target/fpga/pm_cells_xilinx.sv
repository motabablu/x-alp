// Copyright 2026 Politecnico di Torino
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// FPGA clock gates and power switches: BUFGCE clock gates, no power switch
// (the power manager reset still clears a block switched off).

module clock_gate_wrapper (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);

  xilinx_clk_gating u_clk_gate (
      .clk_i,
      .en_i,
      .test_en_i,
      .clk_o
  );

endmodule

module power_switch_wrapper #(
    parameter int unsigned AckDelay = 8
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic switch_en_ni,
    output logic switch_ack_no,
    output logic pwr_ok_o
);

  assign switch_ack_no = switch_en_ni;
  assign pwr_ok_o      = 1'b1;

endmodule
