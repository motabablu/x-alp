# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author(s): David Mallasen
# Description: Generic (default) configuration for X-ALP

from xalp import XAlp
from cpu.cva6 import cva6
from address_map.address_map import AddressMap
from address_map.address_region import AddressRegion

from peripherals.peripheral_domain import PeripheralDomain
from peripherals.base_peripherals import (
    SOC_ctrl,
    Bootrom,
    Ext_peripheral,
    LLC,
    Power_manager,
    PowerDomain,
)
from peripherals.user_peripherals import (
    UART,
    RV_plic,
    RV_timer,
)
from interrupts.interrupts import Interrupts

from debug_ss.debug_ss import DebugSS


def config():

    soc = XAlp("X-ALP")

    cpu = cva6()
    soc.set_cpu(cpu)

    peripheral_domain = AddressRegion(
        "peripheral_domain", start_address=0x20000000, length=0x00100000
    )

    # The memory subsystem is the last-level cache: its scratchpad answers at
    # 0x10000000 and the region it caches, backed by the DRAM on its master
    # port, at 0x80000000. Both are cacheable and executable by default.
    llc = LLC(
        set_assoc=16,
        num_lines=256,
        num_blocks=8,
        spm_start=0x10000000,
        cached_start=0x80000000,
        cached_size=0x10000000,
    )
    soc.set_memory_ss(llc)

    address_map = AddressMap()
    # Kept at 0x00000000: the debug module ROM is where the linker places
    # `extrom`, which the boot ROM hands control to.
    address_map.add_region(
        AddressRegion("debug", start_address=0x00000000, length=0x00100000)
    )

    address_map.add_region(peripheral_domain)
    address_map.add_region(
        AddressRegion("ext_slaves", start_address=0xF0000000, length=0x01000000)
    )
    soc.set_address_map(address_map)

    soc.set_debug_ss(DebugSS())

    # PLIC sources. IDs must be contiguous from 0: the remaining ones become
    # EXT_INTR_<n>, driven by the ext_intr_i port of the SoC.
    interrupts = Interrupts()
    for i, name in enumerate(
        [
            "null_intr",
            "uart_intr_tx_watermark",
            "uart_intr_rx_watermark",
            "uart_intr_tx_empty",
            "uart_intr_rx_overflow",
            "uart_intr_rx_frame_err",
            "uart_intr_rx_break_err",
            "uart_intr_rx_timeout",
            "uart_intr_rx_parity_err",
            "power_manager_wakeup_timer",
        ]
    ):
        interrupts.add_interrupt(name, i)
    soc.set_interrupts(interrupts)

    uart = UART()

    # Power domains switch groups of blocks (power gating), clock gates stop
    # the clock of single blocks. Both take the instances configured above.
    # The code runs from the LLC: it only sleeps together with the core.
    power_manager = Power_manager(
        power_domains=[
            PowerDomain("cpu", [cpu], modes=["clock_gate", "off"]),
            PowerDomain(
                "llc", [llc], modes=["clock_gate", "retentive", "off"], follows_cpu=True
            ),
        ],
        clock_gates=[uart],
        external_domains=0,
    )

    peripherals = PeripheralDomain(
        peripheral_domain.get_name(),
        power_domain=None,
        clock_gating=False,
        peripherals=[
            SOC_ctrl(),
            Bootrom(),
            Ext_peripheral(),
            uart,
            RV_plic(),
            RV_timer(),
            power_manager,
            llc,
        ],
    )
    soc.add_domain(peripherals)

    return soc
