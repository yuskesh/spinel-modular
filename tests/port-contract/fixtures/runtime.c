/* the runtime archive. rt_unused is in the same member as rt_emit and nothing
 * calls it: the link drops its section, so what it calls (t_never, which
 * nothing defines) is not a crossing. A measure that kept whole members
 * would report it. */
void t_out(int c);
void t_never(void);
int t_time(void);
void t_extra(void);
int c_len(const char *s);
int rt_is_ready(void);

void rt_emit(int c)
{
	t_out(c + c_len("a") + rt_is_ready());
#ifdef CTL_UNDECLARED
	t_extra();
#endif
}

static int rt_ready;
__attribute__((constructor)) static void rt_hooks(void) { rt_ready = 1; }
int rt_is_ready(void) { return rt_ready; }

#ifdef CTL_HIDDEN
/* global to the link, local in the image's symbol table */
__attribute__((visibility("hidden"))) void rt_hidden(void) {}
#endif

void rt_unused(void)
{
	t_never();
}

int rt_now(void)
{
	return t_time();
}
