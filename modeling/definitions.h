#ifndef DEFINITIONS_H
#define DEFINITIONS_H

#include <stdio.h>
#include <stdint.h>
#include <math.h>


// N-bodies
// Guarded so the build can override it (gcc -DN=...). This MUST stay in sync
// with rtl/defs.svh's `N -- st_init.mem is written with N values per field and
// read back the same way, so a mismatch silently scrambles every field past rx
// rather than failing loudly. 'make compare N=<n>' sets both.
#ifndef N
#define N 3
#endif

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