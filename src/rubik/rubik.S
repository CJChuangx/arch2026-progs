    .section .bss
    .align 2

rubik_asm_dfs_stack:
    .zero 96

rubik_asm_stack_top:
    .word 0

rubik_asm_search_limit:
    .word 0

rubik_asm_path:
    .zero 11

    .text
    .align 2
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function

rubik_solve_asm:
    # 0..6(sp): temporary permutation digits
    # 8(sp):    output pointer
    # 12(sp):   output capacity
    # 28..76:   saved registers
    addi sp, sp, -80

    sw ra, 76(sp)
    sw s0, 72(sp)
    sw s1, 68(sp)
    sw s2, 64(sp)
    sw s3, 60(sp)
    sw s4, 56(sp)
    sw s5, 52(sp)
    sw s6, 48(sp)
    sw s7, 44(sp)
    sw s8, 40(sp)
    sw s9, 36(sp)
    sw s10, 32(sp)
    sw s11, 28(sp)

    sw a1, 8(sp)
    sw a2, 12(sp)

    beqz a0, .Linvalid

    mv s11, a0

    # ------------------------------------------------------------
    # Parse and validate permutation digits.
    # ------------------------------------------------------------
    li t0, 0              # i
    li t1, 0              # seen mask

.Lparse_perm:
    li t2, 7
    bgeu t0, t2, .Lparse_ori_start

    add t3, s11, t0
    lbu t2, 0(t3)

    li t4, '1'
    bltu t2, t4, .Linvalid

    li t4, '8'
    bgeu t2, t4, .Linvalid

    addi t2, t2, -'1'

    li t4, 1
    sll t4, t4, t2

    and t5, t1, t4
    bnez t5, .Linvalid

    or t1, t1, t4

    add t3, sp, t0
    sb t2, 0(t3)

    addi t0, t0, 1
    j .Lparse_perm

    # ------------------------------------------------------------
    # Parse orientations and construct orientation rank.
    # ------------------------------------------------------------
.Lparse_ori_start:
    li t0, 0              # i
    li t1, 0              # orientation sum
    li s1, 0              # orientation rank

.Lparse_ori:
    li t2, 7
    bgeu t0, t2, .Lparse_done

    addi t3, s11, 7
    add t3, t3, t0
    lbu t2, 0(t3)

    li t4, '1'
    bltu t2, t4, .Linvalid

    li t4, '4'
    bgeu t2, t4, .Linvalid

    addi t2, t2, -'1'
    add t1, t1, t2

    # Only the first six orientations form the rank.
    li t4, 6
    bgeu t0, t4, .Lori_rank_done

    slli t5, s1, 1
    add t5, t5, s1
    add s1, t5, t2

.Lori_rank_done:
    addi t0, t0, 1
    j .Lparse_ori

.Lparse_done:
    # Exactly 14 characters.
    lbu t2, 14(s11)
    bnez t2, .Linvalid

    # sum must be 0, 3, 6, 9 or 12.
    beqz t1, .Lrank_perm_start

    li t2, 3
    beq t1, t2, .Lrank_perm_start
    li t2, 6
    beq t1, t2, .Lrank_perm_start
    li t2, 9
    beq t1, t2, .Lrank_perm_start
    li t2, 12
    beq t1, t2, .Lrank_perm_start

    j .Linvalid

    # ------------------------------------------------------------
    # Permutation Lehmer rank.
    # ------------------------------------------------------------
.Lrank_perm_start:
    li t1, 0              # p
    li t2, 0              # i

.Lperm_outer:
    li t6, 7
    bgeu t2, t6, .Lperm_done

    li t3, 0              # smaller

    add t4, sp, t2
    lbu t5, 0(t4)         # permutation[i]

    addi t4, t2, 1        # j

.Lperm_inner:
    li t6, 7
    bgeu t4, t6, .Lperm_inner_done

    add t6, sp, t4
    lbu t6, 0(t6)

    bgeu t6, t5, .Lperm_not_smaller
    addi t3, t3, 1

.Lperm_not_smaller:
    addi t4, t4, 1
    j .Lperm_inner

.Lperm_inner_done:
    beqz t2, .Lfactor7

    li t6, 1
    beq t2, t6, .Lfactor6
    li t6, 2
    beq t2, t6, .Lfactor5
    li t6, 3
    beq t2, t6, .Lfactor4
    li t6, 4
    beq t2, t6, .Lfactor3
    li t6, 5
    beq t2, t6, .Lfactor2

    mv t6, t1
    j .Lrank_update

.Lfactor7:
    slli t6, t1, 3
    sub t6, t6, t1
    j .Lrank_update

.Lfactor6:
    slli t6, t1, 2
    slli t5, t1, 1
    add t6, t6, t5
    j .Lrank_update

