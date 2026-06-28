`include "defs.svh"

module rsqrt_newton_step(
    input dword_t a,
    input dword_t y,

    output dword_t step
);

    dword_t y2, ay2, term;
    always_comb begin
        y2   = (y * y)  >> `SEEDFRAC;          // Q(F)
        ay2  = (a * y2) >> `SEEDFRAC;          // Q(F), ~1.0
        term = (3 << (`SEEDFRAC-1)) - (ay2 >> 1);  // 1.5 - 0.5*a*y^2, Q(F)
    end

    assign step = (y * term) >> `SEEDFRAC;

endmodule
