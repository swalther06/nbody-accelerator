`include "defs.svh"

function automatic dword_t rsqrt_newton_step(input dword_t a, input dword_t y);
    dword_t y2   = (y * y)  >> `SEEDFRAC;          // Q(F)
    dword_t ay2  = (a * y2) >> `SEEDFRAC;          // Q(F), ~1.0
    dword_t term = (3 << (`SEEDFRAC-1)) - (ay2 >> 1);  // 1.5 - 0.5*a*y^2, Q(F)
    return (y * term) >> `SEEDFRAC;                // Q(F)
endfunction

module inv_pwr_3d2(
    input clk,
    input rst,

    input dword_t x,
    output logic valid,
    output dword_t result
);

    logic [`LUTBITS-1:0] index;
    dword_t a;                    // normalized value -> needed by always_ff
    dword_t first_guess;          // from LUT
    dword_t intermediate_guess;
    dword_t refined_guess;
    dword_t rsqrt_out;

    int msb;
    always_comb begin
        msb = -1;
        for (int i = 0; i < `DWORDBITS; i++) begin
            if (x[i]) msb = i;       // last write wins -> highest set bit
        end
    end

    always_comb begin
        int k, parity, k_even, shift, half;
        logic [`LUTBITS-1:0] mantissa;
        int norm_shift;

        k = msb - `REF;
        parity = k & 1;
        k_even = k - parity;

        shift = msb - `LUTBITS;

        mantissa = (shift >= 0) ? (x >> shift) & ((1 << `LUTBITS) - 1) 
                    : (x << (-shift))  & ((1 << `LUTBITS) - 1);

        index = (parity << `LUTBITS) | mantissa;

        norm_shift = (`DENOMFRAC - `SEEDFRAC) + k_even;
        a = (norm_shift >= 0) ? (x >> norm_shift) : (x << (-norm_shift));

        half = k_even >> 1;
        rsqrt_out = (half >= 0) ? (refined_guess >> half) : (refined_guess << (-half));
    end

    dword_t inv_pwr;
    dword_t inv_pwr2;
    dword_t inv_pwr3;
    always_comb begin
        inv_pwr = rsqrt_out;
        inv_pwr2 = inv_pwr * inv_pwr;
        inv_pwr3 = inv_pwr2 * inv_pwr;
    end

    always_ff @(posedge clk) begin
        if (rst) begin 
            intermediate_guess <= 0;
            refined_guess <= 0;
        end
        intermediate_guess <= rsqrt_newton_step(a, first_guess);
        refined_guess <= rsqrt_newton_step(a, intermediate_guess);   // registered
    end

    newton_lut lookup(
        .index,
        .val(first_guess)
    );
    

    assign valid = (refined_guess != 0);
    assign result = inv_pwr3;
    

endmodule