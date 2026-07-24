`include "defs.svh"

module inv_pwr_3d2_unit #(parameter ITERS = 2, parameter LATENCY = `RSQRTMULTLATENCY*ITERS + 2*`DWORDMULTLATENCY + 3) (
    input clk,
    input rst,
    input dword_t x,
    input logic restart,

    output logic valid,
    output dword_t result
);  
    localparam ITERSCYCLES = ITERS*`RSQRTMULTLATENCY;

    dword_t a_delay [ITERSCYCLES-1:0];
    word_t  half_delay [ITERSCYCLES-1:0];

    dword_t stage_out [ITERS-1:0];

    dword_t a;
    word_t half;
    dword_t guess;          // from LUT
    dword_t rsqrt_out;
    dword_t guess_final;    // fully-refined guess, tail of the chain
    logic parity;
    logic [`LUTBITS-1:0] mantissa;
    dword_t inv_pwr3_reg;


    // MSB DETERMINATION
    int msb;
    int msb_reg;
    dword_t x_reg;
    always_comb begin
        msb = -1;
        for (int i = 0; i < `DWORDBITS; i++) begin
            if (x[i]) msb = i;       // last write wins -> highest set bit
        end
    end


    // MANTISSA, A, HALF, RSQRT CALCULATION
    always_comb begin
        int k, k_even, shift;
        int norm_shift;

        k = msb_reg - `REF;
        parity = k[0];
        k_even = k - int'(parity);

        shift = msb_reg - `LUTBITS;

        mantissa =  shift >= 0
            ? `LUTBITS'((x_reg >> shift) & ((1 << `LUTBITS) - 1)) 
            : `LUTBITS'((x_reg << (-shift)) & ((1 << `LUTBITS) - 1));

        norm_shift = (`DENOMFRAC - `SEEDFRAC) + k_even;
        a = (norm_shift >= 0) ? (x_reg >> norm_shift) : (x_reg << (-norm_shift));

        half = k_even >>> 1;

        guess_final = stage_out[ITERS-1];
        rsqrt_out = (half_delay[ITERSCYCLES-1] >= 0)
            ? (guess_final >> half_delay[ITERSCYCLES-1])
            : (guess_final << (-half_delay[ITERSCYCLES-1]));
    end


    // CUBE RSQRT CALCULATION 
    dword_t inv_pwr, inv_pwr2, inv_pwr3;
    dword_t rsqrt_out_reg;
    dword_t [`DWORDMULTLATENCY-1:0] inv_pwr_delay;
    qword_t p1, p2;

    always_comb begin
        inv_pwr = rsqrt_out_reg;
        inv_pwr2 = dword_t'(p1 >> `SEEDFRAC);
        inv_pwr3 = dword_t'(p2 >> `SEEDFRAC);
    end

    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) inv_pwr2_mult (
        .clk,
        .rst,
        .m(inv_pwr),
        .q(inv_pwr),
        .p(p1)
    );

    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) inv_pwr3_mult (
        .clk,
        .rst,
        .m(inv_pwr2),
        .q(inv_pwr_delay[`DWORDMULTLATENCY-1]),
        .p(p2)
    );

    always_ff @(posedge clk) begin
        if (rst) inv_pwr_delay <= '0;
        else inv_pwr_delay <= {inv_pwr_delay[`DWORDMULTLATENCY-2:0], inv_pwr};
    end

    // REGISTER UPDATE
    logic [$clog2(LATENCY+1)-1:0] fill_ctr;
    always_ff @(posedge clk) begin
        if (rst | restart) fill_ctr <= 0;
        else if (fill_ctr < LATENCY[$clog2(LATENCY+1)-1:0]) fill_ctr <= fill_ctr + 1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            a_delay <= '{default: '0};
            half_delay <= '{default: '0};
            msb_reg <= 0;
            x_reg <= 0;
            inv_pwr3_reg <= 0;
            rsqrt_out_reg <= 0;

        end else begin
            msb_reg <= msb;
            x_reg <= x;
            inv_pwr3_reg <= inv_pwr3;
            rsqrt_out_reg <= rsqrt_out;

            a_delay[0]    <= a;
            half_delay[0] <= half;
            for (int i = 1; i < ITERSCYCLES; i++) begin
                a_delay[i]    <= a_delay[i-1];
                half_delay[i] <= half_delay[i-1];
            end
        end
    end

    genvar k;
    generate
        for (k = 0; k < ITERS; k++) begin : newton_stage
            dword_t y_in, a_in;
            if (k == 0) begin : head
                assign y_in = guess;   // LUT seed
                assign a_in = a;       // aligned in-cycle with guess
            end else begin : tail
                assign y_in = stage_out[k-1];  // previous refined guess
                assign a_in = a_delay[`RSQRTMULTLATENCY*k-1];  // a delayed to match (18 cyc/stage)
            end

            rsqrt_newton_step rns (
                .clk,
                .rst,
                .a(a_in),
                .y(y_in),
                .step_out(stage_out[k])
            );
        end
    endgenerate

    // MODULE DECLARATIONS
    newton_lut lookup(
        .mantissa(mantissa),
        .parity(parity),

        .val(guess)
    );

    // OUTPUT ASSIGNMENTS
    assign valid = (fill_ctr == LATENCY[$clog2(LATENCY+1)-1:0]);
    assign result = inv_pwr3_reg;
    

endmodule
