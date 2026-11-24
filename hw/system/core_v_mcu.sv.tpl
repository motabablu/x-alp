// Copyright 2026 X-HEEP Contributors
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Top-level module for the Core-V MCU design.
// Author: Luigi Giuffrida <luigi.giuffrida@polito.it>
//
<%

    peripherals = [peripheral.get_name() for peripheral in xalp.get_peripherals()]
    masters = [master.get_name() for master in xalp.bus().get_masters()]
    slaves = [slave.get_name() for slave in xalp.bus().get_slaves()]
    interrupts = xalp.get_interrupts()
    pm = xalp.get_power_manager()
    cpu_name = xalp.cpu().get_name() + "_0"

    def clk(name):
        return pm.clk_of(name) if pm else "clk_i"

    # AXI ports of the blocks: (direction, type, ID width, crossbar side req, rsp).
    # In a power domain they sit behind an axi_isolate, so the block is never
    # stopped in the middle of a handshake.
    axi_ports = {
        cpu_name: [("out", "axi_mst", "AxiMstIdWidth", "axi_master_req_sig[CPU_M_BUS_IDX]", "axi_master_rsp_sig[CPU_M_BUS_IDX]")],
        "axi_llc": [("in", "axi_slv", "AxiSlvIdWidth", "axi_slave_req_sig[LLC_S_BUS_IDX]", "axi_slave_rsp_sig[LLC_S_BUS_IDX]"),
                    ("out", "axi_llc", "AxiLlcIdWidth", "ext_llc_req_o", "ext_llc_rsp_i")],
    }

    def axi(name, k):
        _, _, _, req, rsp = axi_ports[name][k]
        if pm and pm.pd_of(name) is not None:
            return f"{name}_axi{k}_req", f"{name}_axi{k}_rsp"
        return req, rsp

    def pd_rst(name):
        pd = pm.pd_of(name) if pm else None
        return "" if pd is None else f" & pd_pwr_ctrl[{pd}].rst_n & pwr_ok_{name}"
%>
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
    input  power_manager_pkg::power_manager_in_t  [core_v_mcu_pkg::NUM_EXT_PD_RND-1:0] ext_pwr_ack_i

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
    logic         [     PLIC_NINT-1:0] intr_vector;
    logic                               plic_irq;
    logic                               plic_msip;
    logic         [               1:0] timer_irq;

    // Power manager
    logic         [     NUM_CORES-1:0] core_sleep;
    logic                               pm_wakeup_timer_irq;
    logic         [    NUM_CG_RND-1:0] cg_en;

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
    ) u_axi_idle_${cpu_name} (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .req_i (axi_master_req_sig[CPU_M_BUS_IDX]),
        .rsp_i (axi_master_rsp_sig[CPU_M_BUS_IDX]),
        .idle_o(core_idle[0])
    );

% if pm:
<%
    pds = pm.get_power_domains()
    ext_pds = [i for i, pd in enumerate(pds) if not pd.blocks]
    isolated = {}
%>\
  % for b in pm.get_gated_blocks():
<%
    name = b["name"]
    en = []
    if b["cg"] is not None:
        en.append(f"cg_en[{b['cg']}]")
    if b["pd"] is not None:
        en.append(f"pd_pwr_ctrl[{b['pd']}].clkgate_en_n")
%>\
    // ${name}
    logic clk_${name};
    clock_gate_wrapper u_clock_gate_${name} (
        .clk_i    (clk_i),
        .en_i     (${" & ".join(en)}),
        .test_en_i(test_mode_i),
        .clk_o    (clk_${name})
    );
    % if b["pd"] is not None:
    logic pwr_ok_${name}, pwr_ack_${name};
    power_switch_wrapper u_power_switch_${name} (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .switch_en_ni (pd_pwr_ctrl[${b["pd"]}].pwrgate_en_n),
        .switch_ack_no(pwr_ack_${name}),
        .pwr_ok_o     (pwr_ok_${name})
    );
      % for k, (d, t, w, req, rsp) in enumerate(axi_ports.get(name, [])):
<%
    isolated.setdefault(b["pd"], []).append(f"isolated_{name}_{k}")
    blk_req, blk_rsp = axi(name, k)
    slv_req, slv_rsp = (blk_req, blk_rsp) if d == "out" else (req, rsp)
    mst_req, mst_rsp = (req, rsp) if d == "out" else (blk_req, blk_rsp)
