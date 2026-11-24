// Copyright 2026 X-HEEP Contributors
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Timer subsystem: OpenTitan rv_timer behind the register interface.
//

module rv_timer_subsystem (
    input logic clk_i,
    input logic rst_ni,

    // Register interface
    input  core_v_mcu_pkg::reg_req_t reg_req_i,
    output core_v_mcu_pkg::reg_rsp_t reg_rsp_o,

    // Timer interrupts, one per hart (MTIP)
    output logic [1:0] timer_irq_o
);

    tlul_pkg::tl_h2d_t tl_h2d;
    tlul_pkg::tl_d2h_t tl_d2h;

    reg_to_tlul #(
        .req_t            (core_v_mcu_pkg::reg_req_t),
        .rsp_t            (core_v_mcu_pkg::reg_rsp_t),
        .tl_h2d_t         (tlul_pkg::tl_h2d_t),
        .tl_d2h_t         (tlul_pkg::tl_d2h_t),
        .tl_a_user_t      (tlul_pkg::tl_a_user_t),
        .tl_a_op_e        (tlul_pkg::tl_a_op_e),
        .TL_A_USER_DEFAULT(tlul_pkg::TL_A_USER_DEFAULT),
        .PutFullData      (tlul_pkg::PutFullData),
        .Get              (tlul_pkg::Get)
    ) u_reg_to_tlul (
        .tl_o     (tl_h2d),
        .tl_i     (tl_d2h),
        .reg_req_i(reg_req_i),
        .reg_rsp_o(reg_rsp_o)
    );

    rv_timer u_rv_timer (
        .clk_i                   (clk_i),
        .rst_ni                  (rst_ni),
        .tl_i                    (tl_h2d),
        .tl_o                    (tl_d2h),
        .intr_timer_expired_0_0_o(timer_irq_o[0]),
        .intr_timer_expired_1_0_o(timer_irq_o[1])
    );

endmodule
