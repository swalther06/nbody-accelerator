`include "defs.svh"

// 2 cycle delay for registering msb
// 1 cycle delay for registering k and shift
// 1 cycle delay for registering norm_shift
// 1 cycle delay for registering rsqrt_out
// 1 cycle delay for registering a
// ITERSCYCLES delay for calculating inv_sqrt
// 2*`DWORDMULTLATENCY for calculating inv_pwr3
// 1 cycle delay for registering inv_pwr3
// total = ITERS*`RSQRTMULTLATENCY + 2*`DWORDMULTLATENCY + 7 cycles delay
module inv_pwr_3d2_unit #(parameter ITERS = 2, parameter LATENCY = 2) (
    input clk,
    input rst,
    input dword_t x,
    input logic restart,

    output logic valid,
    output dword_t result
);  
    localparam ITERSCYCLES = ITERS*`RSQRTMULTLATENCY+1;
    localparam X_DELAY = 4;
    localparam MSB_STAGES = 4;

    localparam int SHW = $clog2(`DWORDBITS);   // 6 

    dword_t a_delay [ITERSCYCLES-1:0];
    // sign + magnitude instead of two full-width signed chains: the shift
    // count is |half| whichever way we shift, so one SHW-bit magnitude and a
    // direction bit carry the same information in 7 bits instead of 64.
    logic           half_sign_delay [ITERSCYCLES:0];
    logic [SHW-1:0] half_mag_delay  [ITERSCYCLES:0];

    dword_t stage_out [ITERS-1:0];

    dword_t a;
    word_t half;
    word_t half_neg;
    dword_t guess;          // from LUT
    dword_t rsqrt_out;
    dword_t guess_final;    // fully-refined guess, tail of the chain
    logic parity;
    logic [`LUTBITS-1:0] mantissa;
    dword_t inv_pwr3_reg;


    // MSB DETERMINATION
    localparam int MSB_SLICE = `DWORDBITS/MSB_STAGES;   // bits scanned per stage

    word_t [MSB_STAGES-1:0] msb;
    word_t [MSB_STAGES-1:0] msb_reg;
    word_t msb_abs, msb_abs_reg;
    dword_t [X_DELAY-1:0] x_reg;
    always_comb begin
        for (int stage = 0; stage < MSB_STAGES; stage++) begin
            msb[stage] = -1;
            for (int i = 0; i < MSB_SLICE; i++) begin
                if (x[i+stage*MSB_SLICE]) msb[stage] = i;       // last write wins -> highest set bit
            end
        end
    end

    always_comb begin
        msb_abs = -1;
        for (int stage = 0; stage < MSB_STAGES; stage++) begin
            if (msb_reg[stage] != -1) msb_abs = msb_reg[stage] + stage*MSB_SLICE;
        end
    end


    // MANTISSA, A, HALF, RSQRT CALCULATION
    int k_reg;
    int k, k_even, shift, shift_neg;

    logic shift_sign, shift_sign_reg;
    logic [SHW-1:0] shift_mag,  shift_mag_reg;

    logic norm_sign, norm_sign_reg;
    logic [SHW-1:0] norm_mag,   norm_mag_reg;

    logic half_sign;
    logic [SHW-1:0] half_mag;

    logic [`LUTBITS:0] lut_idx, lut_idx_reg;
    dword_t guess_reg;

    int norm_shift, norm_shift_neg;   // comb only -- the registered form is norm_sign_reg/norm_mag_reg

    localparam int NORM_CONST        = (`DENOMFRAC - `SEEDFRAC);
    localparam int NORM_CONST_NEG_P1 = -NORM_CONST + 1;

    always_comb begin
        k = msb_abs_reg - `REF;
        parity = k_reg[0];
        k_even = {k_reg[`WORDBITS-1:1],1'b0};

        // shift and shift_neg stay independent (parallel adders, not chained)
        shift     = msb_abs_reg - `LUTBITS;
        shift_neg = `LUTBITS - msb_abs_reg;
        shift_sign = shift[`WORDBITS-1];
        shift_mag  = shift_sign ? shift_neg[SHW-1:0] : shift[SHW-1:0];

        mantissa =  shift_sign_reg
            ? `LUTBITS'((x_reg[2] << shift_mag_reg) & ((1 << `LUTBITS) - 1))
            : `LUTBITS'((x_reg[2] >> shift_mag_reg) & ((1 << `LUTBITS) - 1)) ;

        lut_idx = {parity, mantissa};

        norm_shift     = NORM_CONST        + k_even;
        norm_shift_neg = NORM_CONST_NEG_P1 + (~k_even);   // computed independently of norm_shift, not derived from it
        norm_sign = norm_shift[`WORDBITS-1];
        norm_mag  = norm_sign ? norm_shift_neg[SHW-1:0] : norm_shift[SHW-1:0];

        a = norm_sign_reg ? (x_reg[3] << norm_mag_reg) : (x_reg[3] >> norm_mag_reg);

        half = k_even >>> 1;
        half_neg = -half;

        half_sign = half[`WORDBITS-1];
        half_mag  = half_sign ? half_neg[SHW-1:0] : half[SHW-1:0];

        guess_final = stage_out[ITERS-1];
        rsqrt_out = half_sign_delay[ITERSCYCLES]
            ? (guess_final << half_mag_delay[ITERSCYCLES])
            : (guess_final >> half_mag_delay[ITERSCYCLES]);
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
            half_sign_delay <= '{default: '0};
            half_mag_delay <= '{default : '0};
            msb_reg <= 0;
            msb_abs_reg <= 0;
            x_reg <= 0;
            inv_pwr3_reg <= 0;
            rsqrt_out_reg <= 0;
            k_reg <= 0;
            shift_sign_reg <= 0;
            shift_mag_reg <= 0;
            norm_sign_reg <= 0;
            norm_mag_reg <= 0;
            lut_idx_reg <= 0;
            guess_reg <= 0;

        end else begin
            msb_reg <= msb;
            msb_abs_reg <= msb_abs;
            x_reg <= {x_reg[X_DELAY-2:0], x};
            inv_pwr3_reg <= inv_pwr3;
            rsqrt_out_reg <= rsqrt_out;
            k_reg <= k;
            shift_sign_reg <= shift_sign;
            shift_mag_reg <= shift_mag;
            norm_sign_reg <= norm_sign;
            norm_mag_reg <= norm_mag;
            lut_idx_reg <= lut_idx;   // stage 1: 5-bit index in
            guess_reg   <= guess;     // stage 2: 64-bit seed out

            a_delay[0]    <= a;
            half_sign_delay[0] <= half_sign;
            half_mag_delay[0]  <= half_mag;
            for (int i = 1; i < ITERSCYCLES; i++) begin
                a_delay[i]    <= a_delay[i-1];
                half_sign_delay[i] <= half_sign_delay[i-1];
                half_mag_delay[i]  <= half_mag_delay[i-1];
            end
            half_sign_delay[ITERSCYCLES] <= half_sign_delay[ITERSCYCLES-1];
            half_mag_delay[ITERSCYCLES]  <= half_mag_delay[ITERSCYCLES-1];
        end
    end

    genvar i;
    generate
        for (i = 0; i < ITERS; i++) begin : newton_stage
            dword_t y_in, a_in;
            if (i == 0) begin : head
                assign y_in = guess_reg;   // LUT seed, delayed 1 cycle to match `a`
                assign a_in = a_delay[0];      // a, registered
            end else begin : tail
                assign y_in = stage_out[i-1];  // previous refined guess
                assign a_in = a_delay[`RSQRTMULTLATENCY*i];  // head 
            end

            rsqrt_newton_step rns (
                .clk,
                .rst,
                .a(a_in),
                .y(y_in),
                .step_out(stage_out[i])
            );
        end
    endgenerate

    // MODULE DECLARATIONS
    newton_lut lookup(
        .mantissa(lut_idx_reg[`LUTBITS-1:0]),
        .parity(lut_idx_reg[`LUTBITS]),

        .val(guess)
    );

    // OUTPUT ASSIGNMENTS
    assign valid = (fill_ctr == LATENCY[$clog2(LATENCY+1)-1:0]);
    assign result = inv_pwr3_reg;
    

endmodule
