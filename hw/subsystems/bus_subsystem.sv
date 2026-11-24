// Copyright 2026 X-HEEP Contributors
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Bus Subsystem module.
// Author: Flavia Guella <flavia.guella@polito.it>
//


module bus_subsystem (
    input logic clk_i,
    input logic rst_ni,

    // AXI master
    input  core_v_mcu_pkg::axi_mst_req_t [core_v_mcu_pkg::totalAxiMasters-1:0] axi_master_req_i,
    output core_v_mcu_pkg::axi_mst_rsp_t [core_v_mcu_pkg::totalAxiMasters-1:0] axi_master_rsp_o,

    // AXI slave
    output core_v_mcu_pkg::axi_slv_req_t [core_v_mcu_pkg::totalAxiSlaves-1:0] axi_slave_req_o,
    input  core_v_mcu_pkg::axi_slv_rsp_t [core_v_mcu_pkg::totalAxiSlaves-1:0] axi_slave_rsp_i,

    // Peripheral register interface
    output core_v_mcu_pkg::reg_req_t [core_v_mcu_pkg::totalRegSlaves-1:0] reg_req_o,
    input  core_v_mcu_pkg::reg_rsp_t [core_v_mcu_pkg::totalRegSlaves-1:0] reg_rsp_i

);

    localparam int unsigned regSelectWidth = $clog2(core_v_mcu_pkg::totalRegSlaves);

    // Internal signals
    // ----------------
    core_v_mcu_pkg::axi_slv_req_t [core_v_mcu_pkg::totalAxiSlaves-1:0] axi_slave_req;
    core_v_mcu_pkg::axi_slv_rsp_t [core_v_mcu_pkg::totalAxiSlaves-1:0] axi_slave_rsp;
    // AMO <--> DW converter
    core_v_mcu_pkg::axi_slv_req_t                                      axi_reg_amo_req;
    core_v_mcu_pkg::axi_slv_rsp_t                                      axi_reg_amo_rsp;
    // DW converter <--> AXI to REG
    core_v_mcu_pkg::axi_reg_req_t                                      axi_reg_req;
    core_v_mcu_pkg::axi_reg_rsp_t                                      axi_reg_rsp;
    core_v_mcu_pkg::reg_req_t                                          reg_in_req;
    core_v_mcu_pkg::reg_rsp_t                                          reg_in_rsp;
    // Reg demux
    logic                         [                regSelectWidth-1:0] reg_select;

    // AXI XBAR
    //---------
    axi_xbar #(
        .Cfg          (core_v_mcu_pkg::AxiXbarCfg),
        .ATOPs        (1),
        .Connectivity ('1),
        .slv_aw_chan_t(core_v_mcu_pkg::axi_mst_aw_chan_t),
        .mst_aw_chan_t(core_v_mcu_pkg::axi_slv_aw_chan_t),
        .w_chan_t     (core_v_mcu_pkg::axi_mst_w_chan_t),
        .slv_b_chan_t (core_v_mcu_pkg::axi_mst_b_chan_t),
        .mst_b_chan_t (core_v_mcu_pkg::axi_slv_b_chan_t),
        .slv_ar_chan_t(core_v_mcu_pkg::axi_mst_ar_chan_t),
        .mst_ar_chan_t(core_v_mcu_pkg::axi_slv_ar_chan_t),
        .slv_r_chan_t (core_v_mcu_pkg::axi_mst_r_chan_t),
        .mst_r_chan_t (core_v_mcu_pkg::axi_slv_r_chan_t),
        .slv_req_t    (core_v_mcu_pkg::axi_mst_req_t),
        .slv_resp_t   (core_v_mcu_pkg::axi_mst_rsp_t),
        .mst_req_t    (core_v_mcu_pkg::axi_slv_req_t),
        .mst_resp_t   (core_v_mcu_pkg::axi_slv_rsp_t),
        .rule_t       (core_v_mcu_pkg::rule_t)
    ) u_axi_xbar (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        .test_i               (1'b0),
        .slv_ports_req_i      (axi_master_req_i),
        .slv_ports_resp_o     (axi_master_rsp_o),
        .mst_ports_req_o      (axi_slave_req),
        .mst_ports_resp_i     (axi_slave_rsp),
        .addr_map_i           (core_v_mcu_pkg::addr_rules),
        .en_default_mst_port_i('0),
        .default_mst_port_i   ('0)
    );

    //-------------------
    // Reg Peripheral Bus
    //-------------------

    // Atomics
    //--------
    axi_riscv_atomics_structs #(
        .AxiAddrWidth   (core_v_mcu_pkg::AxiAddrWidth),
        .AxiDataWidth   (core_v_mcu_pkg::AxiDataWidth),
        .AxiIdWidth     (core_v_mcu_pkg::AxiSlvIdWidth),
        .AxiUserWidth   (core_v_mcu_pkg::AxiUserWidth),
        .AxiMaxReadTxns (1),
        .AxiMaxWriteTxns(1),
        .AxiUserAsId    (0),
        .AxiUserIdMsb   (0),
        .AxiUserIdLsb   (0),
        .RiscvWordWidth (64),
        .NAxiCuts       (1),
        .axi_req_t      (core_v_mcu_pkg::axi_slv_req_t),
        .axi_rsp_t      (core_v_mcu_pkg::axi_slv_rsp_t)
    ) i_reg_atomics (
        .clk_i,
        .rst_ni,
        .axi_slv_req_i(axi_slave_req[core_v_mcu_pkg::PERIPHERAL_DOMAIN_S_BUS_IDX]),
        .axi_slv_rsp_o(axi_slave_rsp[core_v_mcu_pkg::PERIPHERAL_DOMAIN_S_BUS_IDX]),
        .axi_mst_req_o(axi_reg_amo_req),
        .axi_mst_rsp_i(axi_reg_amo_rsp)
    );

    axi_dw_converter #(
        .AxiMaxReads        (1),
        .AxiSlvPortDataWidth(core_v_mcu_pkg::AxiDataWidth),
        .AxiMstPortDataWidth(32),
        .AxiAddrWidth       (core_v_mcu_pkg::AxiAddrWidth),
        .AxiIdWidth         (core_v_mcu_pkg::AxiSlvIdWidth),
        .aw_chan_t          (core_v_mcu_pkg::axi_slv_aw_chan_t),
        .mst_w_chan_t       (core_v_mcu_pkg::axi_reg_w_chan_t),
        .slv_w_chan_t       (core_v_mcu_pkg::axi_slv_w_chan_t),
        .b_chan_t           (core_v_mcu_pkg::axi_slv_b_chan_t),
        .ar_chan_t          (core_v_mcu_pkg::axi_slv_ar_chan_t),
        .mst_r_chan_t       (core_v_mcu_pkg::axi_reg_r_chan_t),
        .slv_r_chan_t       (core_v_mcu_pkg::axi_slv_r_chan_t),
        .axi_mst_req_t      (core_v_mcu_pkg::axi_reg_req_t),
        .axi_mst_resp_t     (core_v_mcu_pkg::axi_reg_rsp_t),
        .axi_slv_req_t      (core_v_mcu_pkg::axi_slv_req_t),
        .axi_slv_resp_t     (core_v_mcu_pkg::axi_slv_rsp_t)
    ) u_axi_dw_converter (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .slv_req_i (axi_reg_amo_req),
        .slv_resp_o(axi_reg_amo_rsp),
        .mst_req_o (axi_reg_req),
        .mst_resp_i(axi_reg_rsp)
    );

    // Convert from AXI to reg protocol
    axi_to_reg_v2 #(
        .AxiAddrWidth(core_v_mcu_pkg::AxiAddrWidth),
        .AxiDataWidth(32),
        .AxiIdWidth  (core_v_mcu_pkg::AxiSlvIdWidth),
        .AxiUserWidth(core_v_mcu_pkg::AxiUserWidth),
        .RegDataWidth(32),
        .CutMemReqs  (0),
        .axi_req_t   (core_v_mcu_pkg::axi_reg_req_t),
        .axi_rsp_t   (core_v_mcu_pkg::axi_reg_rsp_t),
        .reg_req_t   (core_v_mcu_pkg::reg_req_t),
        .reg_rsp_t   (core_v_mcu_pkg::reg_rsp_t)
    ) u_axi_to_reg_v2 (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .axi_req_i(axi_reg_req),
        .axi_rsp_o(axi_reg_rsp),
        .reg_req_o(reg_in_req),
        .reg_rsp_i(reg_in_rsp),
        .reg_id_o (),
        .busy_o   ()
    );

    addr_decode #(
        .NoIndices(core_v_mcu_pkg::totalRegSlaves),
        .NoRules  (core_v_mcu_pkg::totalRegSlaves),
        .addr_t   (core_v_mcu_pkg::addr_t),
        .rule_t   (core_v_mcu_pkg::rule_t)
    ) u_reg_demux_decode (
        .addr_i          (reg_in_req.addr),
        .addr_map_i      (core_v_mcu_pkg::RegMap),
        .idx_o           (reg_select),
        .dec_valid_o     (),
        .dec_error_o     (),
        .en_default_idx_i(1'b1),
        .default_idx_i   ('0)
    );

    reg_demux #(
        .NoPorts(core_v_mcu_pkg::totalRegSlaves),
        .req_t  (core_v_mcu_pkg::reg_req_t),
        .rsp_t  (core_v_mcu_pkg::reg_rsp_t)
    ) u_reg_demux (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .in_select_i(reg_select),
        .in_req_i   (reg_in_req),
        .in_rsp_o   (reg_in_rsp),
        .out_req_o  (reg_req_o),
        .out_rsp_i  (reg_rsp_i)
    );

    assign axi_slave_req_o = axi_slave_req;
    for (genvar i = 0; i < core_v_mcu_pkg::totalAxiSlaves; i++) begin : gen_axislave_rsp_assign
        if (i != core_v_mcu_pkg::PERIPHERAL_DOMAIN_S_BUS_IDX) begin : gen_axislave_rsp_assign_nonperiph
            assign axi_slave_rsp[i] = axi_slave_rsp_i[i];
        end
    end

endmodule
