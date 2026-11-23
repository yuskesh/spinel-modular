/* tools/bare-full: the __atomic_* calls for ARMv6-M (Cortex-M0+).
 *
 * ARMv6-M has no exclusive loads and stores, so clang turns the runtime's
 * atomic operations into calls to __atomic_<op>_<size>, which nothing on the
 * target supplies (compiler-rt's bare-metal builtins leave them out). Here
 * each one runs with interrupts masked (PRIMASK saved and restored). That is
 * atomic only on one core: the program runs on core 0 alone, and the only
 * interrupt is SysTick, which touches nothing these protect. Defined only on
 * ARMv6-M; elsewhere the compiler inlines the instructions.
 */
#if defined(__ARM_ARCH_6M__)
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

static inline uint32_t bf_irq_save(void)
{
	uint32_t m;

	__asm volatile("mrs %0, primask\n" "cpsid i" : "=r"(m) : : "memory");
	return m;
}

static inline void bf_irq_restore(uint32_t m)
{
	__asm volatile("msr primask, %0" : : "r"(m) : "memory");
}

/* The names are the compiler's own builtins, so they are given by asm label. */
#define BF_ATOMIC(N, T)                                                                        \
	T bf_load_##N(const volatile void *p, int mo) __asm__("__atomic_load_" #N);             \
	T bf_load_##N(const volatile void *p, int mo)                                         \
	{                                                                                      \
		uint32_t m = bf_irq_save();                                                    \
		T v = *(const volatile T *)p;                                                  \
		(void)mo;                                                                      \
		bf_irq_restore(m);                                                             \
		return v;                                                                      \
	}                                                                                      \
	void bf_store_##N(volatile void *p, T v, int mo) __asm__("__atomic_store_" #N);         \
	void bf_store_##N(volatile void *p, T v, int mo)                                      \
	{                                                                                      \
		uint32_t m = bf_irq_save();                                                    \
		*(volatile T *)p = v;                                                          \
		(void)mo;                                                                      \
		bf_irq_restore(m);                                                             \
	}                                                                                      \
	T bf_exchange_##N(volatile void *p, T v, int mo) __asm__("__atomic_exchange_" #N);      \
	T bf_exchange_##N(volatile void *p, T v, int mo)                                      \
	{                                                                                      \
		uint32_t m = bf_irq_save();                                                    \
		T old = *(volatile T *)p;                                                      \
		*(volatile T *)p = v;                                                          \
		(void)mo;                                                                      \
		bf_irq_restore(m);                                                             \
		return old;                                                                    \
	}                                                                                      \
	bool bf_cas_##N(volatile void *p, void *exp, T des, bool weak, int s, int f)          \
		__asm__("__atomic_compare_exchange_" #N);                                     \
	bool bf_cas_##N(volatile void *p, void *exp, T des, bool weak, int s, int f)          \
	{                                                                                      \
		uint32_t m = bf_irq_save();                                                    \
		T cur = *(volatile T *)p;                                                      \
		bool ok = memcmp(&cur, exp, sizeof(T)) == 0;                                   \
		if (ok)                                                                        \
			*(volatile T *)p = des;                                                \
		else                                                                           \
			memcpy(exp, &cur, sizeof(T));                                          \
		(void)weak;                                                                    \
		(void)s;                                                                       \
		(void)f;                                                                       \
		bf_irq_restore(m);                                                             \
		return ok;                                                                     \
	}                                                                                      \
	BF_FETCH(N, T, add, +)                                                                 \
	BF_FETCH(N, T, sub, -)                                                                 \
	BF_FETCH(N, T, and, &)                                                                 \
	BF_FETCH(N, T, or, |)                                                                  \
	BF_FETCH(N, T, xor, ^)

#define BF_FETCH(N, T, OP, SYM)                                                                \
	T bf_fetch_##OP##_##N(volatile void *p, T v, int mo) __asm__("__atomic_fetch_" #OP "_" #N); \
	T bf_fetch_##OP##_##N(volatile void *p, T v, int mo)                                  \
	{                                                                                      \
		uint32_t m = bf_irq_save();                                                    \
		T old = *(volatile T *)p;                                                      \
		*(volatile T *)p = (T)(old SYM v);                                             \
		(void)mo;                                                                      \
		bf_irq_restore(m);                                                             \
		return old;                                                                    \
	}

BF_ATOMIC(1, uint8_t)
BF_ATOMIC(2, uint16_t)
BF_ATOMIC(4, uint32_t)
BF_ATOMIC(8, uint64_t)
#endif
