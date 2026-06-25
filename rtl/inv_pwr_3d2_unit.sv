`include "defs.svh"

module inv_pwr_3d2_unit #(parameter ITERS = 2, parameter LATENCY = ITERS + 2) (
    input clk,
    input rst,

    input dword_t x,
    output logic valid,
    output dword_t result
);

    // REGISTERS
    dword_t guesses_regs [ITERS-1:0];
    dword_t a_regs [ITERS-1:0];
    word_t half_regs [ITERS-1:0];


    // WIRES TO REGS AND MODULES
    dword_t a_in [ITERS-1:0];
    dword_t guesses_in [ITERS-1:0];
    dword_t guesses_out [ITERS-1:0];
    dword_t a;      
    word_t half;              
    dword_t guess;          // from LUT
    dword_t rsqrt_out;
    logic parity;
    logic [`LUTBITS-1:0] mantissa;


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

        half = k_even >> 1;
        rsqrt_out = (half_regs[ITERS-1] >= 0) 
            ? (guesses_regs[ITERS-1] >> half_regs[ITERS-1]) 
            : (guesses_regs[ITERS-1] << (-half_regs[ITERS-1]));
    end


    // CUBE RSQRT CALCULATION
    dword_t inv_pwr;
    dword_t inv_pwr2;
    dword_t inv_pwr3;
    logic signed [2*`DWORDBITS-1:0] p;
    always_comb begin
        inv_pwr = rsqrt_out;

        p = inv_pwr  * inv_pwr;   
        inv_pwr2 = dword_t'(p >> `SEEDFRAC);

        p = inv_pwr2 * inv_pwr;   
        inv_pwr3 = dword_t'(p >> `SEEDFRAC);
    end


    // LOOKUP TABLE INPUT WIRING
    always_comb begin
        guesses_in[0] = guess;
        a_in[0] = a;
        for (int i = 1; i < ITERS; i++) begin
            a_in[i] = a_regs[i-1];
            guesses_in[i] = guesses_regs[i-1];
        end
    end


    // REGISTER UPDATE
    logic [$clog2(LATENCY+1)-1:0] fill_ctr;
    always_ff @(posedge clk) begin
        if (rst) fill_ctr <= 0;
        else if (fill_ctr < LATENCY[$clog2(LATENCY+1)-1:0]) fill_ctr <= fill_ctr + 1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            guesses_regs <= '{default: '0};
            a_regs <= '{default: '0};
            half_regs <= '{default: '0};
            msb_reg <= 0;
            x_reg <= 0;

        end else begin
            guesses_regs <= guesses_out;
            msb_reg <= msb;
            x_reg <= x;

            a_regs[0] <= a;
            half_regs[0] <= half;
            for (int i = 1; i < ITERS; i++) begin
                a_regs[i]    <= a_regs[i-1];
                half_regs[i] <= half_regs[i-1];
            end
        end
    end


    // MODULE DECLARATIONS
    newton_lut lookup(
        .mantissa(mantissa),
        .parity(parity),

        .val(guess)
    );

    rsqrt_newton_step rns [ITERS-1:0](
        .a(a_in),
        .y(guesses_in),

        .step(guesses_out)
    );
    

    // OUTPUT ASSIGNMENTS
    assign valid = (fill_ctr == LATENCY[$clog2(LATENCY+1)-1:0]);
    assign result = inv_pwr3;
    

endmodule
