/* An extern-check control: gpio_set with ONE parameter (the declaration says two). */
#include <stdint.h>
#ifdef EXTERNS_WITH_HEADER
#include "spinel_freestanding.h"
#endif
int32_t spinel_zephyr_gpio_set(int32_t pin) { return pin; }
