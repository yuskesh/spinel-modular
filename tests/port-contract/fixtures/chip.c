/* the chip family and board code */
void t_hex(unsigned v);
void rt_emit(int c);

void t_chip_init(void)
{
	t_hex(1u);
#ifdef CTL_REACH
	rt_emit('!');
#endif
}
void t_putc(int c) { *(volatile unsigned *)0x40000000u = (unsigned)c; }
#ifndef CTL_OMIT
int t_hz(void) { return 1000; }
#endif
#ifdef CTL_OPTIONAL
int t_us(void) { return 7; }
#endif
#ifdef CTL_STRAY
int chip_private_counter;
#endif
#ifdef CTL_CHIP_LATENT
/* nothing calls this and the image drops it; the chip's surface is closed
 * in every program all the same */
int t_us(void) { rt_emit('?'); return 7; }
#endif
#ifdef CTL_BOOT
__attribute__((section(".t_boot"), used)) static const unsigned chip_boot[4] = {1, 2, 3, 4};
#endif
