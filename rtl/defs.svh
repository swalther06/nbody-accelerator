`ifndef DEFS_SVH
`define DEFS_SVH

// WORD SIZE
`define WORDBITS 32
`define DWORDBITS 2*`WORDBITS

// WORD TYPE DEFINITIONS
typedef logic signed [`WORDBITS-1:0] word_t;
typedef logic signed [`DWORDBITS-1:0] dword_t;

// NUMBER OF BODIES 
`define N 10
`define NBITS $clog2(`N)

`define EPS_SQUARED dword_t'((1e-6 * (`DWORDBITS'd1 << `DENOMFRAC)))

// PIPE PARALLELIZATION - number of bodies processed at once
`define NUMPIPES 20

// LANE PARALLELIZATION - number of accelerations calculated at once
`define NUMLANES 4

// FIXED-POINT ARITHMETIC
`define FRACBITS 20
`define FRACSCALE (1 << `FRACBITS)
`define SEEDFRAC 28
`define DENOMFRAC 2 * `FRACBITS

`define NEWTONITERS 2

// NEWTON TABLE LOOKUP
`define LUTBITS 4
`define LUTSIZE (1 << `LUTBITS)

`define MANTBITS = 4

// RSQRT OPERATION
`define REF (`FRACBITS << 1)


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


`endif
