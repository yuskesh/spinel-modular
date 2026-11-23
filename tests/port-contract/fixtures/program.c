/* the program: one object, measured from what the base asks of it */
void rt_emit(int c);
void t_lock(void);
int rt_now(void);
void t_secret(void);
int t_main(void)
{
#ifdef CTL_LOCK
	t_lock();
#endif
#ifdef CTL_CLOCK
	rt_emit(rt_now());
#endif
	rt_emit('x');
	return 0;
}

#ifdef CTL_KEPT
/* no global names this: only the script's KEEP holds it in the image */
__attribute__((section(".t_vectors"), used)) static void (*const program_slot)(void) = t_secret;
#endif
