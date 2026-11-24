// Copyright 2026 X-HEEP Contributors
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// PLIC subsystem: OpenTitan rv_plic behind the register interface.
//

module rv_plic_subsystem (
    input logic clk_i,
    input logic rst_ni,

    // Register interface
    input  core_v_mcu_pkg::reg_req_t reg_req_i,
    output core_v_mcu_pkg::reg_rsp_t reg_rsp_o,

    // Interrupt sources and notification to hart 0 (MEIP) and its software interrupt (MSIP)
    input  logic [rv_plic_reg_pkg::NumSrc-1:0] intr_src_i,
    output logic                               irq_o,
    output logic                               msip_o
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

    rv_plic u_rv_plic (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .tl_i      (tl_h2d),
        .tl_o      (tl_d2h),
        .intr_src_i(intr_src_i),
        .irq_o     (irq_o),
        .irq_id_o  (),
        .msip_o    (msip_o)
    );

endmodule
