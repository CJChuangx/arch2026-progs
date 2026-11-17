# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    # exponent = (f32bits >> 23) & 0xff
    srli    t0, a0, 23
    andi    t0, t0, 0xff

    li      t1, 0xff
    bne     t0, t1, .Lf32_normal

    # Inf / NaN: upper 16 bits unchanged.
    srli    a0, a0, 16
    ret

.Lf32_normal:
    # bias = 0x7fff + bit16
    srli    t0, a0, 16
    andi    t0, t0, 1

    li      t1, 0x7fff
    add     t1, t1, t0

    add     a0, a0, t1
    srli    a0, a0, 16

    ret

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm


# ------------------------------------------------------------
# bf16_mul_asm
# ------------------------------------------------------------

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2

bf16_mul_asm:
    # Ensure uint16 values.
    slli    a0, a0, 16
    srli    a0, a0, 16

    slli    a1, a1, 16
    srli    a1, a1, 16

    # a2 = product sign (0 or 0x8000)
    xor     a2, a0, a1
    srli    a2, a2, 15
    slli    a2, a2, 15

    # exp_a
    srli    t1, a0, 7
    andi    t1, t1, 0xff

    # frac_a
    andi    t2, a0, 0x7f

    li      a3, 0xff
    bne     t1, a3, .Lmul_check_b_special

    # a is NaN -> return a unchanged.
    bnez    t2, .Lmul_return_a

    # a is Inf.  Check whether b is zero ignoring sign.
    slli    a3, a1, 17
    beqz    a3, .Lmul_qnan

    # Inf wins even if b is NaN.
    li      a0, 0x7f80
    or      a0, a0, a2
    ret


.Lmul_check_b_special:
    # exp_b
    srli    t3, a1, 7
    andi    t3, t3, 0xff

    # frac_b
    andi    t4, a1, 0x7f

    li      a3, 0xff
    bne     t3, a3, .Lmul_finite

    # b is NaN -> return b unchanged.
    bnez    t4, .Lmul_return_b

    # b is Inf. Check whether a is zero ignoring sign.
    slli    a3, a0, 17
    beqz    a3, .Lmul_qnan

    li      a0, 0x7f80
    or      a0, a0, a2
    ret


.Lmul_finite:
    # Either finite operand equal to zero?
    slli    a3, a0, 17
    beqz    a3, .Lmul_signed_zero

    slli    a3, a1, 17
    beqz    a3, .Lmul_signed_zero


    # --------------------------------------------------------
    # Normalize a.
    #
    # t1 = effective exponent
    # t2 = 8-bit normalized significand
    # --------------------------------------------------------

    bnez    t1, .Lmul_a_normal

    li      t1, 1

.Lmul_norm_a:
    andi    a3, t2, 0x80
    bnez    a3, .Lmul_a_ready

    slli    t2, t2, 1
    addi    t1, t1, -1
    j       .Lmul_norm_a

.Lmul_a_normal:
    ori     t2, t2, 0x80

.Lmul_a_ready:


    # --------------------------------------------------------
    # Normalize b.
    #
    # t3 = effective exponent
    # t4 = normalized significand
    # --------------------------------------------------------

    bnez    t3, .Lmul_b_normal

    li      t3, 1

.Lmul_norm_b:
    andi    a3, t4, 0x80
    bnez    a3, .Lmul_b_ready

    slli    t4, t4, 1
    addi    t3, t3, -1
    j       .Lmul_norm_b

.Lmul_b_normal:
    ori     t4, t4, 0x80

.Lmul_b_ready:


    # --------------------------------------------------------
    # 8 x 8 shift-and-add multiplication.
    #
    # a3 = product
    # a4 = multiplicand
    # a5 = multiplier
    # --------------------------------------------------------

    li      a3, 0
    mv      a4, t2
    mv      a5, t4

.Lmul_product_loop:
    andi    a6, a5, 1
    beqz    a6, .Lmul_product_skip

    add     a3, a3, a4

.Lmul_product_skip:
    slli    a4, a4, 1
    srli    a5, a5, 1
    bnez    a5, .Lmul_product_loop


    # result exponent = exp_a + exp_b - 127
    add     t1, t1, t3
    addi    t1, t1, -127

    # Product bit 15 determines normalization.
    srli    a5, a3, 15
    beqz    a5, .Lmul_product_low

    srli    a4, a3, 8
    addi    t1, t1, 1
    j       .Lmul_exp_check

.Lmul_product_low:
    srli    a4, a3, 7


.Lmul_exp_check:
    # exponent >= 255 -> Inf
    li      a5, 255
    bge     t1, a5, .Lmul_inf

    # exponent > 0 -> normal
    bgtz    t1, .Lmul_normal_result


    # --------------------------------------------------------
    # Denormal result.
    # exponent < -6 -> signed zero
    # --------------------------------------------------------

    li      a5, -6
    blt     t1, a5, .Lmul_signed_zero

    # shift = 1 - exponent
    li      a5, 1
    sub     a5, a5, t1

    # Denormal uses only the 7-bit fraction.
    andi    a4, a4, 0x7f
    srl     a4, a4, a5

    or      a0, a2, a4
    ret

