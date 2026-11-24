// Copyright 2026 Politecnico di Torino
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Sleep/wake sequencer of one power domain.
//
// Going to sleep it first isolates the bus ports of the domain (`isolate_o`)
// and waits for them to drain (`isolated_i`) and `delay_i` more cycles with
// `sleep_i` steady, then walks down the steps of the selected mode, one every
// `delay_i` cycles, and back up in reverse on wake, lifting the isolation last:
//   clock_gate: clock gate
//   retentive : clock gate -> isolation -> retention
//   off       : clock gate -> isolation -> reset -> power switch off
// Waking from `off`, after switching on it waits for the switch ack
// (`ack_i`, 1 = powered) when `wait_ack_i` is set, then runs the clock for
// `delay_i` cycles with the reset still asserted, so that the block leaves
// reset clean (synchronous resets, assertions).

module power_manager_domain
  import power_manager_pkg::*;
#(
    parameter bit AllowRetentive = 1'b1,
    parameter bit AllowOff       = 1'b1
) (
    input logic clk_i,
    input logic rst_ni,

    input logic        sleep_i,     // sleep requested
    input logic        isolated_i,  // bus ports isolated, nothing in flight
    input logic        wake_i,      // start the wake sequence (when asleep)
    input pd_mode_e    mode_i,
    input logic [15:0] delay_i,
    input logic        wait_ack_i,
    input logic        ack_i,

    output power_manager_out_t pwr_ctrl_o,
    output logic               isolate_o,   // isolate the bus ports
    output logic               sleeping_o,  // fully asleep
    output logic               awake_o,     // fully on
    output logic               wake_o       // pulse when the wake sequence starts
);

  typedef enum logic [1:0] {
    ON,
    DOWN,
    ASLEEP,
    UP
  } state_e;

  state_e state_q, state_d;
  pd_mode_e mode_q, mode_d;
  logic [2:0] lvl_q, lvl_d, lvl_max;
  logic [15:0] cnt_q, cnt_d;
  logic ack_wait, clk_in_reset;

  // A mode the domain does not support falls back to clock gating
  pd_mode_e mode_sel;
  always_comb begin
    mode_sel = MODE_CLOCK_GATE;
    if (mode_i == MODE_RETENTIVE && AllowRetentive) mode_sel = MODE_RETENTIVE;
    if (mode_i == MODE_OFF && AllowOff) mode_sel = MODE_OFF;
  end

  always_comb begin
    unique case (mode_q)
      MODE_RETENTIVE: lvl_max = 3'd3;
      MODE_OFF:       lvl_max = 3'd4;
      default:        lvl_max = 3'd1;
    endcase
  end

  // Leaving the switched-off step: wait for the power switch
  assign ack_wait = mode_q == MODE_OFF && lvl_q == 3'd3 && wait_ack_i && !ack_i;

  always_comb begin
    state_d = state_q;
    mode_d  = mode_q;
    lvl_d   = lvl_q;
    cnt_d   = cnt_q;
    wake_o  = 1'b0;

    unique case (state_q)
      ON: begin
        if (sleep_i) begin
          mode_d  = mode_sel;
          cnt_d   = delay_i;
          state_d = DOWN;
        end
      end
      DOWN: begin
        // Before the first step the request must hold: abort if it drops
        if (lvl_q == '0 && !sleep_i) state_d = ON;
        else if (lvl_q == '0 && !isolated_i) cnt_d = delay_i;  // let the bus drain
        else if (cnt_q != '0) cnt_d = cnt_q - 1;
        else if (lvl_q == lvl_max) state_d = ASLEEP;
        else begin
          lvl_d = lvl_q + 1;
          cnt_d = delay_i;
        end
      end
      ASLEEP: begin
        if (wake_i) begin
          wake_o  = 1'b1;
          lvl_d   = lvl_q - 1;
          cnt_d   = delay_i;
          state_d = UP;
        end
      end
      UP: begin
        if (cnt_q != '0) cnt_d = cnt_q - 1;
        else if (ack_wait) cnt_d = delay_i;  // count the clocked reset after the ack
        else if (lvl_q == '0) state_d = ON;
        else begin
          lvl_d = lvl_q - 1;
          cnt_d = delay_i;
        end
      end
      default: state_d = ON;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ON;
      mode_q  <= MODE_CLOCK_GATE;
      lvl_q   <= '0;
      cnt_q   <= '0;
    end else begin
      state_q <= state_d;
      mode_q  <= mode_d;
      lvl_q   <= lvl_d;
      cnt_q   <= cnt_d;
    end
  end

  assign clk_in_reset = state_q == UP && mode_q == MODE_OFF && lvl_q == 3'd3 && !ack_wait;
  assign pwr_ctrl_o.clkgate_en_n   = !(lvl_q >= 3'd1) || clk_in_reset;
  assign pwr_ctrl_o.isogate_en_n   = !(lvl_q >= 3'd2);
  assign pwr_ctrl_o.retentive_en_n = !(mode_q == MODE_RETENTIVE && lvl_q >= 3'd3);
  assign pwr_ctrl_o.rst_n          = !(mode_q == MODE_OFF && lvl_q >= 3'd3);
  assign pwr_ctrl_o.pwrgate_en_n   = !(mode_q == MODE_OFF && lvl_q >= 3'd4);
  assign isolate_o                 = state_q != ON;
  assign sleeping_o                = state_q == ASLEEP;
  assign awake_o                   = state_q == ON;

endmodule
