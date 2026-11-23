/* tests/port-contract: the control chip family's part of the link script.
 * The first BF_CHIP_FLASH_HEAD_BYTES bytes of flash are a block the family
 * makes itself (boot/object.rb); the code follows it. */
MEMORY
{
  HEAD (rx)  : ORIGIN = BF_CHIP_FLASH_ORIGIN, LENGTH = BF_CHIP_FLASH_HEAD_BYTES
  CODE (rx)  : ORIGIN = BF_CHIP_FLASH_ORIGIN + BF_CHIP_FLASH_HEAD_BYTES, LENGTH = BF_CHIP_FLASH_SIZE_BYTES - BF_CHIP_FLASH_HEAD_BYTES
  RAM  (rwx) : ORIGIN = BF_CHIP_RAM_ORIGIN, LENGTH = BF_CHIP_RAM_SIZE_BYTES
}
SECTIONS
{
  .boot2 : { KEEP(*(.boot2)) } > HEAD
}
INSERT BEFORE .vectors;
ASSERT(SIZEOF(.boot2) == BF_CHIP_FLASH_HEAD_BYTES, "the head block must fill its region")
