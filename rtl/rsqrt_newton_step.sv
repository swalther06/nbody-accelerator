`include "defs.svh"

module rsqrt_newton_step(
    input clk,
    input rst,
    input dword_t a,
    input dword_t y,

    output dword_t step_out
);

    dword_t y2_reg, ay2_reg, step_reg, y_reg, y_reg_reg, a_reg;
    dword_t y2, ay2, term, step;

    always_comb begin
        y2   = dword_t'(y*y  >> `SEEDFRAC);          // Q(F)
        ay2  = dword_t'(a_reg * y2_reg >> `SEEDFRAC);          // Q(F), ~1.0
        term = (3 << (`SEEDFRAC-1)) - (ay2_reg >> 1);  // 1.5 - 0.5*a*y^2, Q(F)
        step = dword_t'(term * y_reg_reg >> `SEEDFRAC);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            a_reg <= 0;
            y2_reg <= 0;
            ay2_reg <= 0;
            step_reg <= 0;
            y_reg_reg <= 0;
            y_reg <= 0;
        end else begin
            a_reg <= a;
            y2_reg <= y2;
            ay2_reg <= ay2;
            step_reg <= step;
            y_reg_reg <= y_reg;
            y_reg <= y;
        end
    end

    assign step_out = step_reg;

endmodule