%>\
    ${t}_req_t ${blk_req};
    ${t}_rsp_t ${blk_rsp};
    logic isolated_${name}_${k};
    axi_isolate #(
        .NumPending          (16),
        .TerminateTransaction(1'b0),
        .AtopSupport         (1'b1),
        .AxiAddrWidth        (AxiAddrWidth),
        .AxiDataWidth        (AxiDataWidth),
        .AxiIdWidth          (${w}),
        .AxiUserWidth        (AxiUserWidth),
        .axi_req_t           (${t}_req_t),
        .axi_resp_t          (${t}_rsp_t)
    ) u_axi_isolate_${name}_${k} (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .slv_req_i (${slv_req}),
        .slv_resp_o(${slv_rsp}),
        .mst_req_o (${mst_req}),
        .mst_resp_i(${mst_rsp}),
        .isolate_i (pd_isolate[${b["pd"]}]),
        .isolated_o(isolated_${name}_${k})
    );
      % endfor
    % endif

  % endfor
    // Power domain ack (all its switches closed) and bus isolation
  % for i, pd in enumerate(pds):
    % if pd.blocks:
    assign pd_pwr_ack[${i}].pwrgate_ack_n = ${" & ".join("pwr_ack_" + n for n in pd.blocks)};
    assign pd_isolated[${i}] = ${" & ".join(isolated.get(i, [])) or "1'b1"};
    % else:
    assign ext_pwr_ctrl_o[${ext_pds.index(i)}] = pd_pwr_ctrl[${i}];
    assign pd_pwr_ack[${i}] = ext_pwr_ack_i[${ext_pds.index(i)}];
    assign pd_isolated[${i}] = 1'b1;
    % endif
  % endfor
  % if not pds:
    assign pd_pwr_ack = '1;
    assign pd_isolated = '1;
  % endif
  % if not ext_pds:
    assign ext_pwr_ctrl_o = '{default: power_manager_pkg::PD_ON};
  % endif

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
% else:
    assign pd_pwr_ctrl         = '{default: power_manager_pkg::PD_ON};
    assign ext_pwr_ctrl_o      = '{default: power_manager_pkg::PD_ON};
    assign pm_wakeup_timer_irq = 1'b0;
    assign cg_en               = '1;
% endif

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

    assign cpu_rst_n      = rst_ni & ~ndmreset_sync${pd_rst(cpu_name)};

    cpu_subsystem u_cpu_subsystem (
        .clk_i      (${clk(cpu_name)}),
        .rst_ni     (cpu_rst_n),
        .boot_addr_i(BOOT_ADDR),

        // .cvxif_resp_o (),
        // .cvxif_req_i('0),

        .bus_req_o(${axi(cpu_name, 0)[0]}),
        .bus_rsp_i(${axi(cpu_name, 0)[1]}),

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

<%
    llc = xalp.get_cache()
%>\
    axi_llc_reg_wrap #(
        .SetAssociativity(32'd${llc.get_set_assoc()}),
        .NumLines(32'd${llc.get_num_lines()}),
        .NumBlocks(32'd${llc.get_num_blocks()}),
        .AxiIdWidth(AxiSlvIdWidth),
        .AxiAddrWidth(AxiAddrWidth),
        .AxiDataWidth(AxiDataWidth),
        .AxiUserWidth(AxiUserWidth),
        .reg_req_t(reg_req_t),
        .reg_resp_t(reg_rsp_t),
        .slv_req_t(axi_slv_req_t),
        .slv_resp_t(axi_slv_rsp_t),
        .mst_req_t(axi_llc_req_t),
        .mst_resp_t(axi_llc_rsp_t),
        .rule_full_t(rule_t)
    ) u_axi_llc (
        .clk_i(${clk("axi_llc")}),
        .rst_ni(rst_ni${pd_rst("axi_llc")}),
        .test_i('0),
        .slv_req_i(${axi("axi_llc", 0)[0]}),
        .slv_resp_o(${axi("axi_llc", 0)[1]}),
        .mst_req_o(${axi("axi_llc", 1)[0]}),
        .mst_resp_i(${axi("axi_llc", 1)[1]}),
        .conf_req_i(reg_req_sig[AXI_LLC_REG_IDX]),
        .conf_resp_o(reg_rsp_sig[AXI_LLC_REG_IDX]),
        // The LLC re-decodes what the crossbar already routed to it, so these
        // must be the very same windows the decoder uses for this port.
        .cached_start_addr_i(DRAM_BUS_BASE_ADDR),
        .cached_end_addr_i(DRAM_BUS_END_ADDR),
        .spm_start_addr_i(LLC_BUS_BASE_ADDR),
        .axi_llc_events_o()
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

% if "ext_slaves" in slaves:
    assign ext_slv_req_o                          = axi_slave_req_sig[EXT_SLAVES_S_BUS_IDX];
    assign axi_slave_rsp_sig[EXT_SLAVES_S_BUS_IDX] = ext_slv_rsp_i;
% endif

% if "ext_master" in masters:
    assign axi_master_req_sig[EXT_MASTER_M_BUS_IDX] = ext_mst_req_i;
    assign ext_mst_rsp_o                            = axi_master_rsp_sig[EXT_MASTER_M_BUS_IDX];
% endif

% if "ext_peripheral" in peripherals:
    assign ext_reg_req_o                       = reg_req_sig[EXT_PERIPHERAL_REG_IDX];
    assign reg_rsp_sig[EXT_PERIPHERAL_REG_IDX] = ext_reg_rsp_i;
% endif

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

% if "soc_ctrl" in peripherals:
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
% endif

% if "bootrom" in peripherals:
    bootrom_subsystem #(
        .reg_req_t(reg_req_t),
        .reg_rsp_t(reg_rsp_t)
    ) u_bootrom_subsystem (
        .reg_req_i(reg_req_sig[BOOTROM_REG_IDX]),
        .reg_rsp_o(reg_rsp_sig[BOOTROM_REG_IDX])
    );
% endif

% if "uart" in peripherals:
<%
    uart_irqs = ["tx_watermark", "rx_watermark", "tx_empty", "rx_overflow",
                 "rx_frame_err", "rx_break_err", "rx_timeout", "rx_parity_err"]
%>\
% for irq in uart_irqs:
    logic uart_intr_${irq};
% endfor

    uart_subsystem u_uart_subsystem (
        .clk_i                    (${clk("uart")}),
        .rst_ni                   (rst_ni${pd_rst("uart")}),
        .uart_reg_req             (reg_req_sig[UART_REG_IDX]),
        .uart_reg_rsp             (reg_rsp_sig[UART_REG_IDX]),
        .uart_rx_i                (uart_rx_i),
        .uart_tx_o                (uart_tx_o),
% for irq in uart_irqs:
        .uart_intr_${irq}_o${" " * (13 - len(irq))}(uart_intr_${irq})${"" if loop.last else ","}
% endfor
    );
% endif

    always_comb begin
        intr_vector = '0;
        for (int unsigned i = 0; i < NEXT_INT; i++) begin
            intr_vector[PLIC_USED_NINT+i] = ext_intr_i[i];
        end
% if interrupts and interrupts.get_interrupt("power_manager_wakeup_timer") is not None:
        intr_vector[${interrupts.get_interrupt("power_manager_wakeup_timer")}] = pm_wakeup_timer_irq;
% endif
% if interrupts and "uart" in peripherals:
  % for irq in uart_irqs:
    % if interrupts.get_interrupt("uart_intr_" + irq) is not None:
        intr_vector[${interrupts.get_interrupt("uart_intr_" + irq)}] = uart_intr_${irq};
    % endif
  % endfor
% endif
    end

% if "rv_plic" in peripherals:
    rv_plic_subsystem u_rv_plic_subsystem (
        .clk_i       (${clk("rv_plic")}),
        .rst_ni      (rst_ni${pd_rst("rv_plic")}),
        .reg_req_i   (reg_req_sig[RV_PLIC_REG_IDX]),
        .reg_rsp_o   (reg_rsp_sig[RV_PLIC_REG_IDX]),
        .intr_src_i  (intr_vector),
        .irq_o       (plic_irq),
        .msip_o      (plic_msip)
    );
% else:
    assign plic_irq  = 1'b0;
    assign plic_msip = 1'b0;
% endif

% if "rv_timer" in peripherals:
    rv_timer_subsystem u_rv_timer_subsystem (
        .clk_i                 (${clk("rv_timer")}),
        .rst_ni                (rst_ni${pd_rst("rv_timer")}),
        .reg_req_i             (reg_req_sig[RV_TIMER_REG_IDX]),
        .reg_rsp_o             (reg_rsp_sig[RV_TIMER_REG_IDX]),
        .timer_irq_o           (timer_irq)
    );
% else:
    assign timer_irq = '0;
% endif

% if "debug_module" in masters :
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
% endif

endmodule
