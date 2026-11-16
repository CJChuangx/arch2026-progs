#include "gcd.h"

static uint32_t ctz_u32(uint32_t x)
{
    uint32_t n = 0;

    while ((x & 1u) == 0u) {
        x >>= 1;
        n++;
    }

    return n;
}

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;

    if (b == 0)
        return a;

    /* Common power of two. */
    uint32_t shift = ctz_u32(a | b);

    /* Make a odd. */
    a >>= ctz_u32(a);

    while (b != 0) {
        /* Make b odd. */
        b >>= ctz_u32(b);

        /* Keep the smaller odd value in a. */
        if (a > b) {
            uint32_t tmp = a;
            a = b;
            b = tmp;
        }

        b -= a;
    }

    return a << shift;
}
