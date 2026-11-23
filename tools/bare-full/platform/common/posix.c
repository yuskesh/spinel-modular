/* tools/bare-full: the small POSIX surface the hosted Spinel runtime needs,
 * with no RTOS: the OS calls the runtime reaches. A true no-op may be a stub,
 * and an answer the runtime would act on is not faked, so files, processes
 * and fibers fail with ENOSYS.
 *
 * The console is the board's UART for every descriptor. The clock is SysTick
 * counting the core clock from the first read, every clock id alike: uptime,
 * as on Zephyr. A board with a microsecond counter that does not follow the
 * core clock (bf_board_us) gives that count instead. nanosleep waits on the
 * clock; sockets, fcntl and poll fail with ENOSYS. getenv answers the runtime's two settings and nothing else:
 * the slab is off (its 4 MB arena does not fit), and the first collection
 * comes at 16 KB.
 */
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>

#include "bare.h"

char *getenv(const char *n)
{
	if (strcmp(n, "SPINEL_GC_SLAB") == 0)
		return BF_STR(BF_POLICY_GC_SLAB);
	if (strcmp(n, "SPINEL_GC_THRESHOLD_KB") == 0)
		return BF_STR(BF_POLICY_GC_THRESHOLD_KB);
	return NULL;
}

ssize_t write(int fd, const void *b, size_t n)
{
	const char *c = b;

	(void)fd;
	for (size_t i = 0; i < n; i++)
		bf_putc(c[i]);
	return (ssize_t)n;
}

ssize_t read(int fd, void *b, size_t n)
{
	(void)fd;
	(void)b;
	(void)n;
	return 0;
}

/* ---- the clock: SysTick wraps every 2^24 core cycles; its interrupt counts them */
#define SYST_CSR (*(volatile uint32_t *)0xE000E010u)
#define SYST_RVR (*(volatile uint32_t *)0xE000E014u)
#define SYST_CVR (*(volatile uint32_t *)0xE000E018u)
static volatile uint32_t bf_wraps;
static int bf_clock_on;

void bf_systick(void)
{
	bf_wraps++;
}

struct bf_timespec {
	long long tv_sec;
	long tv_nsec;
};

int clock_gettime(int id, struct bf_timespec *t)
{
	uint32_t w, v;
	uint64_t cyc;

	static uint32_t hz;

	(void)id;
	if (bf_board_us) {
		uint64_t us = bf_board_us();

		t->tv_sec = (long long)(us / 1000000u);
		t->tv_nsec = (long)(us % 1000000u) * 1000;
		return 0;
	}
	if (!bf_clock_on) {
		hz = bf_core_hz();
		SYST_RVR = 0xFFFFFFu;
		SYST_CVR = 0;
		SYST_CSR = 7u; /* enable, interrupt, core clock */
		bf_clock_on = 1;
	}
	/* A wrap between the two reads is read again. So is 0: the counter
	 * holds it for one cycle, after the write above (before the first
	 * reload) and after each 1-to-0 step, whose wrap the interrupt has or
	 * has not yet counted; read as 0xFFFFFF elapsed it puts the time one
	 * wrap ahead. */
	do {
		w = bf_wraps;
		v = SYST_CVR;
	} while (w != bf_wraps || v == 0);
	cyc = (uint64_t)w * 0x1000000u + (0xFFFFFFu - v);
	t->tv_sec = (long long)(cyc / hz);
	t->tv_nsec = (long)((cyc % hz) * 1000000000u / hz);
	return 0;
}

#define NOSYS(decl) decl { errno = ENOSYS; return -1; }
int close(int fd) { (void)fd; return 0; }
NOSYS(int open(const char *p, int f, ...))
NOSYS(off_t lseek(int fd, off_t o, int w))
NOSYS(int stat(const char *p, void *s))
NOSYS(int fstat(int fd, void *s))
NOSYS(int lstat(const char *p, void *s))
NOSYS(int getcontext(void *u))
NOSYS(int setcontext(const void *u))
NOSYS(int swapcontext(void *a, const void *b))
void makecontext(void *u, void (*f)(void), int n, ...) { (void)u; (void)f; (void)n; }
int sigaction(int s, const void *a, void *o) { (void)s; (void)a; (void)o; return 0; }
/* The runtime's socket and pipe paths (sp_sock_write, sp_io_wait_writable)
 * stay reachable from a polymorphic call such as `<<` on a boxed value,
 * even when the program has no socket: there is none here, so they fail. */
NOSYS(ssize_t send(int fd, const void *b, size_t n, int f))
NOSYS(int getsockopt(int fd, int l, int o, void *v, void *n))
NOSYS(int fcntl(int fd, int c, ...))
NOSYS(int poll(void *f, unsigned long n, int ms))
/* Queue#push's back-off and Kernel#sleep: wait on the clock. */
int nanosleep(const struct bf_timespec *r, struct bf_timespec *rem)
{
	struct bf_timespec now;
	long long end_s;
	long end_ns;

	if (r->tv_sec < 0 || r->tv_nsec < 0 || r->tv_nsec >= 1000000000L) {
		errno = EINVAL;
		return -1;
	}
	clock_gettime(0, &now);
	end_s = now.tv_sec + r->tv_sec;
	end_ns = now.tv_nsec + r->tv_nsec;
	if (end_ns >= 1000000000L) {
		end_s++;
		end_ns -= 1000000000L;
	}
	do
		clock_gettime(0, &now);
	while (now.tv_sec < end_s || (now.tv_sec == end_s && now.tv_nsec < end_ns));
	if (rem) {
		rem->tv_sec = 0;
		rem->tv_nsec = 0;
	}
	return 0;
}
/* A failed mapping keeps the program on the reset stack. */
void *mmap(void *a, size_t n, int p, int f, int fd, long o)
{
	(void)a; (void)n; (void)p; (void)f; (void)fd; (void)o;
	return (void *)-1;
}
int munmap(void *a, size_t n) { (void)a; (void)n; return 0; }
int mprotect(void *a, size_t n, int p) { (void)a; (void)n; (void)p; return 0; }
int madvise(void *a, size_t n, int w) { (void)a; (void)n; (void)w; return 0; }
/* isatty: upstream Spinel's runtime asks it of STDOUT at start (820b9a6a6) to
 * write a terminal through. Nothing here is a terminal, so STDOUT keeps the
 * buffering stdio gives it, as before that change. */
int isatty(int fd) { (void)fd; errno = ENOTTY; return 0; }
