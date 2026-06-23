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

`define EPS_SQUARED dword_t'((1e-6 * (1 << `DENOMFRAC)))

// PIPE PARALLELIZATION - number of bodies processed at once
`define NUMPIPES 20

// LANE PARALLELIZATION - number of accelerations calculated at once
`define NUMLANES 4

// FIXED-POINT ARITHMETIC
`define FRACBITS 20
`define FRACSCALE 1 << `FRACBITS
`define SEEDFRAC 28
`define DENOMFRAC 2 * `FRACBITS

// NEWTON TABLE LOOKUP
`define LUTBITS 5
`define LUTSIZE (1 << `LUTBITS)

// RSQRT OPERATION
`define REF (`FRACBITS << 1)

`endif
