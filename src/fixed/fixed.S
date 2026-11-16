# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t0, 0

    # Important for op1(x, 0, n):
    # no loop pass, *n = 0.
    beqz    a1, .Lop1_done

.Lop1_loop:
    # t1 = a & b
    and     t1, a0, a1

    # a = a ^ b
    xor     a0, a0, a1

    # b = (old a & old b) << 1
    slli    a1, t1, 1

    addi    t0, t0, 1

    # Avoid an unconditional jump.
    bnez    a1, .Lop1_loop

.Lop1_done:
    sw      t0, 0(a2)
    ret

    .size   op1_asm, .-op1_asm


# ------------------------------------------------------------
# uint32_t op2_asm(uint32_t a, uint32_t b)
# ------------------------------------------------------------

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret

    .size   op2_asm, .-op2_asm


# ------------------------------------------------------------
# uint32_t op3_asm(uint32_t a, uint32_t b)
#
# (a & b) + ((a ^ b) >> 1)
# ------------------------------------------------------------

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor     t0, a0, a1
    srli    t0, t0, 1

    and     a0, a0, a1
    add     a0, a0, t0

    ret

    .size   op3_asm, .-op3_asm


# ------------------------------------------------------------
# int32_t q_mul_asm(int32_t a, int32_t b)
#
# Q11.20:
#
# result = floor((a*b + 2^19) / 2^20)
#
# t1:t0 = 64-bit product
# t3:t2 = 64-bit multiplicand
# t4    = multiplier
# t6    = sign flag
# ------------------------------------------------------------

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # a0 = a
    # a1 = b
    #
    # t1:t0 = 64-bit product
    # t3:t2 = 64-bit multiplicand
    # t4    = multiplier
    # t6    = sign

    li      t6, 0

    # abs(a)
    bgez    a0, .Lq_a_pos
    sub     a0, zero, a0
    xori    t6, t6, 1

.Lq_a_pos:
    # abs(b)
    bgez    a1, .Lq_b_pos
    sub     a1, zero, a1
    xori    t6, t6, 1

.Lq_b_pos:
    # product = 0
    li      t0, 0
    li      t1, 0

    # multiplicand = 0:a
    mv      t2, a0
    li      t3, 0

    # multiplier = b
    mv      t4, a1

    # Special case: multiplier == 0
    beqz    t4, .Lq_mul_done

.Lq_mul_loop:
    # if (multiplier & 1)
    andi    t5, t4, 1
    beqz    t5, .Lq_skip_add

    # product += multiplicand
    add     t0, t0, t2
    sltu    a3, t0, t2

    add     t1, t1, t3
    add     t1, t1, a3
.Lq_skip_add:
    # multiplicand <<= 1
    srli    t5, t2, 31
    slli    t3, t3, 1
    or      t3, t3, t5
    slli    t2, t2, 1

    # multiplier >>= 1
    srli    t4, t4, 1

    # Bottom-tested loop:
    # removes the old top beqz + unconditional j pair.
    bnez    t4, .Lq_mul_loop

.Lq_mul_done:
    # Apply sign to 64-bit product.
    beqz    t6, .Lq_sign_done

    # -(t1:t0)
    #
    # new_lo = -old_lo
    # new_hi = -old_hi - (old_lo != 0)
    sltu    a2, zero, t0
    sub     t0, zero, t0
    sub     t1, zero, t1
    sub     t1, t1, a2

.Lq_sign_done:
    # Add rounding bias: 2^19
    li      t2, 0x80000
    add     t0, t0, t2
    sltu    a3, t0, t2
    add     t1, t1, a3
    # Low 32 bits of arithmetic (t1:t0) >> 20
    #
    # Since only low 32 output bits are required:
    #   (lo >> 20) | (hi << 12)
    srli    t0, t0, 20
    slli    t1, t1, 12
    or      a0, t0, t1

    ret

    .size   q_mul_asm, .-q_mul_asm