.Lfactor5:
    slli t6, t1, 2
    add t6, t6, t1
    j .Lrank_update

.Lfactor4:
    slli t6, t1, 2
    j .Lrank_update

.Lfactor3:
    slli t6, t1, 1
    add t6, t6, t1
    j .Lrank_update

.Lfactor2:
    slli t6, t1, 1

.Lrank_update:
    add t1, t6, t3
    addi t2, t2, 1
    j .Lperm_outer

.Lperm_done:
    mv s0, t1

    # ------------------------------------------------------------
    # Initialize root DFS frame.
    # ------------------------------------------------------------
    la t0, rubik_asm_dfs_stack

    sh s0, 0(t0)
    sh s1, 2(t0)

    li t1, 0
    sb t1, 4(t0)
    sb t1, 5(t0)
    sb t1, 6(t0)

    li t1, -1
    sb t1, 7(t0)

    # Solved cube.
    bnez s0, .Lroot_not_solved
    bnez s1, .Lroot_not_solved

    li s10, 0
    j .Lfound

.Lroot_not_solved:
    # initial limit = max(permutation distance, orientation distance)

    la t2, rubik_asm_permutation_distance
    add t2, t2, s0
    lbu t3, 0(t2)

    la t2, rubik_asm_orientation_distance
    add t2, t2, s1
    lbu t4, 0(t2)

    mv t5, t3
    bgeu t3, t4, .Linitial_h_ready
    mv t5, t4

.Linitial_h_ready:
    la t2, rubik_asm_search_limit
    sw t5, 0(t2)

    la t0, rubik_asm_stack_top
    sw zero, 0(t0)

    # ------------------------------------------------------------
    # Iterative explicit-stack IDA*.
    # ------------------------------------------------------------
.Ldfs_loop:
    la t0, rubik_asm_stack_top
    lw t1, 0(t0)

    slli t2, t1, 3

    la t0, rubik_asm_dfs_stack
    add t0, t0, t2

    lhu s0, 0(t0)
    lhu s1, 2(t0)
    lbu s2, 4(t0)
    lbu s5, 5(t0)
    lbu s6, 6(t0)
    lb s7, 7(t0)

        # --------------------------------------------------------
    # If at most five moves remain, replace further DFS by an
    # exact lookup in the <=5 table.
    # --------------------------------------------------------
    la      t1, rubik_asm_search_limit
    lw      t1, 0(t1)

    sub     t2, t1, s2        # remaining = limit - depth

    li      t3, 5
    bgtu    t2, t3, .Lnormal_dfs

    # key = (p << 10) | o
    slli    a3, s0, 10
    or      a3, a3, s1

    jal     ra, .Lnear5_lookup

    li      t3, -1
    beq     a4, t3, .Lframe_exhausted

    # exact distance stored in high nibble
    srli    t3, a4, 4

    # exact distance must fit into current remaining depth
    bgtu    t3, t2, .Lframe_exhausted

    # Append the exact <=5 solution to the current prefix.
    mv      s8, t3            # moves remaining in near5 suffix
    mv      s9, s2            # destination index in path

    beqz    s8, .Lnear5_complete

.Lnear5_append:
    andi    s6, a4, 15        # move index

    la      t0, rubik_asm_path
    add     t0, t0, s9
    sb      s6, 0(t0)

    # Decode face / quarter-turn count.
    li      t2, 3
    bltu    s6, t2, .Lnear_face0

    li      t2, 6
    bltu    s6, t2, .Lnear_face1

    li      s5, 2
    addi    t2, s6, -6
    j       .Lnear_face_ready

.Lnear_face1:
    li      s5, 1
    addi    t2, s6, -3
    j       .Lnear_face_ready

.Lnear_face0:
    li      s5, 0
    mv      t2, s6

.Lnear_face_ready:
    addi    t2, t2, 1        # number of quarter turns
    li      t3, 0

.Lnear_apply:
    # table offsets for selected face
    beqz    s5, .Lnear_offsets0

    li      t4, 1
    beq     s5, t4, .Lnear_offsets1

    li      t4, 20160
    li      t5, 2916
    j       .Lnear_offsets_ready

.Lnear_offsets0:
    li      t4, 0
    li      t5, 0
    j       .Lnear_offsets_ready

.Lnear_offsets1:
    li      t4, 10080
    li      t5, 1458

.Lnear_offsets_ready:
    la      t0, rubik_asm_permutation_table
    add     t0, t0, t4
    slli    t6, s0, 1
    add     t0, t0, t6
    lhu     s0, 0(t0)

    la      t0, rubik_asm_orientation_table
    add     t0, t0, t5
    slli    t6, s1, 1
    add     t0, t0, t6
    lhu     s1, 0(t0)

    addi    t3, t3, 1
    bltu    t3, t2, .Lnear_apply

    addi    s9, s9, 1
    addi    s8, s8, -1

    beqz    s8, .Lnear5_complete

    # Find the next move toward solved.
    slli    a3, s0, 10
    or      a3, a3, s1
    jal     ra, .Lnear5_lookup

    li      t0, -1
    beq     a4, t0, .Linvalid

    j       .Lnear5_append

