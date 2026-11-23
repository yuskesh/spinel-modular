/* the control build's link script. run.sh passes it through the C
 * preprocessor: -DCTL_NO_CTORS leaves the constructor bounds out,
 * -DCTL_OWN_TOP the stack top, -DCTL_NO_ENTRY the entry. */
#ifndef CTL_NO_ENTRY
ENTRY(t_reset)
#endif
SECTIONS
{
  . = 0x10000000;
  .t_boot : { KEEP(*(.t_boot)) }
  .t_vectors : { KEEP(*(.t_vectors)) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .init_array : {
#ifndef CTL_NO_CTORS
    t_ctors_start = .;
    __init_array_start = .;
#endif
    KEEP(*(.init_array .init_array.*))
#ifndef CTL_NO_CTORS
    t_ctors_end = .;
    __init_array_end = .;
#endif
  }
  . = 0x20000000;
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.* COMMON) }
#ifndef CTL_OWN_TOP
  t_ram_top = 0x20010000;
#endif
}
