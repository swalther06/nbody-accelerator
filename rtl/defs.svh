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
`define N 10
`define NBITS $clog2(`N)

// ACCELERATION SOFTENING - prevents massive accelerations from occuring due to close proximity
`define EPS_SQUARED ((dword_t'(1) << `DENOMFRAC) / 1000000)


// PIPE PARALLELIZATION - number of bodies processed at once
`define NUMPIPES 1

// LANE PARALLELIZATION - number of accelerations calculated at once
`define NUMLANES 4

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

// latency of a single rad4_booth_reduction_multiplier instance, at WIDTH=32
// (word_t) and WIDTH=64 (dword_t) respectively -- partial_prod_reg + p_reg +
// one register per compressor tree level; the WIDTH=64 case is verified
// against simulation/multiplier_tb.sv -- update these if the multiplier's
// internal pipeline depth changes
`define WORDMULTLATENCY 5
`define DWORDMULTLATENCY 6

// rsqrt_newton_step chains 3 dword_t multiplies per Newton iteration
`define RSQRTMULTLATENCY (3*`DWORDMULTLATENCY)


// STATE STRUCT
typedef struct {
    word_t rx [`N-1:0];
    word_t ry [`N-1:0];
    word_t rz [`N-1:0];
    word_t vx [`N-1:0];
    word_t vy [`N-1:0];
    word_t vz [`N-1:0];
    word_t ax [`N-1:0];
    word_t ay [`N-1:0];
    word_t az [`N-1:0];
    word_t m [`N-1:0];
} State;

// padded to N_PAD so accelerator.sv can tile NUMPIPES-wide batches without
// the last (ragged) batch indexing past the end of the array; padding
// slots get mass 0 so they exert/feel no force
typedef struct {
    word_t rx [`N_PAD-1:0];
    word_t ry [`N_PAD-1:0];
    word_t rz [`N_PAD-1:0];
    word_t vx [`N_PAD-1:0];
    word_t vy [`N_PAD-1:0];
    word_t vz [`N_PAD-1:0];
    word_t ax [`N_PAD-1:0];
    word_t ay [`N_PAD-1:0];
    word_t az [`N_PAD-1:0];
    word_t m [`N_PAD-1:0];
} PaddedState;


`endif
