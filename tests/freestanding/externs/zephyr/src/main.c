/* The `externs` lane's MCU legs: every case, plus the
 * device-only property rows.
 *
 * The case list is #included from the generated cases.inc (one table,
 * mkcases_inc.rb) and the prototypes come from the generated header, so nothing
 * here is transcribed.  The trap hook is the harness shape of the other lanes: record
 * (code, detail) and longjmp back into the driver so all cases run in one
 * image; a second build (-DEXTERNS_PANIC_TRAP=1) runs exactly one narrowing case
 * and k_panic()s, so "an extern-argument trap really is fatal" does not rest
 * on the harness's convenience implementation.
 *
 * After the cases, the PROPERTY rows: the things that are true on a real
 * platform but are not values a host oracle can share --
 *   uptime_monotonic  two k_uptime_get() reads around a k_msleep, t1 >= t0
 *   sleep_elapsed     the uptime delta covered the requested sleep
 *   print_witness     (checked by run_gates.sh: the EXTERNSP line printed by the
 *                     chirp case is in this same console log)
 *   gpio_backend      how many pins were driven through the real GPIO driver
 *                     (2 on mps2/an521, 0 on qemu_riscv32) -- a
 *                     field-of-view row, printed per run rather than assumed
 *   gpio_readback     set pin 0 through the wrapper, read it back through the
 *                     wrapper (on M33 that is a register readback from the
 *                     QEMU-emulated FPGAIO device)
 */
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>

#include "spinel_freestanding.h"

int externs_gpio_real_pins(void); /* spinel_zephyr.c */

static jmp_buf externs_jmp;
static volatile int externs_armed;
static volatile int externs_code;

void spinel_trap(int32_t code, int64_t a, int64_t b, const char *detail)
{
#ifdef EXTERNS_PANIC_TRAP
	printk("EXTERNS\tTRAP\tcode=%d a=%lld b=%lld detail=%s\n",
	       (int)code, (long long)a, (long long)b, detail);
	k_panic();
	for (;;) {
	}
#else
	(void)a;
	(void)b;
	externs_code = code;
	if (externs_armed) {
		longjmp(externs_jmp, 1);
	}
	printk("EXTERNS\tFATAL\tunarmed trap code=%d detail=%s\n", (int)code, detail);
	k_panic();
	for (;;) {
	}
#endif
}

static char externs_line[256];
static int externs_len;

static void externs_put(const char *s)
{
	while (*s && externs_len < (int)sizeof(externs_line) - 1) {
		externs_line[externs_len++] = *s++;
	}
	externs_line[externs_len] = 0;
}

static void externs_puti(long long v)
{
	char b[32];

	snprintf(b, sizeof b, "%lld", v);
	externs_put(b);
}

static void externs_putf(double v)
{
	char b[64];

	/* %.17g round-trips every double; Ruby and JS print shortest forms of
	 * the same value.  The host comparison parses both sides (float rows are a
	 * VALUE comparison, not a byte comparison). */
	snprintf(b, sizeof b, "%.17g", v);
	externs_put(b);
}

#define EXTERNS_BEGIN(name)                                                       \
	externs_len = 0;                                                          \
	externs_line[0] = 0;                                                      \
	externs_code = 0;                                                         \
	externs_armed = 1;                                                        \
	externs_put(name);                                                        \
	externs_put("\t");

#define EXTERNS_CASE_I(name, expr)                                                \
	do {                                                                   \
		EXTERNS_BEGIN(name)                                               \
		if (setjmp(externs_jmp) == 0) {                                   \
			long long _v = (long long)(expr);                      \
			externs_armed = 0;                                        \
			externs_puti(_v);                                         \
		} else {                                                       \
			externs_armed = 0;                                        \
			externs_put("trap:");                                     \
			externs_puti((long long)externs_code);                       \
		}                                                              \
		printk("EXTERNS\t%s\n", externs_line);                               \
	} while (0);

#define EXTERNS_CASE_F(name, expr)                                                \
	do {                                                                   \
		EXTERNS_BEGIN(name)                                               \
		if (setjmp(externs_jmp) == 0) {                                   \
			double _v = (double)(expr);                            \
			externs_armed = 0;                                        \
			externs_putf(_v);                                         \
		} else {                                                       \
			externs_armed = 0;                                        \
			externs_put("trap:");                                     \
			externs_puti((long long)externs_code);                       \
		}                                                              \
		printk("EXTERNS\t%s\n", externs_line);                               \
	} while (0);

#include "cases.inc"

static void externs_props(void)
{
	int64_t t0 = spinel_zephyr_uptime_ms();
	int32_t r = spinel_zephyr_sleep_ms(20);
	int64_t t1 = spinel_zephyr_uptime_ms();

	printk("EXTERNS\tPROP\tuptime_monotonic\t%d\n", t1 >= t0 ? 1 : 0);
	printk("EXTERNS\tPROP\tsleep_elapsed\t%d\n",
	       (t1 - t0 >= 20 && r == 0) ? 1 : 0);
	printk("EXTERNS\tPROP\tgpio_backend\treal_pins=%d\n", externs_gpio_real_pins());
	spinel_zephyr_gpio_set(0, 1);
	printk("EXTERNS\tPROP\tgpio_readback\t%d\n", (int)spinel_zephyr_gpio_get(0));
	spinel_zephyr_gpio_set(0, 0);
	printk("EXTERNS\tPROP\tgpio_readback0\t%d\n", (int)spinel_zephyr_gpio_get(0));
}

int main(void)
{
	printk("EXTERNS\tBEGIN\t%s\n", CONFIG_BOARD_TARGET);
#ifdef EXTERNS_PANIC_TRAP
	/* One case, and it is the ARGUMENT-narrowing one this lane adds:
	 * pin 2**32+5 does not fit the extern's declared :i32.  If the panic
	 * build printed a number here, the extern-argument trap would be a harness fiction. */
	printk("EXTERNS\tpanic-probe\t%d\n",
	       (int)spinel_pin_probe(INT64_C(4294967301)));
	printk("EXTERNS\tUNREACHABLE\t0\n");
#else
	externs_run();
	externs_props();
	printk("EXTERNS\tEND\t0\n");
#endif
	return 0;
}
