/* tools/bare-full: the secure Cortex-M33 (CPU0) of the NXP MCX N947 on the
 * FRDM-MCXN947 board, with the sources of tests/freestanding/bare-frdm's
 * map: code at 0x10000000, the 2 MB flash in CPU0's secure alias, where the
 * boot ROM finds the vector table.
 *
 * RAM at 0x30000000, 320 KB: the secure alias of 0x20000000, the range
 * Zephyr's frdm_mcxn947_mcxn947_cpu0.dtsi gives CPU0 (`&sram0`, reg
 * <0x20000000 DT_SIZE_K(320)>), RAMA to RAMF. bare-frdm used only RAMA's
 * 32 KB; the runtime's .bss alone is larger. chip.c opens the clocks of
 * RAMB on. RAM ECC is left as the boot ROM leaves it, as Zephyr does unless
 * configured.
 *
 * The origins and sizes are the chip family's values (chip.yaml) and the
 * board's (its flash size, where it states one), the stack size the board's
 * policy.stack_bytes; the driver puts them in through the C preprocessor
 * (bf-board.h) before the link.
 *
 * This is the chip family's part of the link script: the memory regions.
 * The runtime's part (platform/common/link.ld) follows it and places the
 * sections in the regions named CODE and RAM.
 */
#ifdef BF_POLICY_RAM_BYTES
#define BF_RAM_BYTES BF_POLICY_RAM_BYTES
#else
#define BF_RAM_BYTES BF_CHIP_RAM_BYTES
#endif
MEMORY
{
  CODE (rx)  : ORIGIN = BF_CHIP_FLASH_ORIGIN, LENGTH = BF_CHIP_FLASH_BYTES
  RAM  (rwx) : ORIGIN = BF_CHIP_RAM_ORIGIN, LENGTH = BF_RAM_BYTES
}
