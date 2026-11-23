/* An extern-check control: checksum32 taking int32_t (the declaration says u32). */
#include <stdint.h>
#ifdef EXTERNS_WITH_HEADER
#include "spinel_freestanding.h"
#endif
int32_t spinel_zephyr_checksum32(int32_t v) { return v; }
