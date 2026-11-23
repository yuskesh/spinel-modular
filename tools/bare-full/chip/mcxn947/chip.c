/* tools/bare-full: the mcxn947 chip family's console, clock and RAM gates,
 * for the secure Cortex-M33 (CPU0) of the NXP MCX N947, with no RTOS. The
 * board file gives the values: which Flexcomm and port, the two pins, their
 * mux and the baud rate. What follows describes the FRDM-MCXN947 board, the
 * one board of this family so far.
 *
 * The console is tests/freestanding/bare-frdm/src/main.c's, unchanged but
 * for the BF_ prefix: LP_FLEXCOMM4 as an LPUART on P1_8/P1_9, which the board
 * wires to the MCU-Link VCOM, 115200 8N1 from FRO_12M. Its comment there
 * gives the source of every register value.
 *
 * RAM: link.ld puts the stack and heap in RAMA to RAMF (0x30000000, 320 KB,
 * the range Zephyr gives CPU0). RAMB to RAMH each have a clock gate,
 * SYSCON AHBCLKCTRL0 bits 2-8 (RAMB_CTRL ... RAMH_CTRL in hal_nxp's
 * PERI_SYSCON.h; kCLOCK_Sram1 ... kCLOCK_Sram7 in MCXN947's fsl_clock.h).
 * What the boot ROM leaves in them is not documented here, so the reset
 * entry sets bits 2-8 through AHBCLKCTRLSET0 (SYSCON 0x50000000 + 0x220)
 * before the stack is used.
 *
 * The core clock is whatever the boot ROM left. bf_board_report prints the
 * registers it is read from, and bf_core_hz computes it: SCG CSR (SCG0
 * 0x50044000 + 0x10) SCS [27:24] names the system clock's source, 2 SIRC
 * (12 MHz) or 3 FIRC, whose rate FIRCCFG (+0x308) RANGE bit 0 selects (0 48
 * MHz, 1 144 MHz); SYSCON AHBCLKDIV (+0x380) DIV [7:0] divides it by DIV+1
 * (PERI_SCG.h, PERI_SYSCON.h). Any other source is reported as 0 Hz, and the
 * clock then counts as if at 12 MHz.
 */
#include <stdint.h>

#include "bare.h"

const uint32_t bf_early_write[2] = {0x50000220u, 0x1fcu};

#define BF_REG(a) (*(volatile uint32_t *)(a))

#define BF_SCG_SIRCCSR BF_REG(0x50044200u) /* SCG0 0x50044000 + 0x200 */
#define BF_SIRC_CLK_PERIPH_EN (1u << 5)
#define BF_SIRC_LK (1u << 23)

#define BF_SYSCON 0x50000000u
#define BF_PRESETCTRL0 BF_REG(BF_SYSCON + 0x100u)
#define BF_PRESETCTRL1 BF_REG(BF_SYSCON + 0x104u)
#define BF_PRESETCTRLCLR0 BF_REG(BF_SYSCON + 0x140u)
#define BF_PRESETCTRLCLR1 BF_REG(BF_SYSCON + 0x144u)
#define BF_AHBCLKCTRLSET0 BF_REG(BF_SYSCON + 0x220u)
#define BF_AHBCLKCTRLSET1 BF_REG(BF_SYSCON + 0x224u)
/* console.flexcomm -> its clock select, clock divider, gate / reset bit and
 * base; console.port -> its gate / reset bit and base. Only instances with a
 * cited source are listed. */
#if BF_BOARD_CONSOLE_FLEXCOMM == 4
#define BF_FCCLKSEL4 BF_REG(BF_SYSCON + 0x2c0u)
#define BF_FLEXCOMMCLKDIV4 BF_REG(BF_SYSCON + 0x860u)
#define BF_FC4_BIT (1u << 15)   /* AHBCLKCTRL1 and PRESETCTRL1 */
#define BF_FC4 0x500b4000u
#else
#error "mcxn947: console.flexcomm has no entry in the instance table"
#endif
#if BF_BOARD_CONSOLE_PORT == 1
#define BF_PORT1_BIT (1u << 14) /* AHBCLKCTRL0 and PRESETCTRL0 */
#define BF_PORT1 0x50117000u
#else
#error "mcxn947: console.port has no entry in the instance table"
#endif

/* PORT1 0x50117000; PCR[n] at 0x80 + 4n. MUX [11:8] = 2 (FC4_P0/P1 are ALT2
 * in hal_nxp's MCXN947VDF-pinctrl.h), IBE bit 12, PE bit 1, PS bit 0: the
 * value Zephyr's pinctrl writes for the board's group (input-enable,
 * bias-pull-up, fast slew, low drive). */
#define BF_PORT1_PCR(n) BF_REG(BF_PORT1 + 0x80u + 4u * (n))
#define BF_PCR_FC4 (((uint32_t)BF_BOARD_CONSOLE_MUX << 8) | 0x00001003u)

