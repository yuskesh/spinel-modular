/* tools/bare-full: reset, the vector table and the end of the program, for a
 * Cortex-M33 with no RTOS.
 *
 * Reset copies .data, zeroes .bss, opens the console and runs the
 * constructors (the runtime registers hooks in .init_array; without them
 * every inspect prints "{}"), then the program. The console carries three
 * lines of its own around the program's output:
 *
 *   BAREFULL<TAB>BEGIN
 *   BAREFULL<TAB>GC<TAB><collections>     at exit
 *   BAREFULL<TAB>EXIT<TAB><status>        at exit; then the core stops
 *
 * and a board may print lines of its own, also starting BAREFULL<TAB>, right
 * after BEGIN. A fault prints BAREFULL<TAB>FATAL<TAB>fault and stops.
 *
 * The reset entry runs before C, as tests/freestanding/bare-frdm's does: it
 * clears MSPLIM (a limit a boot ROM left could sit above this stack), makes
 * the board's early write (bf_early_write: on the MCX N947, the clocks of the
 * RAM blocks the stack and heap are in), sets MSP from the linker script and
 * points VTOR (0xE000ED08) at this table, so faults are taken here. It uses
 * no stack until MSP is set.
 */
#include <stdint.h>
#include <stdlib.h>

#include "bare.h"

extern uint32_t __data_load[], __data_start[], __data_end[];
extern uint32_t __bss_start[], __bss_end[];
extern uint32_t __stack_top[];
extern unsigned long long sp_gc_stat_collections;
extern void __libc_init_array(void);
int sp_app_main(int argc, char **argv);

void Reset_Handler(void);
void bf_reset_c(void);
void bf_fault(void);
void bf_systick(void);

void bf_puts(const char *s)
{
	while (*s)
		bf_putc(*s++);
}

void bf_putx(uint32_t v)
{
	bf_puts("0x");
	for (int i = 28; i >= 0; i -= 4)
		bf_putc("0123456789abcdef"[(v >> i) & 0xfu]);
}

void bf_putu(unsigned long long v)
{
	char b[24];
	int n = 0;

	do {
		b[n++] = (char)('0' + v % 10);
		v /= 10;
	} while (v);
	while (n)
		bf_putc(b[--n]);
}

/* MSPLIM exists from ARMv8-M on; ARMv6-M (the RP2040's Cortex-M0+) has no
 * stack limit and no CBZ. */
#if defined(__ARM_ARCH_6M__)
#define BF_CLEAR_MSPLIM ""
#define BF_SKIP_IF_ZERO "cmp r0, #0\n" "beq 1f\n"
#else
#define BF_CLEAR_MSPLIM "movs r0, #0\n" "msr msplim, r0\n"
#define BF_SKIP_IF_ZERO "cbz r0, 1f\n"
#endif

__attribute__((naked, noreturn)) void Reset_Handler(void)
{
	__asm volatile(BF_CLEAR_MSPLIM
		       "ldr r2, =bf_early_write\n"
		       "ldr r0, [r2]\n"
		       BF_SKIP_IF_ZERO
		       "ldr r1, [r2, #4]\n"
		       "str r1, [r0]\n"
		       "dsb\n"
		       "1:\n"
		       "ldr r0, =__stack_top\n"
		       "msr msp, r0\n"
		       "ldr r0, =bf_vectors\n"
		       "ldr r1, =0xe000ed08\n"
		       "str r0, [r1]\n"
		       "dsb\n"
		       "isb\n"
		       "b bf_reset_c\n"
		       ".ltorg\n");
}

void bf_reset_c(void)
{
	static char *argv[] = {"app", 0};
	const uint32_t *src = __data_load;

	for (uint32_t *d = __data_start; d < __data_end;)
		*d++ = *src++;
	for (uint32_t *d = __bss_start; d < __bss_end;)
		*d++ = 0;
	bf_console_init();
	bf_puts("BAREFULL\tBEGIN\n");
	bf_board_report();
	__libc_init_array();
	exit(sp_app_main(1, argv));
}

/* picolibc's exit runs the atexit handlers and the destructors, then this */
void _exit(int status)
{
	bf_puts("BAREFULL\tGC\t");
	bf_putu(sp_gc_stat_collections);
	bf_puts("\nBAREFULL\tEXIT\t");
	bf_putu((unsigned int)status & 0xffu);
	bf_puts("\n");
	for (;;) {
	}
}

void bf_fault(void)
{
	bf_puts("BAREFULL\tFATAL\tfault\n");
	for (;;) {
	}
}

/* Initial SP, reset, then NMI, HardFault, MemManage, BusFault, UsageFault,
 * SecureFault, three reserved, SVCall, DebugMonitor, reserved, PendSV and
 * SysTick (ARMv8-M exception numbers 1-15). SysTick is the only interrupt
 * (posix.c counts its wraps for the clock). Words 8-10 are ARMv8-M reserved
 * and stay zero, as bare-frdm's do: LinkServer-written images in that shape
 * boot on the MCX N947. Global so that Reset_Handler can name it. */
__attribute__((section(".vectors"), used))
void *const bf_vectors[16] = {
	(void *)__stack_top, (void *)Reset_Handler,
	(void *)bf_fault, (void *)bf_fault, (void *)bf_fault, (void *)bf_fault,
	(void *)bf_fault, (void *)bf_fault,
	0, 0, 0,
	(void *)bf_fault, (void *)bf_fault,
	0,
	(void *)bf_fault, (void *)bf_systick,
};
