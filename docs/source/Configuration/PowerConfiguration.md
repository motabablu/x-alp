# Power Configuration

Power gating and clock gating are configured in `configs/soc.py` through the {py:class}`~xheep_gen.peripherals.base_peripherals.Power_manager.Power_manager` peripheral: power domains switch groups of blocks, clock gates stop the clock of single blocks. The hardware and the software interface of the power manager are described in [Peripherals](../Peripherals/index.md).

## Example

The default configuration:

```python
from peripherals.base_peripherals import Power_manager, PowerDomain

uart = UART()

power_manager = Power_manager(
    power_domains=[
        PowerDomain("cpu", [cpu], modes=["clock_gate", "off"]),
        PowerDomain("llc", [llc], modes=["clock_gate", "retentive", "off"], follows_cpu=True),
    ],
    clock_gates=[uart],
    external_domains=1,
)

peripherals = PeripheralDomain(
    peripheral_domain.get_name(),
    peripherals=[SOC_ctrl(), Bootrom(), Ext_peripheral(), uart, RV_plic(), RV_timer(), power_manager, llc],
)
```

Power domains and clock gates take the instances of the configuration, not their names. Create each instance once (`uart = UART()`) and pass the same object to its peripheral domain and to the power manager. The power manager itself is a peripheral: add it to a peripheral domain.

## Power domains

A {py:class}`~xheep_gen.peripherals.base_peripherals.Power_manager.PowerDomain` groups the blocks that sleep together:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `name` | | Name of the domain: `PD_<NAME>_*` registers, `PD_<NAME>_IDX` in `core_v_mcu_pkg`, `pm_<name>_*()` in `power_manager_sdk.h` |
| `members` | `[]` | Instances in the domain: the CPU, peripherals, the LLC. Empty for an external domain |
| `modes` | all | Sleep modes the domain supports, a subset of `clock_gate`, `retentive`, `off` |
| `follows_cpu` | `False` | The running code depends on the domain (e.g. the memory it runs from): it only sleeps together with the cores, armed with `pm_<name>_<mode>_with_cpu()` |

The modes are `clock_gate` (clock stopped), `retentive` (plus isolation and retention) and `off` (plus reset and power switch off, state lost). Software can only request the modes of `modes`: any other one fails to compile.

The domain that holds the core is the one `cpu_sleep_cycles()` and `cpu_sleep_until()` (`cpu_sdk.h`) put to sleep. The core leaves WFI through the PLIC, so both need `rv_plic`; `cpu_sleep_cycles()` also needs the `power_manager_wakeup_timer` source in the [interrupts](../Peripherals/index.md). The domain that holds the core cannot use `follows_cpu`.

### External domains

A domain without members is external: it has no block inside the chip, and its control signals leave on the `ext_pwr_ctrl_o`/`ext_pwr_ack_i` ports of `x_alp`, one entry per external domain in configuration order. `external_domains=N` (at most 32) appends `N` of them, `external_0` to `external_<N-1>`, with all modes.

## Clock gates

`clock_gates` lists the instances whose clock software can stop on its own, one bit each: the `CG_<NAME>` register, `CG_<NAME>_IDX` in `core_v_mcu_pkg` and `pm_<name>_clock_gate(gated)` in `power_manager_sdk.h`. A block can have a clock gate and be in a power domain at the same time.

`<name>` is the RTL name of the block: `cva6_0` for the core, the peripheral name otherwise (`uart`, `axi_llc`, ...). Every block in a power domain or with a clock gate gets its own clock, `clk_<name>`.

## Checks

`mcu-gen` stops with an error when:

- two power domains have the same name;
- `modes` is empty or holds an unknown mode;
- a member or a clock gate is not part of the system (a different instance);
- a block is in two power domains, or twice in `clock_gates`;
- `soc_ctrl`, `bootrom`, `power_manager` or `ext_peripheral`, which are always on, are in a power domain or in `clock_gates`;
- the domain that holds the core has `follows_cpu=True`;
- `external_domains` is greater than 32.

## Generated files

`mcu-gen` derives from this configuration:

- `core_v_mcu_pkg`: `NUM_PD`, `PD_<NAME>_IDX`, `NUM_EXT_PD`, `NUM_CG`, `CG_<NAME>_IDX`;
- `hw/ip/power_manager/data/power_manager.hjson`, with one group of `PD_<NAME>_*` registers per domain and one `CG_<NAME>` register per clock gate, and from it the register RTL and `power_manager_regs.h`;
- `hw/ip/power_manager/rtl/power_manager.sv` and, in `core_v_mcu.sv`, the clock gates, power switches and AXI isolation of every block;
- the SDK headers `sw/device/lib/sdk/cpu/cpu_sdk.h` and `sw/device/lib/sdk/power_manager/power_manager_sdk.h`.
