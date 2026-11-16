# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2

gcd_u32_asm:
    # a0 = a
    # a1 = b

    # gcd(0, b) = b
    bnez    a0, .La_nonzero
    mv      a0, a1
    ret

.La_nonzero:
    # gcd(a, 0) = a
    bnez    a1, .Lb_nonzero
    ret

.Lb_nonzero:
    # t0 = shift = ctz(a | b)
    or      t1, a0, a1
    li      t0, 0

.Lcommon_ctz:
    andi    t2, t1, 1
    bnez    t2, .Lcommon_done

    srli    t1, t1, 1
    addi    t0, t0, 1
    j       .Lcommon_ctz

.Lcommon_done:
    # make a odd
.La_ctz:
    andi    t1, a0, 1
    bnez    t1, .La_odd

    srli    a0, a0, 1
    j       .La_ctz

.La_odd:
.Lloop:
    beqz    a1, .Ldone

    # make b odd
.Lb_ctz:
    andi    t1, a1, 1
    bnez    t1, .Lb_odd

    srli    a1, a1, 1
    j       .Lb_ctz

.Lb_odd:
    # if (a <= b), keep order
    bleu    a0, a1, .Lordered

    # swap a and b
    mv      t1, a0
    mv      a0, a1
    mv      a1, t1

.Lordered:
    # b = b - a
    sub     a1, a1, a0
    j       .Lloop

.Ldone:
    # restore common power of two
    sll     a0, a0, t0
    ret

    .size   gcd_u32_asm, .-gcd_u32_asm
