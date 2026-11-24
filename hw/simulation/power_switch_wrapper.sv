// Copyright 2026 Politecnico di Torino
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Behavioral power switch of one block (simulation). Like the memories, an
// implementation replaces this file with its own switch cells.
//
// The supply drops as soon as the switch opens and is back AckDelay cycles
// after it closes, together with the ack. While unpowered the block is held
// in reset (pwr_ok_o = 0), so its state is lost.

module power_switch_wrapper #(
    parameter int unsigned AckDelay = 8  // >= 2
) (
    input  logic clk_i,          // always-on clock, for the behavioral delay
    input  logic rst_ni,
    input  logic switch_en_ni,   // 1: powered (power_manager_out_t.pwrgate_en_n)
    output logic switch_ack_no,  // 1: powered (power_manager_in_t.pwrgate_ack_n)
    output logic pwr_ok_o        // 0: hold the block in reset
);

    logic [AckDelay-1:0] switch_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) switch_q <= '1;
        else switch_q <= {switch_q[AckDelay-2:0], switch_en_ni};
    end

    assign switch_ack_no = switch_q[AckDelay-1];
    assign pwr_ok_o      = switch_en_ni & switch_ack_no;

endmodule
