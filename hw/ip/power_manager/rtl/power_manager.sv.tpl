// Copyright 2026 Politecnico di Torino
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Power manager, generated from the Power_manager configuration.
// One sequencer per power domain (power gating), one enable per clock gate
// group (clock gating), wake-up timer and per-hart restore registers.
<%
    pm = xalp.get_power_manager()
    pds = pm.get_power_domains() if pm else []
    cgs = pm.get_clock_gates() if pm else []
    num_cores = max(pm.num_cores(), 1) if pm else 1
%>\

module power_manager
  import power_manager_pkg::*;
#(
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic,
    // Do not change: they follow the configuration
    parameter int unsigned NumCores = ${num_cores},
    parameter int unsigned NumPd    = ${max(len(pds), 1)},
    parameter int unsigned NumCg    = ${max(len(cgs), 1)}
) (
    input logic clk_i,
    input logic rst_ni,

    // Bus Interface
    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    // Cores in WFI and debug requests, one bit per hart
    input logic [NumCores-1:0] core_sleep_i,
    input logic [NumCores-1:0] debug_req_i,

    // Wake-up sources (the PLIC sources)
    input logic [63:0] wake_src_i,

    // Wake-up timer expired: an interrupt too, so a clock-gated core leaves WFI
    output logic wakeup_timer_irq_o,

    // Power domains
    output power_manager_out_t [NumPd-1:0] pd_pwr_ctrl_o,
    input  power_manager_in_t  [NumPd-1:0] pd_pwr_ack_i,
    output logic               [NumPd-1:0] pd_isolate_o,   // isolate the bus ports
    input  logic               [NumPd-1:0] pd_isolated_i,  // isolated, nothing in flight

    // Clock gate groups, 1 = clock enabled
    output logic [NumCg-1:0] cg_en_o
);

  import power_manager_reg_pkg::*;

  power_manager_reg2hw_t reg2hw;
  power_manager_hw2reg_t hw2reg;

  power_manager_reg_top #(
      .reg_req_t(reg_req_t),
      .reg_rsp_t(reg_rsp_t)
  ) u_power_manager_reg_top (
      .clk_i,
      .rst_ni,
      .reg_req_i,
      .reg_rsp_o,
      .reg2hw,
      .hw2reg,
      .devmode_i(1'b1)
  );

  // --------------------------------------------------------------------------
  // Wake-up timer
  // --------------------------------------------------------------------------

  logic [31:0] timer_q;
  logic timer_en_q, timer_expired_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      timer_q         <= '0;
      timer_en_q      <= 1'b0;
      timer_expired_q <= 1'b0;
    end else begin
      timer_en_q <= reg2hw.wakeup_timer_en.q;
      if (!reg2hw.wakeup_timer_en.q) begin
        timer_q         <= '0;
        timer_expired_q <= 1'b0;
      end else if (!timer_en_q) begin
        timer_q <= reg2hw.wakeup_timer.q;
      end else if (timer_q != '0) begin
        timer_q <= timer_q - 1;
      end else begin
        timer_expired_q <= 1'b1;
      end
    end
  end

  assign hw2reg.wakeup_timer_status.d = timer_expired_q;
  assign wakeup_timer_irq_o = timer_expired_q;

  // --------------------------------------------------------------------------
  // Power domains
  // --------------------------------------------------------------------------

% if not pds:
  assign pd_pwr_ctrl_o[0] = PD_ON;
  assign pd_isolate_o[0]  = 1'b0;
% endif
% for i, pd in enumerate(pds):
<%
    n = "pd_" + pd.name.lower()
    r = n
%>\
  // ${pd.name}: ${", ".join(pd.blocks) if pd.blocks else "external"} (${", ".join(pd.modes)})
  logic ${n}_ack, ${n}_sleep, ${n}_wake, ${n}_wake_start, ${n}_sleeping, ${n}_awake;
  logic [NumCores-1:0] ${n}_wfi_mask;

  sync #(
      .ResetValue(1'b1)
  ) u_sync_${n}_ack (
      .clk_i,
      .rst_ni,
      .serial_i(pd_pwr_ack_i[${i}].pwrgate_ack_n),
      .serial_o(${n}_ack)
  );

  assign ${n}_wfi_mask = reg2hw.${r}_wfi_mask.q;
  assign ${n}_sleep = reg2hw.${r}_sleep_en.q && &(core_sleep_i | ~${n}_wfi_mask);
  assign ${n}_wake = !reg2hw.${r}_sleep_en.q
      || |(wake_src_i & {reg2hw.${r}_wake_mask_hi.q, reg2hw.${r}_wake_mask_lo.q})
      || (reg2hw.${r}_wake_timer.q && timer_expired_q)
      || |(debug_req_i & ${n}_wfi_mask);

  power_manager_domain #(
      .AllowRetentive(1'b${1 if "retentive" in pd.modes else 0}),
      .AllowOff      (1'b${1 if "off" in pd.modes else 0})
  ) u_${n} (
      .clk_i,
      .rst_ni,
      .sleep_i   (${n}_sleep),
      .wake_i    (${n}_wake),
      .mode_i    (pd_mode_e'(reg2hw.${r}_mode.q)),
      .delay_i   (reg2hw.${r}_delay.q),
      .wait_ack_i(reg2hw.${r}_wait_ack.q),
      .ack_i     (${n}_ack),
      .isolated_i(pd_isolated_i[${i}]),
      .isolate_o (pd_isolate_o[${i}]),
      .pwr_ctrl_o(pd_pwr_ctrl_o[${i}]),
      .sleeping_o(${n}_sleeping),
      .awake_o   (${n}_awake),
      .wake_o    (${n}_wake_start)
  );

  // The wake disarms the domain: SW arms it again for the next sleep
  assign hw2reg.${r}_sleep_en.d     = 1'b0;
  assign hw2reg.${r}_sleep_en.de    = ${n}_wake_start;
  assign hw2reg.${r}_status.sleeping.d = ${n}_sleeping;
  assign hw2reg.${r}_status.ack.d   = ${n}_ack;
  assign hw2reg.${r}_status.awake.d = ${n}_awake;

% endfor
  // --------------------------------------------------------------------------
  // Clock gates
  // --------------------------------------------------------------------------

% if not cgs:
  assign cg_en_o[0] = 1'b1;
% endif
% for i, cg in enumerate(cgs):
  assign cg_en_o[${i}] = !reg2hw.cg_${cg.lower()}.q;
% endfor

endmodule : power_manager
