/* tools/bare-full: the runtime's part of the link script, the same for every
 * chip: the order of the sections, and every symbol the base and the C
 * library read from the script.
 *
 * It is given after the chip family's part (chip/<family>/link.ld), which
 * declares the two memory regions this part places things in: CODE, where
 * the image is stored and run from, and RAM. A family whose boot ROM needs
 * something before the vector table adds a section with INSERT BEFORE
 * .vectors; a user adds a section the same way, in a part of their own.
 *
 * .vectors is the first section of CODE unless a part inserts one before it:
 * the base's 16-word vector table (the initial stack pointer, the reset
 * entry and the core's exceptions 2 to 15). .data and every .data.* section
 * are stored in CODE and copied to RAM at reset, so a function a program
 * puts in a .data.* section runs from RAM.
 *
 * The program's heap is the RAM between .bss and the stack. picolibc's sbrk
 * reads __heap_start and __heap_end. --defsym=__bf_heap_bytes=N caps the heap
 * at N bytes. The constructors (.init_array) are kept and run at reset: the
 * runtime registers its hooks in them. The stack size is the board's
 * policy.stack_bytes; the driver puts it in through the C preprocessor
 * (bf-board.h) before the link.
 */
ENTRY(Reset_Handler)
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_size = BF_POLICY_STACK_BYTES;

SECTIONS
{
  .vectors : { KEEP(*(.vectors)) } > CODE
  ASSERT(SIZEOF(.vectors) == 64, "the vector table must be 16 words")
  .text : { *(.text .text.*) } > CODE
  .rodata : { *(.rodata .rodata.*) } > CODE
  .ARM.exidx : { *(.ARM.exidx .ARM.exidx.*) } > CODE

  .init_array : ALIGN(4)
  {
    __bothinit_array_start = .;
    __preinit_array_start = .;
    KEEP(*(.preinit_array))
    __preinit_array_end = .;
    __init_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
    KEEP(*(.init_array .ctors))
    __init_array_end = .;
    __bothinit_array_end = .;
  } > CODE
  .fini_array : ALIGN(4)
  {
    __fini_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
    KEEP(*(.fini_array .dtors))
    __fini_array_end = .;
  } > CODE

  .data : ALIGN(4)
  {
    __data_start = .;
    *(.data .data.*)
    . = ALIGN(4);
    __data_end = .;
  } > RAM AT > CODE
  __data_load = LOADADDR(.data);
  /* the end of the image in flash: one past the last byte that is loaded */
  __image_end = LOADADDR(.data) + SIZEOF(.data);

  .bss (NOLOAD) : ALIGN(8)
  {
    __bss_start = .;
    *(.bss .bss.* COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > RAM
}

__heap_start = ALIGN(__bss_end, 8);
__heap_end = DEFINED(__bf_heap_bytes) ? __heap_start + __bf_heap_bytes : __stack_top - __stack_size;
ASSERT(__heap_end <= __stack_top - __stack_size, "the heap overlaps the stack")
