#include "rubik.h"

#include <stdint.h>

enum { CUBIES = 7, PERMUTATIONS = 5040, ORIENTATIONS = 729, MAX_DEPTH = 11 };

typedef struct {
    uint8_t p[CUBIES];
    uint8_t o[CUBIES];
} state_t;

typedef struct {
    uint16_t p;
    uint16_t o;
    uint8_t depth;
    uint8_t next_face;
    uint8_t next_turn;
    int8_t previous_face;
} frame_t;

extern const uint16_t rubik_c_permutation_table[3 * PERMUTATIONS];
extern const uint16_t rubik_c_orientation_table[3 * ORIENTATIONS];
extern const uint8_t rubik_c_permutation_distance[PERMUTATIONS];
extern const uint8_t rubik_c_orientation_distance[ORIENTATIONS];

static frame_t stack[MAX_DEPTH + 1];
static uint8_t path[MAX_DEPTH];

static uint32_t mul_perm_factor(uint32_t p, uint8_t i)
{
    switch (i) {
    case 0:
        return (p << 3) - p;
    case 1:
        return (p << 2) + (p << 1);
    case 2:
        return (p << 2) + p;
    case 3:
        return p << 2;
    case 4:
        return (p << 1) + p;
    case 5:
        return p << 1;
    default:
        return p;
    }
}

static uint16_t rank_permutation(const state_t *state)
{
    uint32_t p = 0;

    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;

        for (uint8_t j = (uint8_t) (i + 1u); j < CUBIES; ++j) {
            if (state->p[j] < state->p[i])
                ++smaller;
        }

        p = mul_perm_factor(p, i) + smaller;
    }

    return (uint16_t) p;
}

static uint16_t rank_orientation(const state_t *state)
{
    uint16_t o = 0;

    for (uint8_t i = 0; i < 6; ++i)
        o = (uint16_t) ((o << 1) + o + state->o[i]);

    return o;
}

static int parse_state(const char *input, state_t *state)
{
    uint8_t seen = 0;
    uint8_t sum = 0;

    if (input == NULL)
        return 0;

    for (uint8_t i = 0; i < CUBIES; ++i) {
        char c = input[i];

        if (c < '1' || c > '7')
            return 0;

        uint8_t v = (uint8_t) (c - '1');
        uint8_t bit = (uint8_t) (1u << v);

        if ((seen & bit) != 0)
            return 0;

        seen = (uint8_t) (seen | bit);
        state->p[i] = v;
    }

    for (uint8_t i = 0; i < CUBIES; ++i) {
        char c = input[i + CUBIES];

        if (c < '1' || c > '3')
            return 0;

        uint8_t v = (uint8_t) (c - '1');
        state->o[i] = v;
        sum = (uint8_t) (sum + v);
    }

    if (input[RUBIK_STATE_LEN] != '\0')
        return 0;

    return sum == 0u || sum == 3u || sum == 6u || sum == 9u || sum == 12u;
}

static uint16_t perm_turn(uint8_t face, uint16_t p)
{
    return rubik_c_permutation_table[(uint32_t) face * PERMUTATIONS + p];
}

static uint16_t ori_turn(uint8_t face, uint16_t o)
{
    return rubik_c_orientation_table[(uint32_t) face * ORIENTATIONS + o];
}

static uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t hp = rubik_c_permutation_distance[p];
    uint8_t ho = rubik_c_orientation_distance[o];

    return hp > ho ? hp : ho;
}

static int dfs(uint16_t start_p, uint16_t start_o, uint8_t limit)
{
    int top = 0;

    stack[0].p = start_p;
    stack[0].o = start_o;
    stack[0].depth = 0;
    stack[0].next_face = 0;
    stack[0].next_turn = 0;
    stack[0].previous_face = -1;

    while (top >= 0) {
        frame_t *f = &stack[top];

        if (f->p == 0 && f->o == 0)
            return f->depth;

        if ((uint8_t) (f->depth + heuristic(f->p, f->o)) > limit) {
            --top;
            continue;
        }

        if (f->next_face >= 3) {
            --top;
            continue;
        }

        if (f->previous_face >= 0 &&
            f->next_face == (uint8_t) f->previous_face) {
            ++f->next_face;
            f->next_turn = 0;
            continue;
        }

        uint8_t face = f->next_face;
        uint8_t turn = f->next_turn;

        ++f->next_turn;

        if (f->next_turn >= 3) {
            f->next_turn = 0;
            ++f->next_face;
        }

        uint16_t next_p = f->p;
        uint16_t next_o = f->o;

        for (uint8_t i = 0; i <= turn; ++i) {
            next_p = perm_turn(face, next_p);
            next_o = ori_turn(face, next_o);
        }

        uint8_t child_depth = (uint8_t) (f->depth + 1u);

        path[f->depth] = (uint8_t) (face * 3u + turn);

        if (next_p == 0 && next_o == 0)
            return child_depth;

        if ((uint8_t) (child_depth + heuristic(next_p, next_o)) > limit)
            continue;

        ++top;

        stack[top].p = next_p;
        stack[top].o = next_o;
        stack[top].depth = child_depth;
        stack[top].next_face = 0;
        stack[top].next_turn = 0;
        stack[top].previous_face = (int8_t) face;
    }

    return -1;
}

static size_t move_length(uint8_t move)
{
    return move == 0u || move == 3u || move == 6u ? 1u : 2u;
}

static int write_solution(char *out, size_t cap, int depth)
{
    static const char face_char[3] = {'R', 'B', 'D'};

    size_t needed = 1;

    for (int i = 0; i < depth; ++i) {
        needed += move_length(path[i]);

        if (i + 1 < depth)
            ++needed;
    }

    if (cap < needed || (cap != 0 && out == NULL)) {
        if (cap != 0 && out != NULL)
            out[0] = '\0';

        return -2;
    }

    size_t pos = 0;

    for (int i = 0; i < depth; ++i) {
        uint8_t move = path[i];

        uint8_t face = 0;
        uint8_t turn = move;

        if (turn >= 6) {
            face = 2;
            turn = (uint8_t) (turn - 6);
        } else if (turn >= 3) {
            face = 1;
            turn = (uint8_t) (turn - 3);
        }

        out[pos++] = face_char[face];

        if (turn == 1)
            out[pos++] = '2';
        else if (turn == 2)
            out[pos++] = '\'';

        if (i + 1 < depth)
            out[pos++] = ' ';
    }

    out[pos] = '\0';
    return depth;
}

int rubik_solve(const char *input, char *out, size_t cap)
{
    state_t state;

    if (!parse_state(input, &state))
        return -1;

    uint16_t p = rank_permutation(&state);
    uint16_t o = rank_orientation(&state);

    if (p == 0 && o == 0)
        return write_solution(out, cap, 0);

    uint8_t first = heuristic(p, o);

    for (uint8_t limit = first; limit <= MAX_DEPTH; ++limit) {
        int depth = dfs(p, o, limit);

        if (depth >= 0)
            return write_solution(out, cap, depth);
    }

    return -1;
}