/* LP_FLEXCOMM4 0x500B4000: the LPUART registers from 0, PSELID at 0xFF8
 * (PERSEL [2:0], 1 = UART). */
#define BF_FC4_PSELID BF_REG(BF_FC4 + 0xff8u)
#define BF_UART_GLOBAL BF_REG(BF_FC4 + 0x08u) /* RST bit 1 */
#define BF_UART_BAUD BF_REG(BF_FC4 + 0x10u)   /* OSR [28:24] = osr-1, SBR [12:0] */
#define BF_UART_STAT BF_REG(BF_FC4 + 0x14u)   /* TDRE bit 23 */
#define BF_UART_CTRL BF_REG(BF_FC4 + 0x18u)   /* TE bit 19 */
#define BF_UART_DATA BF_REG(BF_FC4 + 0x1cu)
#define BF_UART_FIFO BF_REG(BF_FC4 + 0x28u)   /* TXFE bit 7, TXFLUSH bit 15 */
#define BF_UART_WATER BF_REG(BF_FC4 + 0x2cu)

/* 115200 8N1 from FRO_12M: 26 samples per bit, and the divisor to the
 * nearest whole number (12 MHz / (26 x 115200) = 4.006) */
#define BF_FRO_12M_HZ 12000000u
#define BF_UART_OSR 26u
#define BF_UART_SBR ((BF_FRO_12M_HZ + BF_BOARD_CONSOLE_BAUD * BF_UART_OSR / 2u) / (BF_BOARD_CONSOLE_BAUD * BF_UART_OSR))

static void bf_uart_init(void)
{
	uint32_t sirc = BF_SCG_SIRCCSR;
	if (!(sirc & BF_SIRC_CLK_PERIPH_EN)) {
		if (sirc & BF_SIRC_LK)
			BF_SCG_SIRCCSR = sirc & ~BF_SIRC_LK;
		BF_SCG_SIRCCSR = (BF_SCG_SIRCCSR & ~BF_SIRC_LK) | BF_SIRC_CLK_PERIPH_EN;
	}
	BF_FCCLKSEL4 = 2u;
	BF_FLEXCOMMCLKDIV4 = 3u << 29;
	BF_FLEXCOMMCLKDIV4 = 0u;

	BF_AHBCLKCTRLSET0 = BF_PORT1_BIT;
	BF_AHBCLKCTRLSET1 = BF_FC4_BIT;
	BF_PRESETCTRLCLR0 = BF_PORT1_BIT;
	while (BF_PRESETCTRL0 & BF_PORT1_BIT) {
	}
	BF_PRESETCTRLCLR1 = BF_FC4_BIT;
	while (BF_PRESETCTRL1 & BF_FC4_BIT) {
	}

	BF_PORT1_PCR(BF_BOARD_CONSOLE_RX) = BF_PCR_FC4;
	BF_PORT1_PCR(BF_BOARD_CONSOLE_TX) = BF_PCR_FC4;
	BF_FC4_PSELID = 1u;

	BF_UART_GLOBAL = 2u;
	BF_UART_GLOBAL = 0u;
	BF_UART_BAUD = ((BF_UART_OSR - 1u) << 24) | BF_UART_SBR;
	BF_UART_CTRL = 0u;
	BF_UART_WATER = 0u;
	BF_UART_FIFO |= (1u << 7) | (1u << 15);
	BF_UART_CTRL = 1u << 19;
}

void bf_putc(char c)
{
	while (!(BF_UART_STAT & (1u << 23))) {
	}
	BF_UART_DATA = (uint32_t)(unsigned char)c;
}


void bf_console_init(void)
{
	bf_uart_init();
}

#define BF_SCG_CSR BF_REG(0x50044010u)
#define BF_SCG_FIRCCFG BF_REG(0x50044308u)
#define BF_AHBCLKDIV BF_REG(BF_SYSCON + 0x380u)

static uint32_t bf_measured_hz(void)
{
	uint32_t src, hz;

	src = (BF_SCG_CSR >> 24) & 0xfu;
	if (src == 2u)
		hz = 12000000u;
	else if (src == 3u)
		hz = (BF_SCG_FIRCCFG & 1u) ? 144000000u : 48000000u;
	else
		return 0;
	return hz / ((BF_AHBCLKDIV & 0xffu) + 1u);
}

uint32_t bf_core_hz(void)
{
	uint32_t hz = bf_measured_hz();

	return hz ? hz : 12000000u;
}

void bf_board_report(void)
{
	bf_puts("BAREFULL\tCLOCK\t");
	bf_putu(bf_measured_hz());
	bf_puts("\tSCG_CSR=");
	bf_putx(BF_SCG_CSR);
	bf_puts("\tFIRCCFG=");
	bf_putx(BF_SCG_FIRCCFG);
	bf_puts("\tAHBCLKDIV=");
	bf_putx(BF_AHBCLKDIV);
	bf_puts("\tAHBCLKCTRL0=");
	bf_putx(BF_REG(BF_SYSCON + 0x200u));
	bf_puts("\n");
}