.Lnear5_complete:
    mv      s10, s9
    j       .Lfound

.Lnormal_dfs:

    li t1, 3
    bgeu s5, t1, .Lframe_exhausted

    # Do not use the same face twice consecutively.
    li t1, -1
    beq s7, t1, .Lsame_face_ok

    bne s5, s7, .Lsame_face_ok

    addi t1, s5, 1
    sb t1, 5(t0)
    sb zero, 6(t0)

    j .Ldfs_loop

.Lsame_face_ok:
    # Save move = face * 3 + turn at path[depth].
    slli t1, s5, 1
    add t1, t1, s5
    add t1, t1, s6

    la t2, rubik_asm_path
    add t2, t2, s2
    sb t1, 0(t2)

    # Advance parent iterator before descending.
    addi t1, s6, 1

    li t2, 3
    bltu t1, t2, .Lsave_next_turn

    sb zero, 6(t0)

    addi t2, s5, 1
    sb t2, 5(t0)

    j .Literator_done

.Lsave_next_turn:
    sb t1, 6(t0)

.Literator_done:
    # Number of quarter turns = turn + 1.
    addi s8, s6, 1
    li s9, 0

    beqz s5, .Lchild_face0

    li t6, 1
    beq s5, t6, .Lchild_face1

    # Face 2
    li t2, 20160
    li t3, 2916
    j .Lchild_transition

.Lchild_face0:
    li t2, 0
    li t3, 0
    j .Lchild_transition

.Lchild_face1:
    li t2, 10080
    li t3, 1458

.Lchild_transition:
    # permutation transition
    la t0, rubik_asm_permutation_table
    add t0, t0, t2

    slli t1, s0, 1
    add t0, t0, t1
    lhu s3, 0(t0)

    # orientation transition
    la t0, rubik_asm_orientation_table
    add t0, t0, t3

    slli t1, s1, 1
    add t0, t0, t1
    lhu s4, 0(t0)

    addi s9, s9, 1
    bgeu s9, s8, .Lchild_done

    mv s0, s3
    mv s1, s4

    j .Lchild_transition

.Lchild_done:
    # Goal test.
    bnez s3, .Lchild_not_goal
    bnez s4, .Lchild_not_goal

    addi s10, s2, 1
    j .Lfound

.Lchild_not_goal:
    # hp
    la t3, rubik_asm_permutation_distance
    add t3, t3, s3
    lbu t4, 0(t3)

    # ho
    la t3, rubik_asm_orientation_distance
    add t3, t3, s4
    lbu t5, 0(t3)

    # h = max(hp, ho)
    mv t6, t4
    bgeu t4, t5, .Lchild_h_ready
    mv t6, t5

.Lchild_h_ready:
    addi t1, s2, 1
    add t2, t1, t6

    la t3, rubik_asm_search_limit
    lw t3, 0(t3)

    bgtu t2, t3, .Ldfs_loop

    # Push child.
    la t0, rubik_asm_stack_top
    lw t1, 0(t0)

    addi t1, t1, 1
    sw t1, 0(t0)

    slli t2, t1, 3
    la t0, rubik_asm_dfs_stack
    add t0, t0, t2

    sh s3, 0(t0)
    sh s4, 2(t0)

    addi t1, s2, 1
    sb t1, 4(t0)

    sb zero, 5(t0)
    sb zero, 6(t0)

    sb s5, 7(t0)

    j .Ldfs_loop

.Lframe_exhausted:
    la t0, rubik_asm_stack_top
    lw t1, 0(t0)

    beqz t1, .Ldepth_exhausted

    addi t1, t1, -1
    sw t1, 0(t0)

    j .Ldfs_loop

.Ldepth_exhausted:
    la t0, rubik_asm_search_limit
    lw t1, 0(t0)

    addi t1, t1, 1

    li t2, 11
    bgtu t1, t2, .Linvalid

    sw t1, 0(t0)

    # Restart from the root.
    la t0, rubik_asm_stack_top
    sw zero, 0(t0)

    la t0, rubik_asm_dfs_stack
    sb zero, 5(t0)
    sb zero, 6(t0)

    j .Ldfs_loop

    # ------------------------------------------------------------
    # Convert path into "R2 D B' ..." text.
    # ------------------------------------------------------------
.Lfound:
    # Compute number of bytes required, including NUL.
    li t0, 1              # needed
    li t1, 0              # i

