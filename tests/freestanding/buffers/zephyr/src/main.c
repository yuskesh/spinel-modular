/* The `buffers` lane's MCU side: every case, with the buffers it writes.
 *
 * The same shape as the `ints` driver, with one thing added: a case's answer is
 * now the returned value AND, where the declaration says a buffer is written,
 * the buffer's contents afterwards.  Printing both is what makes "the four
 * targets agree" a statement about MEMORY and not only about r0.
 *
 * THE PROTOTYPES ARE NOT WRITTEN HERE.  `spinel-fs-emit --emit-header` wrote
 * them from the same declarations it compiled, so a transcription error is not
 * possible -- and with buffers there is now something worth transcribing
 * wrongly (which int32_t is a length?  is that pointer const?).  The header
 * answers both, in C, where the C compiler enforces it.
 *
 * ---------------------------------------------------------------------------
 * WHAT `spinel_trap` DOES HERE
 *
 * Exactly what the `ints` driver makes it do, for the same reason: it records
 * (code, a, b, detail) and longjmps back into the driver, so all cases --
 * including the ones that trap -- run in one image.  It never returns to its
 * caller, which is the only thing the generated code assumes.  A second build
 * (-DBUFFERS_PANIC_TRAP=1) calls k_panic() instead, so that "a bounds trap really
 * is fatal" does not rest on the harness's convenience implementation.
 *
 * This lane adds three codes to the ones the `ints` lane knows (1 overflow, 2 divzero,
 * 3 narrow): 4 bounds, 5 NULL buffer, 6 negative length.  The driver prints
 * the code, so the differential distinguishes them.
 */
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>

#include "spinel_freestanding.h"

static jmp_buf buffers_jmp;
static volatile int buffers_armed;
static volatile int buffers_code;
static const char *volatile buffers_detail;

void spinel_trap(int32_t code, int64_t a, int64_t b, const char *detail)
{
#ifdef BUFFERS_PANIC_TRAP
	printk("BUFFERS\tTRAP\tcode=%d a=%lld b=%lld detail=%s\n",
	       (int)code, (long long)a, (long long)b, detail);
	k_panic();
	for (;;) {
	}
#else
	(void)a;
	(void)b;
	buffers_code = code;
	buffers_detail = detail;
	if (buffers_armed) {
		longjmp(buffers_jmp, 1);
	}
	printk("BUFFERS\tFATAL\tunarmed trap code=%d detail=%s\n", (int)code, detail);
	k_panic();
	for (;;) {
	}
#endif
}

/* One line per case.  The value first, then (for a case that names an output
 * fixture) the buffer, as `v,v,v,` -- the same trailing-comma rendering the
 * Ruby driver produces, so the two texts are comparable without a parser. */
static char buffers_line[512];
static int buffers_len;

static void buffers_put(const char *s)
{
	while (*s && buffers_len < (int)sizeof(buffers_line) - 1) {
		buffers_line[buffers_len++] = *s++;
	}
	buffers_line[buffers_len] = 0;
}

static void buffers_puti(long long v)
{
	char b[32];
	snprintf(b, sizeof b, "%lld", v);
	buffers_put(b);
}

static void buffers_putf(double v)
{
	char b[64];
	/* %.17g round-trips every double.  Ruby prints the SHORTEST decimal that
	 * round-trips, which is different text for the same value -- the harness
	 * parses both sides and compares the doubles, and says so.  Choosing a
	 * format that made the strings match would hide the fact that this is a
	 * value comparison, not a byte comparison. */
	snprintf(b, sizeof b, "%.17g", v);
	buffers_put(b);
}

static int buffers_trapped;

#define BUFFERS_BEGIN(name)                                                       \
	buffers_len = 0;                                                          \
	buffers_line[0] = 0;                                                      \
	buffers_code = 0;                                                         \
	buffers_trapped = 0;                                                      \
	buffers_armed = 1;                                                        \
	buffers_put(name);                                                        \
	buffers_put("\t");

/* A trapped case prints `trap:<code>` and NO buffer columns.  Not an
 * omission: the trap hook never returns, so the buffer's contents at that
 * point are whatever the kernel had written before the fault, which is a
 * property of the schedule and not of the contract.  The Ruby side is in the
 * same position (the process died), so both sides print one column. */
#define BUFFERS_CASE_I(name, expr)                                                \
	do {                                                                   \
		BUFFERS_BEGIN(name)                                               \
		if (setjmp(buffers_jmp) == 0) {                                   \
			long long _v = (long long)(expr);                      \
			buffers_armed = 0;                                        \
			buffers_puti(_v);                                         \
		} else {                                                       \
			buffers_armed = 0;                                        \
			buffers_trapped = 1;                                      \
			buffers_put("trap:");                                     \
			buffers_puti((long long)buffers_code);                       \
		}                                                              \
	} while (0);

#define BUFFERS_CASE_F(name, expr)                                                \
	do {                                                                   \
		BUFFERS_BEGIN(name)                                               \
		if (setjmp(buffers_jmp) == 0) {                                   \
			double _v = (double)(expr);                            \
			buffers_armed = 0;                                        \
			buffers_putf(_v);                                         \
		} else {                                                       \
			buffers_armed = 0;                                        \
			buffers_trapped = 1;                                      \
			buffers_put("trap:");                                     \
			buffers_puti((long long)buffers_code);                       \
		}                                                              \
	} while (0);

#define BUFFERS_BUF_U8(nm)                                                        \
	do {                                                                   \
		if (!buffers_trapped) {                                           \
			buffers_put("\t");                                        \
			for (unsigned _j = 0;                                  \
			     _j < sizeof(nm) / sizeof(nm[0]); _j++) {          \
				buffers_puti((long long)nm[_j]);                  \
				buffers_put(",");                                 \
			}                                                      \
		}                                                              \
	} while (0);
#define BUFFERS_BUF_I32 BUFFERS_BUF_U8
#define BUFFERS_BUF_F32(nm)                                                       \
	do {                                                                   \
		if (!buffers_trapped) {                                           \
			buffers_put("\t");                                        \
			for (unsigned _j = 0;                                  \
			     _j < sizeof(nm) / sizeof(nm[0]); _j++) {          \
				buffers_putf((double)nm[_j]);                     \
				buffers_put(",");                                 \
			}                                                      \
		}                                                              \
	} while (0);
#define BUFFERS_BUF_F64 BUFFERS_BUF_F32

#define BUFFERS_EOL()                                                             \
	do {                                                                   \
		printk("BUFFERS\t%s\n", buffers_line);                               \
	} while (0);

#include "cases.inc"

int main(void)
{
	printk("BUFFERS\tBEGIN\t%s\n", CONFIG_BOARD_TARGET);
#ifdef BUFFERS_PANIC_TRAP
	/* The panic build runs exactly one case: a KERNEL that indexes one past
	 * the length it was given (trap 4).  Note which case it is NOT:
	 * `spinel_adler32(bf_hello, 9)` is a CALLER that lied about the length,
	 * and the bounds check cannot see that -- it reads nine bytes because it
	 * was told there were nine.  Picking the wrong one of those two here
	 * would have made the panic build print a number and look healthy. */
	printk("BUFFERS\tpanic-probe\t%lld\n",
	       (long long)spinel_sum_offby1(bf_sig, 8));
	printk("BUFFERS\tUNREACHABLE\t0\n");
#else
	buffers_run();
	printk("BUFFERS\tEND\t0\n");
#endif
	return 0;
}
