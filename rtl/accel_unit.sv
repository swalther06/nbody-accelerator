`include "defs.svh"

// inputs arrive cycle 0
// dr available on cycle 0 TODO will change to cycle 1
// dr2 availabe on cycle 5 (`WORDMULTLATENCY)
// denom_reg availabe on cycle 6 (`WORDMULTLATENCY + 1)
// inv_res availabe on cycle BLANK (DENOM_LATENCY + INV_PWR_LATENCY)
// a_i_reg availabe on cycle BLANK (DENOM_LATENCY + INV_PWR_LATENCY + 1)
module accel_unit #(parameter ITERS = 2) (
    input clk,
    input rst,
    input logic restart,
    input word_t [2:0] r_i,
    input word_t [2:0] r_j,
    input word_t m_j,

    output word_t [2:0] a_i_out,
    output logic accel_valid
);
    localparam DENOM_LATENCY = `WORDMULTLATENCY + 1;
    localparam INV_PWR_LATENCY = DENOM_LATENCY + ITERS*`RSQRTMULTLATENCY + 2*`DWORDMULTLATENCY + 3;
    localparam MD_LATENCY = INV_PWR_LATENCY - `WORDMULTLATENCY;
    localparam VALID_LATENCY = (`DWORDMULTLATENCY + 2);


    dword_t [MD_LATENCY-1:0][2:0] mdr_reg;
    dword_t denom_reg;

    logic valid;
    logic [VALID_LATENCY-1:0] valid_reg;

    word_t [2:0] a_i_reg;

    // WORDMULTLATENCY cycle latency from registering d*
    word_t [2:0] dr;
    dword_t [2:0] dr2;
    dword_t denom, inv_res;

    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) dr2_calc [2:0] (
        .clk,
        .rst,
        .m(dr),
        .q(dr),
        .p(dr2)
    );

    dword_t dr2_sum;
    always_comb begin
        dr2_sum = '0;
        for (int dir = 0; dir < 3; dir++) begin
            dr[dir] = r_j[dir] - r_i[dir];
            dr2_sum += dr2[dir];
        end

        denom = dr2_sum + `EPS_SQUARED;
    end


    inv_pwr_3d2_unit #(.ITERS(ITERS), .LATENCY(INV_PWR_LATENCY)) ip(
        .clk,
        .rst,
        .x(denom_reg),
        .restart(restart),

        .valid(valid),
        .result(inv_res)
    );

    dword_t [2:0] mdr_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) mdr_calc [2:0] (
        .clk,
        .rst,
        .m(dr),
        .q({m_j, m_j, m_j}),
        .p(mdr_unshifted)
    );

    dword_t [2:0] mdr;
    always_comb begin
        // >>> (not >>): dx/dy/dz are frequently negative; >> never sign-extends
        for (int dir = 0; dir < 3; dir++) begin
            mdr[dir] = mdr_unshifted[dir] >>> `FRACBITS;
        end
    end

    qword_t [2:0] a_i_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) ar_calc [2:0] (
        .clk,
        .rst,
        .q({inv_res, inv_res, inv_res}),
        .m(mdr_reg[MD_LATENCY-1]),
        .p(a_i_unshifted)
    );

    word_t [2:0] a_i;
    always_comb begin
        for (int dir = 0; dir < 3; dir++) begin
            a_i[dir] = word_t'(a_i_unshifted[dir] >>> `SEEDFRAC);
        end
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            denom_reg <= 0;
            mdr_reg <= 0;
            valid_reg <= 0;
            a_i_reg <= 0;
        end else begin
            denom_reg <= denom;
            // inv_pwr_3d2_unit's fill_ctr free-runs (and saturates) while
            // idle between restarts, so the cycle restart actually fires,
            // its combinational `valid` can still read the stale pre-reset
            // (already-saturated) value -- force valid_reg low on that exact
            // cycle so a restart never latches a glitchy "already done" pulse
            valid_reg <= restart ? '0 : {valid_reg[VALID_LATENCY-2:0], valid};
            a_i_reg <= a_i;

            mdr_reg[0] <= mdr;
            for (int i = 1; i < MD_LATENCY; i++) begin
                mdr_reg[i] <= mdr_reg[i-1];
            end
        end
    end

    always_comb begin
        a_i_out = a_i_reg;
        accel_valid = valid_reg[VALID_LATENCY-1];
    end

endmodule
