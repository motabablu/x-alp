// Copyright 2026 Politecnico di Torino
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Checks that an AXI interface is idle, i.e. no transactions are in flight and no new transactions are being requested.

module axi_idle_monitor #(
    parameter type         req_t    = logic,
    parameter type         rsp_t    = logic,
    parameter int unsigned CntWidth = 8
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  req_t req_i,
    input  rsp_t rsp_i,
    output logic idle_o
);

    logic [CntWidth-1:0] wr_q, rd_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_q <= '0;
            rd_q <= '0;
        end else begin
            wr_q <= wr_q + CntWidth'(req_i.aw_valid && rsp_i.aw_ready)
                   - CntWidth'(rsp_i.b_valid && req_i.b_ready);
            rd_q <= rd_q + CntWidth'(req_i.ar_valid && rsp_i.ar_ready)
                   - CntWidth'(rsp_i.r_valid && req_i.r_ready && rsp_i.r.last);
        end
    end

    assign idle_o = wr_q == '0 && rd_q == '0 && !req_i.aw_valid && !req_i.ar_valid && !req_i.w_valid;

endmodule