.Lsize_loop:
    bgeu t1, s10, .Lsize_done

    la t2, rubik_asm_path
    add t2, t2, t1
    lbu t3, 0(t2)

    # R, B, D quarter-turn names are one byte:
    # moves 0, 3, 6. All others are two.
    beqz t3, .Lone_char

    li t4, 3
    beq t3, t4, .Lone_char

    li t4, 6
    beq t3, t4, .Lone_char

    addi t0, t0, 2
    j .Lsize_space

.Lone_char:
    addi t0, t0, 1

.Lsize_space:
    addi t4, t1, 1
    bgeu t4, s10, .Lsize_next

    addi t0, t0, 1       # space

.Lsize_next:
    addi t1, t1, 1
    j .Lsize_loop

.Lsize_done:
    lw t1, 12(sp)        # cap
    bltu t1, t0, .Lbuffer_small

    lw t2, 8(sp)         # out
    beqz t2, .Lbuffer_small

    li t1, 0             # i

.Lwrite_loop:
    bgeu t1, s10, .Lwrite_done

    la t3, rubik_asm_path
    add t3, t3, t1
    lbu t4, 0(t3)        # move

    # Decode move without division.
    li t5, 3
    bltu t4, t5, .Lwrite_R

    li t5, 6
    bltu t4, t5, .Lwrite_B

    # D
    li t6, 'D'
    sb t6, 0(t2)
    addi t2, t2, 1
    addi t4, t4, -6
    j .Lwrite_suffix

.Lwrite_B:
    li t6, 'B'
    sb t6, 0(t2)
    addi t2, t2, 1
    addi t4, t4, -3
    j .Lwrite_suffix

.Lwrite_R:
    li t6, 'R'
    sb t6, 0(t2)
    addi t2, t2, 1

.Lwrite_suffix:
    beqz t4, .Lwrite_space

    li t5, 1
    bne t4, t5, .Lwrite_prime

    li t6, '2'
    sb t6, 0(t2)
    addi t2, t2, 1
    j .Lwrite_space

.Lwrite_prime:
    li t6, 39
    sb t6, 0(t2)
    addi t2, t2, 1

.Lwrite_space:
    addi t5, t1, 1
    bgeu t5, s10, .Lwrite_next

    li t6, ' '
    sb t6, 0(t2)
    addi t2, t2, 1

.Lwrite_next:
    addi t1, t1, 1
    j .Lwrite_loop

.Lwrite_done:
    sb zero, 0(t2)

    mv a0, s10
    j .Lreturn

.Lbuffer_small:
    lw t0, 12(sp)
    beqz t0, .Lbuffer_return

    lw t1, 8(sp)
    beqz t1, .Lbuffer_return

    sb zero, 0(t1)

.Lbuffer_return:
    li a0, -2
    j .Lreturn

.Linvalid:
    li a0, -1

.Lreturn:
    lw s11, 28(sp)
    lw s10, 32(sp)
    lw s9, 36(sp)
    lw s8, 40(sp)
    lw s7, 44(sp)
    lw s6, 48(sp)
    lw s5, 52(sp)
    lw s4, 56(sp)
    lw s3, 60(sp)
    lw s2, 64(sp)
    lw s1, 68(sp)
    lw s0, 72(sp)
    lw ra, 76(sp)

    addi sp, sp, 80
    ret
    
    # ------------------------------------------------------------
# near5 lookup
#
# input:
#   a3 = (permutation_rank << 10) | orientation_rank
#
# output:
#   a4 = info byte, or -1 when absent
#
# info:
#   high nibble = exact distance to solved (0..5)
#   low nibble  = first move toward solved (0..8)
# ------------------------------------------------------------
.Lnear5_lookup:
    li      t0, 0
    li      t1, 12224

.Lnear5_bs:
    bgeu    t0, t1, .Lnear5_check

    add     t2, t0, t1
    srli    t2, t2, 1

    la      t3, rubik_asm_near5_ranks
    slli    t4, t2, 2
    add     t3, t3, t4
    lw      t5, 0(t3)

    bltu    t5, a3, .Lnear5_right

    mv      t1, t2
    j       .Lnear5_bs

.Lnear5_right:
    addi    t0, t2, 1
    j       .Lnear5_bs

.Lnear5_check:
    li      t1, 12224
    bgeu    t0, t1, .Lnear5_miss

    la      t2, rubik_asm_near5_ranks
    slli    t3, t0, 2
    add     t2, t2, t3
    lw      t4, 0(t2)

    bne     t4, a3, .Lnear5_miss

    la      t2, rubik_asm_near5_info
    add     t2, t2, t0
    lbu     a4, 0(t2)
    ret

.Lnear5_miss:
    li      a4, -1
    ret
    .size rubik_solve_asm, .-rubik_solve_asm
