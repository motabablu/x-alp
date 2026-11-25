# Prepare X-ALP on FPGA for a `load` into the LLC scratchpad (LINKER=spm).
# Mirrors the boot ROM: wait for the LLC BIST, lock every way as SPM, wait
# for the commit to land. Without this, writes to 0x10000000 return SLVERR.
#
# Usage: riscv64-unknown-elf-gdb -x util/fpga_init.gdb <app>.elf
#        then: load, continue

target extended-remote :3333
monitor reset halt

# Base from the linker symbol, offsets from axi_llc_regs.h.
set $llc = (unsigned long)&__base_axi_llc
# BIST_STATUS
while (*(unsigned int *)($llc + 0x48) & 1) == 0
end
# SET_ASSO_LOW
set $ways = *(unsigned int *)($llc + 0x28)
# CFG_SPM_LOW, CFG_SPM_HIGH, COMMIT_CFG
set *(unsigned int *)($llc + 0x00) = (1 << $ways) - 1
set *(unsigned int *)($llc + 0x04) = 0
set *(unsigned int *)($llc + 0x10) = 1
# FLUSHED_LOW == CFG_SPM_LOW
while *(unsigned int *)($llc + 0x18) != *(unsigned int *)($llc + 0x00)
end
printf "LLC SPM locked @0x%08lx: CFG_SPM_LOW=0x%08x\n", $llc, *(unsigned int *)($llc + 0x00)
