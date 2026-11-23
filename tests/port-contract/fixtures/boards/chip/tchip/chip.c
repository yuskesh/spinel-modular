/* tests/port-contract: the control chip family's code. It is built and held
 * to the contract, and never run: no chip has this memory map. It is here so
 * that the lanes build a family from a port directory outside tools/bare-full,
 * for ARMv6-M, with an object of the family's own, a part of the link script
 * that places it, and a UF2 image.
 */
#include <stdint.h>

#include "bare.h"

#if BF_BOARD_CONSOLE_UART == 0
#define UART 0x40001000u
#elif BF_BOARD_CONSOLE_UART == 1
#define UART 0x40002000u
#else
#error "tchip: console.uart has no entry in the instance table"
#endif
#define U_DATA (*(volatile uint32_t *)(UART + 0x00))
#define U_BUSY (*(volatile uint32_t *)(UART + 0x04))
#define U_DIV (*(volatile uint32_t *)(UART + 0x08))

const uint32_t bf_early_write[2] = {0u, 0u};

uint32_t bf_core_hz(void)
{
	return BF_BOARD_CLOCK_CRYSTAL_HZ;
}

void bf_console_init(void)
{
	U_DIV = BF_BOARD_CLOCK_CRYSTAL_HZ / BF_BOARD_CONSOLE_BAUD;
}

void bf_putc(char c)
{
	while (U_BUSY & 1u) {
	}
	U_DATA = (uint32_t)(unsigned char)c;
}

void bf_board_report(void)
{
}
