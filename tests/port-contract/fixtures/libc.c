/* the C library: any part may use it. Its own references to the constructor
 * bounds are weak, as picolibc's are. The second pair has the names ld.lld
 * defines by itself when a script leaves them out. */
extern void (*__init_array_start[])(void) __attribute__((weak));
extern void (*__init_array_end[])(void) __attribute__((weak));
extern void (*t_ctors_start[])(void) __attribute__((weak));
extern void (*t_ctors_end[])(void) __attribute__((weak));

void c_init(void)
{
	for (void (**f)(void) = t_ctors_start; f < t_ctors_end; f++)
		(*f)();
	for (void (**f)(void) = __init_array_start; f < __init_array_end; f++)
		(*f)();
}
