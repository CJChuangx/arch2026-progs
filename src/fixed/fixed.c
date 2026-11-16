#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int count = 0;

    while (b != 0u) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        count++;
    }

    *n = count;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    /*
     * floor((a + b) / 2), without overflowing a + b.
     *
     * a & b       = bits shared by both
     * (a ^ b) / 2 = half of differing bits
     */
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua;
    uint32_t ub;
    uint32_t negative = 0;

    if (a < 0) {
        ua = 0u - (uint32_t) a;
        negative ^= 1u;
    } else {
        ua = (uint32_t) a;
    }

    if (b < 0) {
        ub = 0u - (uint32_t) b;
        negative ^= 1u;
    } else {
        ub = (uint32_t) b;
    }

    /*
     * 64-bit product represented as:
     *
     *     hi : lo
     *
     * No uint64_t multiplication is used.
     */
    uint32_t lo = 0;
    uint32_t hi = 0;

    uint32_t mlo = ua;
    uint32_t mhi = 0;
    uint32_t multiplier = ub;

    while (multiplier != 0u) {
        if ((multiplier & 1u) != 0u) {
            uint32_t old_lo = lo;

            lo += mlo;
            hi += mhi;

            if (lo < old_lo)
                hi++;
        }

        /* mhi:mlo <<= 1 */
        mhi = (mhi << 1) | (mlo >> 31);
        mlo <<= 1;

        multiplier >>= 1;
    }

    /*
     * Apply sign to the 64-bit pair.
     * Two's complement: ~(hi:lo) + 1.
     */
    if (negative != 0u) {
        uint32_t carry;

        lo = ~lo;
        hi = ~hi;

        carry = (lo == UINT32_MAX);
        lo += 1u;
        hi += carry;
    }
    /*
     * Add rounding bias 2^19.
     */
    hi += lo >= 0xfff80000u;
    lo += 1u << 19;

    /*
     * Low 32 bits of arithmetic (hi:lo) >> 20.
     *
     * The required low 32-bit result is:
     *
     *     (lo >> 20) | (hi << 12)
     */
    uint32_t result = (lo >> 20) | (hi << 12);

    return (int32_t) result;
}
