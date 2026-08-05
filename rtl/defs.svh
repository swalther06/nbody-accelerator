`ifndef DEFS_SVH
`define DEFS_SVH

// WORD SIZE
`define WORDBITS 32
`define DWORDBITS (2*`WORDBITS)
`define QWORDBITS (2*`DWORDBITS)

// WORD TYPE DEFINITIONS
typedef logic signed [`WORDBITS-1:0] word_t;
typedef logic signed [`DWORDBITS-1:0] dword_t;
typedef logic signed [`QWORDBITS-1:0] qword_t;

// NUMBER OF BODIES
// Guarded so the build can override it (vcs +define+N=...). This MUST stay in
// sync with modeling/definitions.h's N -- st_init.mem is written with `N values
// per field and read back the same way, so a mismatch silently scrambles every
// field past rx rather than failing loudly. 'make compare N=<n>' sets both.
`ifndef N
`define N 3
`endif
`define NBITS $clog2(`N)

// ACCELERATION SOFTENING - prevents massive accelerations from occuring due to close proximity
`define EPS_SQUARED ((dword_t'(1) << `DENOMFRAC) / 1000000)


// PIPE PARALLELIZATION - number of bodies processed at once
`define NUMPIPES 10

// LANE PARALLELIZATION - number of accelerations calculated at once
`define NUMLANES 1

// PADDING FOR N
`define N_PAD1 (((`N + `NUMPIPES - 1) / `NUMPIPES) * `NUMPIPES)
`define N_PAD (((`N_PAD1 + `NUMLANES - 1) / `NUMLANES) * `NUMLANES)

// FIXED-POINT ARITHMETIC
`define FRACBITS 20
`define FRACSCALE (1 << `FRACBITS)
`define SEEDFRAC 28
`define DENOMFRAC (2 * `FRACBITS)

`define RSHIFT_ROUND(val, shift) (((val) + (dword_t'(1) << ((shift) - 1))) >>> (shift))

`define NEWTONITERS 2

// NEWTON TABLE LOOKUP
`define LUTBITS 4
`define LUTSIZE (1 << `LUTBITS)

`define MANTBITS = 4

// RSQRT OPERATION
`define REF (`FRACBITS << 1)

`define WORDMULTLATENCY 4
`define DWORDMULTLATENCY 4

// accumulator_piplined's input->output latency: ceil(LEVELS/2) registered
// stages inside compressor_4_2_tree plus its own acc_reg, where LEVELS is
// $clog2(NUM_INPS)-1. Consumers (accel_module) must size their valid-shift
// handshake from this rather than hardcoding a depth -- it is 1 for
// NUM_INPS<=2, 2 for 4 and 8, 3 for 16. Verified against measured latency
// in simulation/acc_latency_tb.sv.
`define ACC_LATENCY(n) (((($clog2(n)-1)+1)/2) + 1)

// rsqrt_newton_step chains 3 dword_t multiplies per Newton iteration
`define RSQRTMULTLATENCY (3*`DWORDMULTLATENCY)


// STATE STRUCT
typedef struct {
    word_t [2:0] r [`N-1:0];
    word_t [2:0] v [`N-1:0];
    word_t [2:0] a [`N-1:0];
    word_t m [`N-1:0];
} State;

// padded to N_PAD so accelerator.sv can tile NUMPIPES-wide batches without
// the last (ragged) batch indexing past the end of the array; padding
// slots get mass 0 so they exert/feel no force
typedef struct {
    word_t [2:0] r [`N_PAD-1:0];
    word_t [2:0] v [`N_PAD-1:0];
    word_t [2:0] a [`N_PAD-1:0];
    word_t m [`N_PAD-1:0];
} PaddedState;


`endif