.Lmul_normal_result:
    andi    a4, a4, 0x7f

    slli    t1, t1, 7

    or      a0, a2, t1
    or      a0, a0, a4

    ret


.Lmul_inf:
    li      a0, 0x7f80
    or      a0, a0, a2
    ret


.Lmul_signed_zero:
    mv      a0, a2
    ret


.Lmul_qnan:
    li      a0, 0x7fc0
    ret


.Lmul_return_a:
    ret


.Lmul_return_b:
    mv      a0, a1
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm


# ------------------------------------------------------------
# bf16_sqrt_asm
# ------------------------------------------------------------

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

bf16_sqrt_asm:
    # Keep only 16 bits.
    slli    a0, a0, 16
    srli    a0, a0, 16

    # exponent
    srli    t0, a0, 7
    andi    t0, t0, 0xff

    # fraction
    andi    t1, a0, 0x7f

    # --------------------------------------------------------
    # Inf / NaN
    # --------------------------------------------------------

    li      a1, 0xff
    bne     t0, a1, .Lsqrt_not_special

    # NaN: unchanged
    bnez    t1, .Lsqrt_return

    # +Inf: unchanged
    srli    a1, a0, 15
    beqz    a1, .Lsqrt_return

    # -Inf -> qNaN
    j       .Lsqrt_qnan


.Lsqrt_not_special:
    # zero including -0 -> +0
    slli    a1, a0, 17
    beqz    a1, .Lsqrt_zero

    # negative nonzero -> qNaN
    srli    a1, a0, 15
    bnez    a1, .Lsqrt_qnan

    # denormal -> +0
    beqz    t0, .Lsqrt_zero


    # --------------------------------------------------------
    # Positive normal.
    #
    # t1 = significand
    # t2 = unbiased exponent
    # --------------------------------------------------------

    ori     t1, t1, 0x80
    addi    t2, t0, -127

    # If exponent is odd, double significand and decrement e.
    andi    a1, t2, 1
    beqz    a1, .Lsqrt_even_exp

    slli    t1, t1, 1
    addi    t2, t2, -1

.Lsqrt_even_exp:
    # result exponent = e / 2 + 127
    srai    t2, t2, 1
    addi    t2, t2, 127


    # --------------------------------------------------------
    # Binary search mid in [90, 256].
    #
    # t3 = lo
    # t4 = hi
    # t5 = best
    # t6 = mid
    # --------------------------------------------------------

    li      t3, 90
    li      t4, 256
    li      t5, 90

.Lsqrt_search:
    bgt     t3, t4, .Lsqrt_search_done

    add     t6, t3, t4
    srli    t6, t6, 1


    # --------------------------------------------------------
    # Compute mid * mid using shift-and-add.
    #
    # a1 = multiplicand
    # a2 = multiplier
    # a3 = product
    # --------------------------------------------------------

    mv      a1, t6
    mv      a2, t6
    li      a3, 0

.Lsqrt_square_loop:
    andi    a4, a2, 1
    beqz    a4, .Lsqrt_square_skip

    add     a3, a3, a1

.Lsqrt_square_skip:
    slli    a1, a1, 1
    srli    a2, a2, 1

    bnez    a2, .Lsqrt_square_loop

    # floor(mid * mid / 128)
    srli    a3, a3, 7

    # If value <= significand, mid is acceptable.
    bgt     a3, t1, .Lsqrt_too_large

    mv      t5, t6
    addi    t3, t6, 1
    j       .Lsqrt_search


.Lsqrt_too_large:
    addi    t4, t6, -1
    j       .Lsqrt_search


.Lsqrt_search_done:
    # --------------------------------------------------------
    # Renormalize result significand into [128, 256).
    # --------------------------------------------------------

    li      a1, 128
    bge     t5, a1, .Lsqrt_check_high

    slli    t5, t5, 1
    addi    t2, t2, -1

.Lsqrt_check_high:
    li      a1, 256
    blt     t5, a1, .Lsqrt_exp_check

    srli    t5, t5, 1
    addi    t2, t2, 1


.Lsqrt_exp_check:
    li      a1, 255
    bge     t2, a1, .Lsqrt_inf

    blez    t2, .Lsqrt_zero

    andi    t5, t5, 0x7f
    slli    t2, t2, 7

    or      a0, t2, t5
    ret


.Lsqrt_inf:
    li      a0, 0x7f80
    ret


.Lsqrt_qnan:
    li      a0, 0x7fc0
    ret


.Lsqrt_zero:
    li      a0, 0
    ret


.Lsqrt_return:
    ret

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
