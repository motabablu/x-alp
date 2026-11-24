// Copyright 2026 X-HEEP Contributors
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Top-level module for the Core-V MCU design.
// Author: Luigi Giuffrida <luigi.giuffrida@polito.it>
//

module core_v_mcu (

    input logic clk_i,
    input logic rst_ni,

    // UART IO
    input  logic uart_rx_i,
    output logic uart_tx_o,

    // Boot select
    input logic boot_select_i,

    // JTAG Interface
    input  logic jtag_tck_i,
    input  logic jtag_tms_i,
    input  logic jtag_trst_ni,
    input  logic jtag_tdi_i,
    output logic jtag_tdo_o,
    output logic jtag_tdo_oe_o,

    // Test mode
    input logic test_mode_i,

    // LLC External Interface
    output core_v_mcu_pkg::axi_llc_req_t ext_llc_req_o,
    input  core_v_mcu_pkg::axi_llc_rsp_t ext_llc_rsp_i,

    // External Peripheral Interface
    output core_v_mcu_pkg::axi_slv_req_t ext_slv_req_o,
    input  core_v_mcu_pkg::axi_slv_rsp_t ext_slv_rsp_i,

    input  core_v_mcu_pkg::axi_mst_req_t ext_mst_req_i,
    output core_v_mcu_pkg::axi_mst_rsp_t ext_mst_rsp_o,

    output core_v_mcu_pkg::reg_req_t ext_reg_req_o,
    input  core_v_mcu_pkg::reg_rsp_t ext_reg_rsp_i,

    // Exit interface
    output logic        exit_valid_o,
    output logic [31:0] exit_value_o,

    // External interrupts (PLIC sources EXT_INTR_*)
    input logic [core_v_mcu_pkg::NEXT_INT_RND-1:0] ext_intr_i,

    // External power domains: power switches, isolation and retention
    output power_manager_pkg::power_manager_out_t [core_v_mcu_pkg::NUM_EXT_PD_RND-1:0] ext_pwr_ctrl_o,
    input power_manager_pkg::power_manager_in_t [core_v_mcu_pkg::NUM_EXT_PD_RND-1:0] ext_pwr_ack_i

);

    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off PINMISSING      */

    import core_v_mcu_pkg::*;

    // Internal signals
    axi_mst_req_t [totalAxiMasters-1:0] axi_master_req_sig;
    axi_mst_rsp_t [totalAxiMasters-1:0] axi_master_rsp_sig;
    axi_slv_req_t [ totalAxiSlaves-1:0] axi_slave_req_sig;
    axi_slv_rsp_t [ totalAxiSlaves-1:0] axi_slave_rsp_sig;

    reg_req_t     [ totalRegSlaves-1:0] reg_req_sig;
    reg_rsp_t     [ totalRegSlaves-1:0] reg_rsp_sig;

    // Interrupts
    logic         [      PLIC_NINT-1:0] intr_vector;
    logic                               plic_irq;
    logic                               plic_msip;
    logic         [                1:0] timer_irq;

    // Power manager
    logic         [      NUM_CORES-1:0] core_sleep;
    logic                               pm_wakeup_timer_irq;
    logic         [     NUM_CG_RND-1:0] cg_en;

    logic                               debug_req;
    logic                               debug_req_sync;
    logic                               ndmreset;
    logic                               ndmreset_sync;
    logic                               cpu_rst_n;

    // Synchronizers for debug signals (2-stage sync)
    logic         [                1:0] debug_req_sync_reg;
    logic         [                1:0] ndmreset_sync_reg;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            debug_req_sync_reg <= '0;
            ndmreset_sync_reg  <= '0;
        end else begin
            debug_req_sync_reg <= {debug_req_sync_reg[0], debug_req};
            ndmreset_sync_reg  <= {ndmreset_sync_reg[0], ndmreset};
        end
    end

    assign debug_req_sync = debug_req_sync_reg[1];
    assign ndmreset_sync  = ndmreset_sync_reg[1];

    power_manager_pkg::power_manager_out_t [NUM_PD_RND-1:0] pd_pwr_ctrl;
    power_manager_pkg::power_manager_in_t  [NUM_PD_RND-1:0] pd_pwr_ack;
    logic                                  [NUM_PD_RND-1:0] pd_isolate;
    logic                                  [NUM_PD_RND-1:0] pd_isolated;

    logic [NUM_CORES-1:0] core_wfi, core_idle;
    assign core_sleep = core_wfi & core_idle;

    axi_idle_monitor #(
        .req_t(axi_mst_req_t),
        .rsp_t(axi_mst_rsp_t)
    ) u_axi_idle_cva6_0 (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .req_i (axi_master_req_sig[CPU_M_BUS_IDX]),
        .rsp_i (axi_master_rsp_sig[CPU_M_BUS_IDX]),
        .idle_o(core_idle[0])
    );

    // cva6_0
    logic clk_cva6_0;
    clock_gate_wrapper u_clock_gate_cva6_0 (
        .clk_i    (clk_i),
        .en_i     (pd_pwr_ctrl[0].clkgate_en_n),
        .test_en_i(test_mode_i),
        .clk_o    (clk_cva6_0)
    );
    logic pwr_ok_cva6_0, pwr_ack_cva6_0;
    power_switch_wrapper u_power_switch_cva6_0 (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .switch_en_ni (pd_pwr_ctrl[0].pwrgate_en_n),
        .switch_ack_no(pwr_ack_cva6_0),
        .pwr_ok_o     (pwr_ok_cva6_0)
    );
    axi_mst_req_t cva6_0_axi0_req;
    axi_mst_rsp_t cva6_0_axi0_rsp;
    logic         isolated_cva6_0_0;
    axi_isolate #(
        .NumPending          (16),
        .TerminateTransaction(1'b0),
        .AtopSupport         (1'b1),
        .AxiAddrWidth        (AxiAddrWidth),
        .AxiDataWidth        (AxiDataWidth),
        .AxiIdWidth          (AxiMstIdWidth),
        .AxiUserWidth        (AxiUserWidth),
        .axi_req_t           (axi_mst_req_t),
        .axi_resp_t          (axi_mst_rsp_t)
    ) u_axi_isolate_cva6_0_0 (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .slv_req_i (cva6_0_axi0_req),
        .slv_resp_o(cva6_0_axi0_rsp),
        .mst_req_o (axi_master_req_sig[CPU_M_BUS_IDX]),
        .mst_resp_i(axi_master_rsp_sig[CPU_M_BUS_IDX]),
        .isolate_i (pd_isolate[0]),
        .isolated_o(isolated_cva6_0_0)
    );

    // axi_llc
    logic clk_axi_llc;
    clock_gate_wrapper u_clock_gate_axi_llc (
        .clk_i    (clk_i),
        .en_i     (pd_pwr_ctrl[1].clkgate_en_n),
        .test_en_i(test_mode_i),
        .clk_o    (clk_axi_llc)
    );
    logic pwr_ok_axi_llc, pwr_ack_axi_llc;
    power_switch_wrapper u_power_switch_axi_llc (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .switch_en_ni (pd_pwr_ctrl[1].pwrgate_en_n),
        .switch_ack_no(pwr_ack_axi_llc),
        .pwr_ok_o     (pwr_ok_axi_llc)
    );
    axi_slv_req_t axi_llc_axi0_req;
    axi_slv_rsp_t axi_llc_axi0_rsp;
    logic         isolated_axi_llc_0;
    axi_isolate #(
        .NumPending          (16),
        .TerminateTransaction(1'b0),
        .AtopSupport         (1'b1),
        .AxiAddrWidth        (AxiAddrWidth),
        .AxiDataWidth        (AxiDataWidth),
        .AxiIdWidth          (AxiSlvIdWidth),
        .AxiUserWidth        (AxiUserWidth),
        .axi_req_t           (axi_slv_req_t),
        .axi_resp_t          (axi_slv_rsp_t)
    ) u_axi_isolate_axi_llc_0 (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .slv_req_i (axi_slave_req_sig[LLC_S_BUS_IDX]),
        .slv_resp_o(axi_slave_rsp_sig[LLC_S_BUS_IDX]),
        .mst_req_o (axi_llc_axi0_req),
        .mst_resp_i(axi_llc_axi0_rsp),
        .isolate_i (pd_isolate[1]),
        .isolated_o(isolated_axi_llc_0)
    );
    axi_llc_req_t axi_llc_axi1_req;
    axi_llc_rsp_t axi_llc_axi1_rsp;
    logic         isolated_axi_llc_1;
    axi_isolate #(
        .NumPending          (16),
        .TerminateTransaction(1'b0),
        .AtopSupport         (1'b1),
        .AxiAddrWidth        (AxiAddrWidth),
        .AxiDataWidth        (AxiDataWidth),
        .AxiIdWidth          (AxiLlcIdWidth),
        .AxiUserWidth        (AxiUserWidth),
        .axi_req_t           (axi_llc_req_t),
        .axi_resp_t          (axi_llc_rsp_t)
    ) u_axi_isolate_axi_llc_1 (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .slv_req_i (axi_llc_axi1_req),
        .slv_resp_o(axi_llc_axi1_rsp),
        .mst_req_o (ext_llc_req_o),
        .mst_resp_i(ext_llc_rsp_i),
        .isolate_i (pd_isolate[1]),
        .isolated_o(isolated_axi_llc_1)
    );

    // uart
    logic clk_uart;
    clock_gate_wrapper u_clock_gate_uart (
        .clk_i    (clk_i),
        .en_i     (cg_en[0]),
        .test_en_i(test_mode_i),
        .clk_o    (clk_uart)
    );

    // Power domain ack (all its switches closed) and bus isolation
    assign pd_pwr_ack[0].pwrgate_ack_n = pwr_ack_cva6_0;
    assign pd_isolated[0]              = isolated_cva6_0_0;
    assign pd_pwr_ack[1].pwrgate_ack_n = pwr_ack_axi_llc;
    assign pd_isolated[1]              = isolated_axi_llc_0 & isolated_axi_llc_1;
    assign ext_pwr_ctrl_o[0]           = pd_pwr_ctrl[2];
    assign pd_pwr_ack[2]               = ext_pwr_ack_i[0];
    assign pd_isolated[2]              = 1'b1;

    power_manager #(
        .reg_req_t(reg_req_t),
        .reg_rsp_t(reg_rsp_t)
    ) u_power_manager (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .reg_req_i         (reg_req_sig[POWER_MANAGER_REG_IDX]),
        .reg_rsp_o         (reg_rsp_sig[POWER_MANAGER_REG_IDX]),
        .core_sleep_i      (core_sleep),
        .debug_req_i       (debug_req_sync),
        .wake_src_i        (intr_vector),
        .wakeup_timer_irq_o(pm_wakeup_timer_irq),
        .pd_pwr_ctrl_o     (pd_pwr_ctrl),
        .pd_pwr_ack_i      (pd_pwr_ack),
        .pd_isolate_o      (pd_isolate),
        .pd_isolated_i     (pd_isolated),
        .cg_en_o           (cg_en)
    );

    //
    //       █████████  ███████████  █████  █████
    //      ███░░░░░███░░███░░░░░███░░███  ░░███
    //     ███     ░░░  ░███    ░███ ░███   ░███
    //    ░███          ░██████████  ░███   ░███
    //    ░███          ░███░░░░░░   ░███   ░███
    //    ░░███     ███ ░███         ░███   ░███
    //     ░░█████████  █████        ░░████████
    //      ░░░░░░░░░  ░░░░░          ░░░░░░░░
    //

    assign cpu_rst_n = rst_ni & ~ndmreset_sync & pd_pwr_ctrl[0].rst_n & pwr_ok_cva6_0;

    cpu_subsystem u_cpu_subsystem (
        .clk_i      (clk_cva6_0),
        .rst_ni     (cpu_rst_n),
        .boot_addr_i(BOOT_ADDR),

        // .cvxif_resp_o (),
        // .cvxif_req_i('0),

        .bus_req_o(cva6_0_axi0_req),
        .bus_rsp_i(cva6_0_axi0_rsp),

        .irq_i       ({1'b0, plic_irq}),  // {SEIP, MEIP}
        .ipi_i       (plic_msip),
        .time_irq_i  (timer_irq[0]),
        .debug_req_i (debug_req_sync),
        .core_sleep_o(core_wfi[0])
    );

    //
    //  ██████   ██████
    // ░░██████ ██████
    //  ░███░█████░███   ██████  █████████████    ██████  ████████  █████ ████
    //  ░███░░███ ░███  ███░░███░░███░░███░░███  ███░░███░░███░░███░░███ ░███
    //  ░███ ░░░  ░███ ░███████  ░███ ░███ ░███ ░███ ░███ ░███ ░░░  ░███ ░███
    //  ░███      ░███ ░███░░░   ░███ ░███ ░███ ░███ ░███ ░███      ░███ ░███
    //  █████     █████░░██████  █████░███ █████░░██████  █████     ░░███████
    // ░░░░░     ░░░░░  ░░░░░░  ░░░░░ ░░░ ░░░░░  ░░░░░░  ░░░░░       ░░░░░███
    //                                                               ███ ░███
    //                                                              ░░██████
    //                                                               ░░░░░░
    //

    axi_llc_reg_wrap #(
        .SetAssociativity(32'd16),
        .NumLines        (32'd256),
        .NumBlocks       (32'd8),
        .AxiIdWidth      (AxiSlvIdWidth),
        .AxiAddrWidth    (AxiAddrWidth),
        .AxiDataWidth    (AxiDataWidth),
        .AxiUserWidth    (AxiUserWidth),
        .reg_req_t       (reg_req_t),
        .reg_resp_t      (reg_rsp_t),
        .slv_req_t       (axi_slv_req_t),
        .slv_resp_t      (axi_slv_rsp_t),
        .mst_req_t       (axi_llc_req_t),
        .mst_resp_t      (axi_llc_rsp_t),
        .rule_full_t     (rule_t)
    ) u_axi_llc (
        .clk_i              (clk_axi_llc),
        .rst_ni             (rst_ni & pd_pwr_ctrl[1].rst_n & pwr_ok_axi_llc),
        .test_i             ('0),
        .slv_req_i          (axi_llc_axi0_req),
        .slv_resp_o         (axi_llc_axi0_rsp),
        .mst_req_o          (axi_llc_axi1_req),
        .mst_resp_i         (axi_llc_axi1_rsp),
        .conf_req_i         (reg_req_sig[AXI_LLC_REG_IDX]),
        .conf_resp_o        (reg_rsp_sig[AXI_LLC_REG_IDX]),
        // The LLC re-decodes what the crossbar already routed to it, so these
        // must be the very same windows the decoder uses for this port.
        .cached_start_addr_i(DRAM_BUS_BASE_ADDR),
        .cached_end_addr_i  (DRAM_BUS_END_ADDR),
        .spm_start_addr_i   (LLC_BUS_BASE_ADDR),
        .axi_llc_events_o   ()
    );

    //
    //  ███████████  █████  █████  █████████
    // ░░███░░░░░███░░███  ░░███  ███░░░░░███
    //  ░███    ░███ ░███   ░███ ░███    ░░░
    //  ░██████████  ░███   ░███ ░░█████████
    //  ░███░░░░░███ ░███   ░███  ░░░░░░░░███
    //  ░███    ░███ ░███   ░███  ███    ░███
    //  ███████████  ░░████████  ░░█████████
    // ░░░░░░░░░░░    ░░░░░░░░    ░░░░░░░░░
    //

    bus_subsystem u_bus_subsystem (
        .clk_i (clk_i),
        .rst_ni(rst_ni),

        // AXI master
        .axi_master_req_i(axi_master_req_sig),
        .axi_master_rsp_o(axi_master_rsp_sig),

        // AXI slave
        .axi_slave_req_o(axi_slave_req_sig),
        .axi_slave_rsp_i(axi_slave_rsp_sig),

        // Peripheral register interface
        .reg_req_o(reg_req_sig),
        .reg_rsp_i(reg_rsp_sig)
    );

    assign ext_slv_req_o                            = axi_slave_req_sig[EXT_SLAVES_S_BUS_IDX];
    assign axi_slave_rsp_sig[EXT_SLAVES_S_BUS_IDX]  = ext_slv_rsp_i;

    assign axi_master_req_sig[EXT_MASTER_M_BUS_IDX] = ext_mst_req_i;
    assign ext_mst_rsp_o                            = axi_master_rsp_sig[EXT_MASTER_M_BUS_IDX];

    assign ext_reg_req_o                            = reg_req_sig[EXT_PERIPHERAL_REG_IDX];
    assign reg_rsp_sig[EXT_PERIPHERAL_REG_IDX]      = ext_reg_rsp_i;

    //
    //  ███████████                      ███            █████                                   ████
    // ░░███░░░░░███                    ░░░            ░░███                                   ░░███
    //  ░███    ░███  ██████  ████████  ████  ████████  ░███████    ██████  ████████   ██████   ░███   █████
    //  ░██████████  ███░░███░░███░░███░░███ ░░███░░███ ░███░░███  ███░░███░░███░░███ ░░░░░███  ░███  ███░░
    //  ░███░░░░░░  ░███████  ░███ ░░░  ░███  ░███ ░███ ░███ ░███ ░███████  ░███ ░░░   ███████  ░███ ░░█████
    //  ░███        ░███░░░   ░███      ░███  ░███ ░███ ░███ ░███ ░███░░░   ░███      ███░░███  ░███  ░░░░███
    //  █████       ░░██████  █████     █████ ░███████  ████ █████░░██████  █████    ░░████████ █████ ██████
    // ░░░░░         ░░░░░░  ░░░░░     ░░░░░  ░███░░░  ░░░░ ░░░░░  ░░░░░░  ░░░░░      ░░░░░░░░ ░░░░░ ░░░░░░
    //                                        ░███
    //                                        █████
    //                                       ░░░░░
    //

    soc_ctrl #(
        .reg_req_t(reg_req_t),
        .reg_rsp_t(reg_rsp_t)
    ) u_soc_ctrl (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .reg_req_i    (reg_req_sig[SOC_CTRL_REG_IDX]),
        .reg_rsp_o    (reg_rsp_sig[SOC_CTRL_REG_IDX]),
        .boot_select_i(boot_select_i),
        .exit_valid_o (exit_valid_o),
        .exit_value_o (exit_value_o)
    );

    bootrom_subsystem #(
        .reg_req_t(reg_req_t),
        .reg_rsp_t(reg_rsp_t)
    ) u_bootrom_subsystem (
        .reg_req_i(reg_req_sig[BOOTROM_REG_IDX]),
        .reg_rsp_o(reg_rsp_sig[BOOTROM_REG_IDX])
    );

    logic uart_intr_tx_watermark;
    logic uart_intr_rx_watermark;
    logic uart_intr_tx_empty;
    logic uart_intr_rx_overflow;
    logic uart_intr_rx_frame_err;
    logic uart_intr_rx_break_err;
    logic uart_intr_rx_timeout;
    logic uart_intr_rx_parity_err;

    uart_subsystem u_uart_subsystem (
        .clk_i                    (clk_uart),
        .rst_ni                   (rst_ni),
        .uart_reg_req             (reg_req_sig[UART_REG_IDX]),
        .uart_reg_rsp             (reg_rsp_sig[UART_REG_IDX]),
        .uart_rx_i                (uart_rx_i),
        .uart_tx_o                (uart_tx_o),
        .uart_intr_tx_watermark_o (uart_intr_tx_watermark),
        .uart_intr_rx_watermark_o (uart_intr_rx_watermark),
        .uart_intr_tx_empty_o     (uart_intr_tx_empty),
        .uart_intr_rx_overflow_o  (uart_intr_rx_overflow),
        .uart_intr_rx_frame_err_o (uart_intr_rx_frame_err),
        .uart_intr_rx_break_err_o (uart_intr_rx_break_err),
        .uart_intr_rx_timeout_o   (uart_intr_rx_timeout),
        .uart_intr_rx_parity_err_o(uart_intr_rx_parity_err)
    );

    always_comb begin
        intr_vector = '0;
        for (int unsigned i = 0; i < NEXT_INT; i++) begin
            intr_vector[PLIC_USED_NINT+i] = ext_intr_i[i];
        end
        intr_vector[9] = pm_wakeup_timer_irq;
        intr_vector[1] = uart_intr_tx_watermark;
        intr_vector[2] = uart_intr_rx_watermark;
        intr_vector[3] = uart_intr_tx_empty;
        intr_vector[4] = uart_intr_rx_overflow;
        intr_vector[5] = uart_intr_rx_frame_err;
        intr_vector[6] = uart_intr_rx_break_err;
        intr_vector[7] = uart_intr_rx_timeout;
        intr_vector[8] = uart_intr_rx_parity_err;
    end

    rv_plic_subsystem u_rv_plic_subsystem (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .reg_req_i (reg_req_sig[RV_PLIC_REG_IDX]),
        .reg_rsp_o (reg_rsp_sig[RV_PLIC_REG_IDX]),
        .intr_src_i(intr_vector),
        .irq_o     (plic_irq),
        .msip_o    (plic_msip)
    );

    rv_timer_subsystem u_rv_timer_subsystem (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .reg_req_i  (reg_req_sig[RV_TIMER_REG_IDX]),
        .reg_rsp_o  (reg_rsp_sig[RV_TIMER_REG_IDX]),
        .timer_irq_o(timer_irq)
    );

    debug_subsystem u_debug_subsystem (
        .clk_i (clk_i),
        .rst_ni(rst_ni),

        // AXI Slave Interface
        .axi_slv_req_i(axi_slave_req_sig[DEBUG_S_BUS_IDX]),
        .axi_slv_rsp_o(axi_slave_rsp_sig[DEBUG_S_BUS_IDX]),

        // AXI Master Interface
        .axi_mst_req_o(axi_master_req_sig[DEBUG_MODULE_M_BUS_IDX]),
        .axi_mst_rsp_i(axi_master_rsp_sig[DEBUG_MODULE_M_BUS_IDX]),
        // JTAG Interface
        .jtag_tck_i   (jtag_tck_i),
        .jtag_tms_i   (jtag_tms_i),
        .jtag_trst_ni (jtag_trst_ni),
        .jtag_tdi_i   (jtag_tdi_i),
        .jtag_tdo_o   (jtag_tdo_o),
        .jtag_tdo_oe_o(jtag_tdo_oe_o),
        // Test mode
        .test_mode_i  (test_mode_i),
        // Debug signals
        .dbg_active_o (),
        .dbg_req_o    (debug_req),
        .ndmreset_o   (ndmreset)
    );

endmodule
