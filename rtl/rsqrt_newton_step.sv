`include "defs.svh"

// total module latency = 3 * 6 = 18
module rsqrt_newton_step(
    input clk,
    input rst,
    input dword_t a,
    input dword_t y,

    output dword_t step_out
);
    localparam MULT_LATENCY = 6; // 6 cycles per 64 bit mult
    
    dword_t [2*MULT_LATENCY-1:0] y_reg; 
    dword_t [MULT_LATENCY-1:0] a_reg;

    dword_t y2;
    qword_t y2_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) y2_multiplier (
        .clk,
        .rst,
        .m(y),
        .q(y),
        .p(y2_unshifted)
    );
    assign y2 = dword_t'(y2_unshifted >>> `SEEDFRAC);          // Q(F)


    dword_t ay2;
    qword_t ay2_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) ay2_multiplier (
        .clk,
        .rst,
        .m(a_reg[MULT_LATENCY-1]),
        .q(y2),
        .p(ay2_unshifted)
    );
    assign ay2  = dword_t'(ay2_unshifted >>> `SEEDFRAC);          // Q(F), ~1.0
    

    dword_t term;
    dword_t step;
    qword_t step_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) step_multiplier (
        .clk,
        .rst,
        .m(term),
        .q(y_reg[2*MULT_LATENCY-1]),
        .p(step_unshifted)
    );
    assign term = (3 << (`SEEDFRAC-1)) - (ay2 >> 1);  // 1.5 - 0.5*a*y^2, Q(F)
    assign step = dword_t'(step_unshifted >>> `SEEDFRAC);


    always_ff @(posedge clk) begin
        if (rst) begin
            a_reg <= 0;
            y_reg <= 0;
        end else begin
            a_reg <= {a_reg[MULT_LATENCY-2:0], a};
            y_reg <= {y_reg[2*MULT_LATENCY-2:0], y};
        end
    end

    assign step_out = step;

endmodule
