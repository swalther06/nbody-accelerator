#ifndef BITLEVEL_MODEL_H
#define BITLEVEL_MODEL_H

#include <stdio.h>
#include <stdint.h>
#include <math.h>

#include "newton_lut.h"
#include "definitions.h"
#include "state.h"

// Header-only (static inline) so both bitlevel_model.c and gen_st_init.c can
// share the exact same bit-exact rsqrt/force/seeding path -- gen_st_init.c
// used to seed accelerations with simplified double-precision gravity, which
// is close enough for well-behaved orbits but drifts from the bit-exact
// result by a couple ULPs; for a chaotic config that tiny seed mismatch gets
// amplified into a completely different trajectory after ~100 steps.

static void inline init_state(State *state) {
    for (int i = 0; i < N; i++) {
        state->rx[i] = 0;
        state->ry[i] = 0;
        state->rz[i] = 0;
        state->vx[i] = 0;
        state->vy[i] = 0;
        state->vz[i] = 0;
        state->ax[i] = 0;
        state->ay[i] = 0;
        state->az[i] = 0;
        state->m[i] = 0;
    }
}

// One Newton-Raphson step for inverse sqrt:  y' = y * (1.5 - 0.5 * a * y^2)
// a and y are both in Q(SEED_FRAC). For convergence, a*y^2 must be ~1.0,
// which requires `a` to be in the SAME normalized domain the seed approximates.
static inline int64_t rsqrt_newton_step(int64_t a, int64_t y) {
    int64_t y2   = (y * y)  >> SEED_FRAC;          // Q(F)
    int64_t ay2  = (a * y2) >> SEED_FRAC;          // Q(F), ~1.0
    int64_t term = ( (int64_t)3 << (SEED_FRAC-1) ) - (ay2 >> 1);  // 1.5 - 0.5*a*y^2, Q(F)
    return (y * term) >> SEED_FRAC;                // Q(F)
}

static inline int msb_position(int64_t x) {
    for (int i = 63; i >= 0; --i)
        if (x & (1LL << i)) return i;
    return -1;                                   // x == 0
}

// Returns rsqrt(x) in Q(SEED_FRAC).  x is Q(DENOM_FRAC).
// Newton refines in the NORMALIZED domain (a in [1,4)) so it always converges.
static inline int64_t fixed_rsqrt(int64_t x) {
    int msb = msb_position(x);
    if (msb < 0) return 0;                          // x == 0 (shouldn't happen w/ softening)

    int k      = msb - REF;
    int parity = k & 1;                             // 0 -> [1,2), 1 -> [2,4)
    int k_even = k - parity;                        // always even

    // --- table index: K mantissa bits below MSB, plus parity (octave) bit ---
    int shift = msb - NEWTON_LUT_BITS;
    int64_t mantissa = (shift >= 0)
        ? (x >> shift)     & ((1LL << NEWTON_LUT_BITS) - 1)
        : (x << (-shift))  & ((1LL << NEWTON_LUT_BITS) - 1);
    int index = ((int)parity << NEWTON_LUT_BITS) | (int)mantissa;

    int64_t y = NEWTON_LUT[index];                  // seed = rsqrt(normalized), Q(SEED_FRAC)

    // --- normalized value of x, in Q(SEED_FRAC), in [1,4): a = x / 2^k_even ---
    // a_Q = x >> ((DENOM_FRAC - SEED_FRAC) + k_even)
    int norm_shift = (DENOM_FRAC - SEED_FRAC) + k_even;
    int64_t a = (norm_shift >= 0) ? (x >> norm_shift) : (x << (-norm_shift));

    // --- Newton in normalized domain: a in [1,4) => a*y^2 ~ 1 => guaranteed convergence ---
    for (int i = 0; i < NEWTON_ITERS; ++i)
        y = rsqrt_newton_step(a, y);

    // --- magnitude correction: rsqrt(x) = rsqrt(a) * 2^(-k_even/2) ---
    int half = k_even >> 1;
    return (half >= 0) ? (y >> half) : (y << (-half));
}

static void inline calc_scaled_gravitational_acceleration(
    const int32_t x_i, const int32_t y_i, const int32_t z_i,
    const int32_t x_j, const int32_t y_j, const int32_t z_j, const int32_t m_j,
    int32_t* ax, int32_t* ay, int32_t* az) {

        int64_t dx = (int64_t)x_j - (int64_t)x_i;
        int64_t dy = (int64_t)y_j - (int64_t)y_i;
        int64_t dz = (int64_t)z_j - (int64_t)z_i;

        int64_t denom = dx*dx + dy*dy + dz*dz + EPS_SQUARED;

        int64_t inv_sqrt = fixed_rsqrt(denom);
        int64_t inv_sqrt_2 = (inv_sqrt * inv_sqrt) >> SEED_FRAC;
        int64_t inv_sqrt_3 = (inv_sqrt_2 * inv_sqrt) >> SEED_FRAC;

        int64_t mdx = ((int64_t)m_j * dx) >> FRAC_BITS;  // Q20
        int64_t mdy = ((int64_t)m_j * dy) >> FRAC_BITS;
        int64_t mdz = ((int64_t)m_j * dz) >> FRAC_BITS;

        *ax = (int32_t)((mdx * inv_sqrt_3) >> SEED_FRAC);
        *ay = (int32_t)((mdy * inv_sqrt_3) >> SEED_FRAC);
        *az = (int32_t)((mdz * inv_sqrt_3) >> SEED_FRAC);
}

static void inline accumulate_accelerations(State *state, int32_t* ax_tot, int32_t* ay_tot, int32_t* az_tot) {
    for (int i = 0; i < N; ++i) {
        *ax_tot += state->ax[i];
        *ay_tot += state->ay[i];
        *az_tot += state->az[i];
    }
}

static inline void calculate_particle_acceleration(int i, State* st,
    int32_t* ax_reg, int32_t* ay_reg, int32_t* az_reg) {

        int num_cycles = ceil(1.0 * N / WIDTH);
        for (int cycles = 0; cycles < num_cycles; ++cycles) {
            State t;
            init_state(&t);

            int jump = cycles*WIDTH;
            for (int j = 0; j < WIDTH && (jump + j) < N; ++j) {
                calc_scaled_gravitational_acceleration(st->rx[i], st->ry[i], st->rz[i],
                    st->rx[jump + j], st->ry[jump + j], st->rz[jump + j], st->m[jump + j],
                    &t.ax[jump + j], &t.ay[jump + j], &t.az[jump + j]);
            }

            int32_t ax = 0, ay = 0, az = 0;
            accumulate_accelerations(&t, &ax, &ay, &az);

            *ax_reg += ax;
            *ay_reg += ay;
            *az_reg += az;
        }
}

static inline void seed_accelerations(State* state) {
    for (int i = 0; i < N; ++i) {
        int32_t ax_reg = 0, ay_reg = 0, az_reg = 0;
        calculate_particle_acceleration(i, state, &ax_reg, &ay_reg, &az_reg);
        state->ax[i] = ax_reg;
        state->ay[i] = ay_reg;
        state->az[i] = az_reg;
    }
}

#endif // BITLEVEL_MODEL_H