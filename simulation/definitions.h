#ifndef DEFINITIONS_H
#define DEFINITIONS_H

#include <stdio.h>
#include <stdint.h>
#include <math.h>


// N-bodies
#define N 10

#define WIDTH 4

// Fixed-point arithmetic
#define FRAC_BITS 20u
#define FRAC_SCALE (1LL << FRAC_BITS)
#define SEED_FRAC 28u
#define DENOM_FRAC (2 * FRAC_BITS)   // = 40

// Small value to avoid division by zero
#define EPS_SQUARED ((int64_t)(1e-6 * (double)(1LL << DENOM_FRAC)))

// Lookup table for Newton's method
#define NEWTON_LUT_BITS 4
#define NEWTON_LUT_SIZE (2 << NEWTON_LUT_BITS)


#define REF (FRAC_BITS << 1)

#define NEWTON_ITERS 2





#endif // DEFINITIONS_H