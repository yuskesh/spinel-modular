/* the port's common code */
#ifdef CTL_OWN_TOP
unsigned t_ram_top[4];
#else
extern unsigned t_ram_top[];
#endif
int rt_now(void) __attribute__((weak));
void rt_hidden(void);
void t_chip_init(void);
void t_putc(int c);
int t_hz(void);
int t_us(void) __attribute__((weak));
int t_main(void);
void c_init(void);

void t_reset(void)
{
	t_chip_init();
#ifdef CTL_WEAK
	if (rt_now)
		rt_now();
#endif
	c_init();
#ifdef CTL_HIDDEN
	rt_hidden();
#endif
	t_main();
	for (;;) {
	}
}

#ifndef CTL_NO_VECTORS
__attribute__((section(".t_vectors"), used))
void *const base_vectors[2] = {(void *)t_ram_top, (void *)t_reset};
#else
void *base_top(void) { return t_ram_top; }
#endif

void t_out(int c) { t_putc(c); }
void t_hex(unsigned v) { t_putc("0123456789abcdef"[v & 15u]); }
void t_lock(void) {}
/* nothing in the hello program reads the clock: the image drops this */
int t_time(void) { return t_us ? t_us() : t_hz(); }
#if defined(CTL_UNDECLARED)
void t_extra(void) {}
#endif
#if defined(CTL_KEPT)
void t_secret(void) {}
#endif
#ifdef CTL_SHADOW
int c_len(const char *s) { return s[0] != 0; }
#endif
