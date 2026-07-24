`include "defs.svh"


module compressor_4_2(
    input logic x1,
    input logic x2,
    input logic x3,
    input logic x4,
    input logic ci,

    output logic co,
    output logic carry,
    output logic sum
);
    logic s;

    assign s = x1 ^ x2 ^ x3;
    assign co = (x1 & x2) | (x3 & (x1 ^ x2));

    assign sum = s ^ x4 ^ ci;
    assign carry = (s & x4) | (ci & (s ^ x4));

endmodule
