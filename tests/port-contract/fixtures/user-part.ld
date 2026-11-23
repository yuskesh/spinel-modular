/* A user's link part, for tests/port-contract/boards.sh: one section of
 * their own, 16 bytes written by the script itself, placed after .rodata of
 * the runtime's part. */
SECTIONS
{
  .user_table :
  {
    __user_table = .;
    LONG(0x11111111) LONG(0x22222222) LONG(0x33333333) LONG(0x44444444)
  } > CODE
}
INSERT AFTER .rodata;
