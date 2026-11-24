from ..abstractions import BasePeripheral


class PowerDomain:
    """
    A group of blocks that are power gated together.

    :param str name: Name of the domain, used for registers and RTL signals.
    :param list members: Instances (CPU, peripherals, LLC) belonging to the domain. Empty for an external domain.
    :param list modes: Sleep modes the domain supports, a subset of :attr:`Power_manager.MODES`.
    :param bool follows_cpu: The running code depends on the domain (e.g. the memory): it only sleeps together with the cores, never on its own.
    """

    def __init__(self, name: str, members: list = None, modes: list = None, follows_cpu: bool = False):
        self.name = name
        self.members = list(members) if members else []
        self.modes = list(modes) if modes else list(Power_manager.MODES)
        self.follows_cpu = follows_cpu
        # Filled by Power_manager.build()
        self.blocks = []
        self.cores = []


class Power_manager(BasePeripheral):
    """
    Manages power states and clock gating for different system components.

    Power domains (power gating) group blocks; clock gating is per block, one
    register bit each. Both reference the very instances configured in the
    system, so the same peripheral type may appear more than once.
    """

    _name = "power_manager"

    MODES = ["clock_gate", "retentive", "off"]
    """Sleep modes, in the order of their encoding in the MODE registers."""

    NOT_GATEABLE = ["soc_ctrl", "bootrom", "power_manager", "ext_peripheral"]
    """Blocks that must stay always on (or have no clock to gate)."""

    def __init__(
        self,
        address: int = None,
        length: int = None,
        external_domains: int = 0,
        power_domains: list = None,
        clock_gates: list = None,
    ):
        """
        Initialize the Power_manager peripheral.

        :param int address: The virtual (in peripheral domain) memory address of the Power_manager.
        :param int length: The length of the Power_manager.
        :param int external_domains: the number of power domains external to X-HEEP.
        :param list power_domains: the :class:`PowerDomain` groups (X-ALP).
        :param list clock_gates: the instances with a clock gate, one bit each (X-ALP).
        """
        super().__init__(
            address,
            length,
        )

        if external_domains > 32:
            raise ValueError(
                "Power_manager: external_domains must be less than 32 instead of "
                + str(external_domains)
            )

        self._external_domains = external_domains
        self._power_domains = list(power_domains) if power_domains else []
        self._clock_gates = list(clock_gates) if clock_gates else []
        self._cores = []

    def get_external_domains(self):
        """
        Get the number of external domains.
        """
        return self._external_domains

    def set_external_domains(self, value: int):
        """
        Set the number of external domains.
        """
        self._external_domains = value

    # ------------------------------------------------------------
    # X-ALP power and clock domains
    # ------------------------------------------------------------

    def build(self, cores: list, blocks: list):
        """
        Resolves the instances referenced by the domains into RTL names and
        validates the configuration. Must run on the original objects, before
        any deepcopy, since instances are matched by identity.

        Afterwards the domains only keep names, so deep copies stay cheap.

        :param list cores: The CPU instances, in hart order.
        :param list blocks: The other gateable instances (peripherals, LLC).
        """
        self._cores = [c.get_name() for c in cores]

        def resolve(member, owner):
            for i, c in enumerate(cores):
                if member is c:
                    return f"{c.get_name()}_{i}", i
            for b in blocks:
                if member is b:
                    return b.get_name(), None
            raise ValueError(
                f"[MCU-GEN - Power_manager] ERROR: {owner} references {member!r}, which is not part of the system"
            )

        for i in range(self._external_domains):
            self._power_domains.append(PowerDomain(f"external_{i}"))

        in_pd = {}
        names = set()
        for pd in self._power_domains:
            if pd.name in names:
                raise ValueError(
                    f"[MCU-GEN - Power_manager] ERROR: duplicate power domain name {pd.name}"
                )
            names.add(pd.name)
            unknown = set(pd.modes) - set(self.MODES)
            if unknown or not pd.modes:
                raise ValueError(
                    f"[MCU-GEN - Power_manager] ERROR: power domain {pd.name} has invalid modes {sorted(unknown) or pd.modes}, allowed: {self.MODES}"
                )
            for member in pd.members:
                name, core = resolve(member, f"power domain {pd.name}")
                if member.get_name() in self.NOT_GATEABLE:
                    raise ValueError(
                        f"[MCU-GEN - Power_manager] ERROR: {name} cannot be power gated (power domain {pd.name})"
                    )
                if name in in_pd:
                    raise ValueError(
                        f"[MCU-GEN - Power_manager] ERROR: {name} is in power domains {in_pd[name]} and {pd.name}"
                    )
                in_pd[name] = pd.name
                pd.blocks.append(name)
                if core is not None:
                    pd.cores.append(core)
            if pd.follows_cpu and pd.cores:
                raise ValueError(
                    f"[MCU-GEN - Power_manager] ERROR: power domain {pd.name} holds cores, it cannot follow them"
                )
            pd.members = []

        gated = []
        for member in self._clock_gates:
            name, _ = resolve(member, "clock_gates")
            if member.get_name() in self.NOT_GATEABLE:
                raise ValueError(f"[MCU-GEN - Power_manager] ERROR: {name} cannot be clock gated")
            if name in gated:
                raise ValueError(f"[MCU-GEN - Power_manager] ERROR: {name} is twice in clock_gates")
            gated.append(name)
        self._clock_gates = gated

    def get_power_domains(self):
        """
        :return: The power domains, external ones included, after :meth:`build`.
        :rtype: list[PowerDomain]
        """
        return self._power_domains

    def get_clock_gates(self):
        """
        :return: The names of the clock gated blocks (one bit each), after :meth:`build`.
        :rtype: list[str]
        """
        return self._clock_gates

    def num_cores(self):
        """
        :return: The number of cores the power manager watches.
        :rtype: int
        """
        return len(self._cores)

    def get_gated_blocks(self):
        """
        Every block whose clock depends on the power manager.

        :return: ``{name, cg, pd}`` entries, ``cg``/``pd`` being the group index or `None`.
        :rtype: list[dict]
        """
        blocks = {}
        for i, pd in enumerate(self._power_domains):
            for name in pd.blocks:
                blocks.setdefault(name, {"name": name, "cg": None, "pd": None})["pd"] = i
        for i, name in enumerate(self._clock_gates):
            blocks.setdefault(name, {"name": name, "cg": None, "pd": None})["cg"] = i
        return list(blocks.values())

    def clk_of(self, name: str):
        """
        :param str name: RTL name of a block (``cva6_0`` for the first core).
        :return: The clock signal the block must use.
        :rtype: str
        """
        gated = any(b["name"] == name for b in self.get_gated_blocks())
        return f"clk_{name}" if gated else "clk_i"

    def pd_of(self, name: str):
        """
        :param str name: RTL name of a block.
        :return: Index of the power domain holding the block, `None` if always on.
        :rtype: int
        """
        for i, pd in enumerate(self._power_domains):
            if name in pd.blocks:
                return i
        return None
