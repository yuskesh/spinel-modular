/* The `ints` lane's MCU side: every case of the kernel, printed for the checks.
 *
 * Boots Zephyr, calls every entry the freestanding kernel object exports, and
 * prints one `INTS<TAB><case><TAB><result>` line per case.  The host side
 * (ints_host.rb, compiled by bin/spinel through its ordinary C back end) prints
 * exactly the same first two columns, and run_gates.sh joins them.
 *
 * THE PROTOTYPES ARE NOT WRITTEN HERE.  `spinel-fs-emit --emit-header` wrote
 * them into spinel_freestanding.h from the same declarations it compiled, so a
 * transcription error is not possible -- which is the point of having the
 * boundary be a declaration at all.
 *
 * ---------------------------------------------------------------------------
 * WHAT `spinel_trap` DOES HERE, and why it is allowed to be different
 *
 * The trap hook is the PLATFORM's responsibility:
 * the generator emits a call to a noreturn symbol and `llvm.unreachable` after
 * it, and what happens next is not the compiler's business.  Two platforms are
 * built from this one file:
 *
 *   default            spinel_trap records (code, a, b, detail) and longjmps
 *                      back into the driver, so all 31 cases -- including the
 *                      seven that trap -- run in ONE image.  It never returns to
 *                      its caller, which is the only thing the generated code
 *                      assumes.  This is exactly what the HOSTED runtime does
 *                      (sp_raise_cls longjmps to the innermost handler,
 *                      spinel_rt.h:6685), so it is not a special-case invention.
 *   INTS_PANIC_TRAP    spinel_trap prints and calls k_panic(), which is what a
 *                      real product would do; the panic build demonstrates
 *                      it so that the claim
 *                      "a trap really is fatal" does not rest on the harness's
 *                      convenience implementation.
 */
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <setjmp.h>
#include <stdint.h>

#include "spinel_freestanding.h"

static jmp_buf ints_jmp;
static volatile int ints_armed;
static volatile int ints_code;
static const char *volatile ints_detail;

void spinel_trap(int32_t code, int64_t a, int64_t b, const char *detail)
{
#ifdef INTS_PANIC_TRAP
	printk("INTS\tTRAP\tcode=%d a=%lld b=%lld detail=%s\n",
	       (int)code, (long long)a, (long long)b, detail);
	k_panic();
	for (;;) {
	}
#else
	(void)a;
	(void)b;
	ints_code = code;
	ints_detail = detail;
	if (ints_armed) {
		longjmp(ints_jmp, 1);
	}
	/* A trap outside a driver arm is a bug in the harness, not in the
	 * kernel object; say so loudly rather than falling off the end. */
	printk("INTS\tFATAL\tunarmed trap code=%d detail=%s\n", (int)code, detail);
	k_panic();
	for (;;) {
	}
#endif
}

/* Every case is invoked under setjmp, so a trap becomes a row rather than the
 * end of the run.  `volatile` on nothing here: the only object live across
 * setjmp is the loop index, which lives in the generated code below as a
 * straight-line sequence. */
#define INTS_CASE(name, expr)                                                  \
	do {                                                                   \
		ints_code = 0;                                                 \
		ints_armed = 1;                                                \
		if (setjmp(ints_jmp) == 0) {                                   \
			long long _v = (long long)(expr);                      \
			ints_armed = 0;                                        \
			printk("INTS\t%s\t%lld\n", name, _v);                  \
		} else {                                                       \
			ints_armed = 0;                                        \
			printk("INTS\t%s\ttrap:%d\n", name, (int)ints_code);   \
		}                                                              \
	} while (0);

int main(void)
{
	printk("INTS\tBEGIN\t%s\n", CONFIG_BOARD_TARGET);
#ifdef INTS_PANIC_TRAP
	/* The panic build runs exactly one case: the one that traps. */
	printk("INTS\tpanic-probe\t%lld\n",
	       (long long)spinel_mulnarrow(46341, 46341));
	printk("INTS\tUNREACHABLE\t0\n");
#else
#include "cases.inc"
	printk("INTS\tEND\t0\n");
#endif
	return 0;
}
