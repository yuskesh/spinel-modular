/* tools/bare-full: what a board supplies to the common platform code. */
#ifndef BF_BARE_H
#define BF_BARE_H
#include <stdint.h>

#define BF_STR_(x) #x
#define BF_STR(x) BF_STR_(x) /* a value as the text of its number */

/* One register write the reset entry makes before anything touches RAM,
 * not even the stack: {address, value}, or {0, 0} for none. A board whose
 * RAM blocks have clock gates opens them here. */
extern const uint32_t bf_early_write[2];

uint32_t bf_core_hz(void);          /* the clock SysTick counts */
/* Optional: microseconds from a counter that does not follow the core clock.
 * A board that defines it gives clock_gettime this count instead of SysTick,
 * so that a program that changes the core clock keeps the time. */
uint64_t bf_board_us(void) __attribute__((weak));
void bf_console_init(void);
void bf_putc(char c);
/* after BEGIN: board lines of its own (BAREFULL<TAB>...), or nothing */
void bf_board_report(void);

void bf_puts(const char *s);
void bf_putu(unsigned long long v);
void bf_putx(uint32_t v);           /* 0x and eight hex digits */

#endif
