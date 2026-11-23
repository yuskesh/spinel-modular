/* tools/bare-full: the secure Cortex-M33 (CPU0) of QEMU's mps2-an521, as in
 * tests/freestanding/bare/src/link.ld (which names the sources of the map):
 * code at 0x10000000 (SSRAM-0's secure alias, 4 MB), RAM at 0x38000000
 * (SSRAM-1 and SSRAM-2's secure alias, 4 MB).
 *
 * The origins and sizes are the chip family's values (chip.yaml), the stack
 * size the board's policy.stack_bytes; the driver puts them in through the
 * C preprocessor (bf-board.h) before the link.
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
