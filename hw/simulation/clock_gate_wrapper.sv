// Copyright 2026 Politecnico di Torino
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Behavioral clock gate (simulation). Like the memories, an implementation
// replaces this file with its own technology cell.

module clock_gate_wrapper (
    input  logic clk_i,
    input  logic en_i,       // 1: clock running
    input  logic test_en_i,  // 1: clock running (scan)
    output logic clk_o
);

    logic en_latch;

    always_latch begin
        if (!clk_i) en_latch = en_i | test_en_i;
    end

    assign clk_o = clk_i & en_latch;

endmodule
