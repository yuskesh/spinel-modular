/* tools/bare-full: the an521 chip family's console and clock (the AN521
 * image of the MPS2+, as QEMU's mps2-an521 models it). The board file gives
 * the values: which UART, its divisor and the core clock.
 *
 * UART0 at 0x50200000, as tests/freestanding/bare/src/main.c drives it (a
 * CMSDK APB UART: DATA at 0x0, STATE at 0x4 with bit 0 TX full, CTRL at 0x8,
 * BAUDDIV at 0x10). The mps2-an521 board's core clock is 25 MHz (Zephyr's
 * boards/arm/mps2/mps2_an521-common.dtsi, clock-frequency = <25000000>).
 */
#include <stdint.h>

#include "bare.h"

/* console.uart -> the UART base (secure alias). Only instances with a cited
 * source are listed. */
#if BF_BOARD_CONSOLE_UART == 0
#define UART0 0x50200000u
#else
#error "an521: console.uart has no entry in the instance table"
#endif
#define U_DATA (*(volatile uint32_t *)(UART0 + 0x00))
#define U_STATE (*(volatile uint32_t *)(UART0 + 0x04))
#define U_CTRL (*(volatile uint32_t *)(UART0 + 0x08))
#define U_BAUD (*(volatile uint32_t *)(UART0 + 0x10))

const uint32_t bf_early_write[2] = {0u, 0u}; /* the RAM needs nothing */

uint32_t bf_core_hz(void)
{
	return BF_BOARD_CLOCK_CORE_HZ;
}

void bf_console_init(void)
{
	U_BAUD = BF_BOARD_CONSOLE_BAUD_DIVISOR;
	U_CTRL = 1;
}

void bf_putc(char c)
{
	while (U_STATE & 1u) {
	}
	U_DATA = (uint32_t)(unsigned char)c;
}

void bf_board_report(void)
{
}
