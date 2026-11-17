#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exp = (f32bits >> 23) & 0xffu;

    /*
     * Inf and NaN are kept by simply taking the upper 16 bits.
     */
    if (exp == 0xffu)
        return (uint16_t) (f32bits >> 16);

    /*
     * Round binary32 to BF16:
     *
     * 0x7fff + bit16 implements round-to-nearest, ties-to-even.
     */
    uint32_t bias = 0x7fffu + ((f32bits >> 16) & 1u);

    return (uint16_t) ((f32bits + bias) >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = ((uint32_t) (a ^ b)) & 0x8000u;

    uint32_t exp_a = ((uint32_t) a >> 7) & 0xffu;
    uint32_t exp_b = ((uint32_t) b >> 7) & 0xffu;

    uint32_t frac_a = (uint32_t) a & 0x7fu;
    uint32_t frac_b = (uint32_t) b & 0x7fu;

    uint32_t mag_a = (uint32_t) a & 0x7fffu;
    uint32_t mag_b = (uint32_t) b & 0x7fffu;

    /*
     * Special values must be examined in the specified order:
     * a first, then b.
     */
    if (exp_a == 0xffu) {
        if (frac_a != 0u)
            return a;

        /* a is infinity. */
        if (mag_b == 0u)
            return 0x7fc0u;

        return (uint16_t) (sign | 0x7f80u);
    }

    if (exp_b == 0xffu) {
        if (frac_b != 0u)
            return b;

        /* b is infinity. */
        if (mag_a == 0u)
            return 0x7fc0u;

        return (uint16_t) (sign | 0x7f80u);
    }

    /*
     * Zero times a finite number gives signed zero.
     */
    if (mag_a == 0u || mag_b == 0u)
        return (uint16_t) sign;

    /*
     * Convert each finite operand to:
     *
     *     significand / 128 * 2^(exp - 127)
     *
     * Normal numbers have an implicit leading 1.
     * Denormals are normalized manually.
     */
    uint32_t sig_a;
    uint32_t sig_b;
    int32_t e_a;
    int32_t e_b;

    if (exp_a != 0u) {
        sig_a = 0x80u | frac_a;
        e_a = (int32_t) exp_a;
    } else {
        sig_a = frac_a;
        e_a = 1;

        while ((sig_a & 0x80u) == 0u) {
            sig_a <<= 1;
            e_a--;
        }
    }

    if (exp_b != 0u) {
        sig_b = 0x80u | frac_b;
        e_b = (int32_t) exp_b;
    } else {
        sig_b = frac_b;
        e_b = 1;

        while ((sig_b & 0x80u) == 0u) {
            sig_b <<= 1;
            e_b--;
        }
    }

    /*
     * 8-bit x 8-bit significand multiplication.
     *
     * __mulsi3 is explicitly permitted by the assignment.
     */
    uint32_t product = sig_a * sig_b;

    int32_t result_exp = e_a + e_b - 127;
    uint32_t result_sig;

    /*
     * sig_a and sig_b are in [128, 255].
     *
     * If bit 15 is set, product is >= 2.0 and needs one additional
     * normalization step.
     *
     * Fraction is deliberately truncated, not rounded.
     */
    if ((product & 0x8000u) != 0u) {
        result_sig = product >> 8;
        result_exp++;
    } else {
        result_sig = product >> 7;
    }

    if (result_exp >= 0xff)
        return (uint16_t) (sign | 0x7f80u);

    /*
     * Denormal result.
     *
     * result_exp == 0  -> shift by 1
     * result_exp == -1 -> shift by 2
     * ...
     * result_exp == -6 -> shift by 7
     */
    if (result_exp <= 0) {
        if (result_exp < -6)
            return (uint16_t) sign;

        uint32_t shift = (uint32_t) (1 - result_exp);

        /*
         * The assignment's BF16 model shifts only the 7-bit fraction
         * when producing a denormal. The implicit leading one is not
         * carried into the denormal result.
         */
        uint32_t result_frac = result_sig & 0x7fu;

        result_frac >>= shift;

        return (uint16_t) (sign | result_frac);
    }

    return (uint16_t) (sign | ((uint32_t) result_exp << 7) |
                       (result_sig & 0x7fu));
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t sign = (uint32_t) a & 0x8000u;
    uint32_t exp = ((uint32_t) a >> 7) & 0xffu;
    uint32_t frac = (uint32_t) a & 0x7fu;
    uint32_t mag = (uint32_t) a & 0x7fffu;

    /*
     * NaN and infinity.
     */
    if (exp == 0xffu) {
        if (frac != 0u)
            return a;

        if (sign == 0u)
            return a; /* +Inf */

        return 0x7fc0u; /* -Inf */
    }

    /*
     * Both +0 and -0 become +0.
     */
    if (mag == 0u)
        return 0u;

    /*
     * Negative nonzero.
     */
    if (sign != 0u)
        return 0x7fc0u;

    /*
     * Assignment specifies that denormals sqrt to +0.
     */
    if (exp == 0u)
        return 0u;

    uint32_t sig = 0x80u | frac;
    int32_t e = (int32_t) exp - 127;

    /*
     * Make an odd exponent even:
     *
     * 2^e * m = 2^(e-1) * (2m)
     */
    if ((e & 1) != 0) {
        sig <<= 1;
        e--;
    }

    int32_t result_exp = (e / 2) + 127;

    /*
     * Find the largest mid in [90, 256] satisfying:
     *
     *     floor(mid * mid / 128) <= sig
     *
     * Binary search keeps this much cheaper than a linear scan.
     */
    uint32_t lo = 90;
    uint32_t hi = 256;
    uint32_t best = 90;

    while (lo <= hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t square_scaled = (mid * mid) >> 7;

        if (square_scaled <= sig) {
            best = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }

    /*
     * Renormalize into [128, 256).
     */
    if (best < 128u) {
        best <<= 1;
        result_exp--;
    } else if (best >= 256u) {
        best >>= 1;
        result_exp++;
    }

    if (result_exp >= 0xff)
        return 0x7f80u;

    if (result_exp <= 0)
        return 0u;

    return (uint16_t) (((uint32_t) result_exp << 7) | (best & 0x7fu));
}
