/* The Zephyr instance of the platform-extern surface.
 *
 * These are the `spinel_zephyr_*` wrappers: the generator
 * never reads a Zephyr header, the kernel imports exactly these symbols, and
 * the profile (cortex-m33-zephyr-externs.yaml) is the single declaration both
 * sides are held to.  Two independent witnesses enforce the agreement:
 *
 *   1. the extern check (`spinel-fs-check --extern`) scans this file's signatures
 *      against the profile (the transcription-lie gate);
 *   2. this TU #includes the GENERATED header (spinel_freestanding.h carries
 *      a prototype per declared extern), so Zephyr's own C compiler refuses a
 *      conflicting definition at build time -- the dynamic backing of the
 *      static scan.
 *
 * THE GPIO BACKEND, stated exactly (an instrument has a field of view).
 * The extern contract is a pin register file: pins 0..7, values 0..1,
 * `set` echoes the value written, `get` returns the last value set, -1
 * outside the range.  On mps2/an521 the board HAS a GPIO controller QEMU
 * models (the FPGAIO LED register, DT node gpio_led0, 2 pins), so pins 0..1
 * are READ AND WRITTEN THROUGH the real Zephyr GPIO driver -- a `get` on pin
 * 0 is a register readback from the emulated device, not a variable.  Pins
 * 2..7 (and every pin on qemu_riscv32, whose virt board has no GPIO node)
 * fall back to a shadow array in this wrapper.  main.c prints which backend
 * each build actually used (`EXTERNS  PROP  gpio_backend  ...`), so the claim in
 * the log is per-run, not per-comment.
 */
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <zephyr/devicetree.h>
#include <stdint.h>

#include "spinel_freestanding.h"

#define EXTERNS_NPINS 8

static int32_t pin_shadow[EXTERNS_NPINS];

#if DT_NODE_HAS_STATUS(DT_NODELABEL(gpio_led0), okay) && defined(CONFIG_GPIO)
#include <zephyr/drivers/gpio.h>
#define EXTERNS_HAVE_GPIO 1
#define EXTERNS_REAL_PINS 2 /* the FPGAIO LED register has two pins */
static const struct device *const externs_gpio =
	DEVICE_DT_GET(DT_NODELABEL(gpio_led0));
static int externs_pin_is_real(int32_t pin)
{
	return pin >= 0 && pin < EXTERNS_REAL_PINS && device_is_ready(externs_gpio);
}
#else
static int externs_pin_is_real(int32_t pin)
{
	(void)pin;
	return 0;
}
#endif

int externs_gpio_real_pins(void)
{
#ifdef EXTERNS_HAVE_GPIO
	return device_is_ready(externs_gpio) ? EXTERNS_REAL_PINS : 0;
#else
	return 0;
#endif
}

int64_t spinel_zephyr_uptime_ms(void)
{
	return k_uptime_get();
}

int32_t spinel_zephyr_sleep_ms(int32_t ms)
{
	return k_msleep(ms);
}

int32_t spinel_zephyr_print_i64(int64_t v)
{
	/* A distinct prefix (EXTERNSP) so the differential's line extractor never
	 * mistakes a platform side effect for a case result. */
	printk("EXTERNSP\tprint\t%lld\n", (long long)v);
	return 0;
}

int32_t spinel_zephyr_gpio_set(int32_t pin, int32_t val)
{
	if (pin < 0 || pin >= EXTERNS_NPINS || val < 0 || val > 1) {
		return -1;
	}
	pin_shadow[pin] = val;
#ifdef EXTERNS_HAVE_GPIO
	if (externs_pin_is_real(pin)) {
		gpio_pin_set_raw(externs_gpio, (gpio_pin_t)pin, val);
	}
#endif
	return val;
}

int32_t spinel_zephyr_gpio_get(int32_t pin)
{
	if (pin < 0 || pin >= EXTERNS_NPINS) {
		return -1;
	}
#ifdef EXTERNS_HAVE_GPIO
	if (externs_pin_is_real(pin)) {
		return gpio_pin_get_raw(externs_gpio, (gpio_pin_t)pin);
	}
#endif
	return pin_shadow[pin];
}

double spinel_zephyr_sense_scale(float a, double b)
{
	return (double)a * 2.0 + b;
}

uint32_t spinel_zephyr_checksum32(uint32_t v)
{
	return v ^ 0xA5A5A5A5u;
}
