`include "defs.svh"

module accel_unit #(parameter ITERS = 2) (
    input clk,
    input rst,
    input logic restart,
    input word_t rx_i,
    input word_t ry_i,
    input word_t rz_i, 
    input word_t rx_j,
    input word_t ry_j, 
    input word_t rz_j,
    input word_t m_j,

    output word_t ax_i_out,
    output word_t ay_i_out,
    output word_t az_i_out,

    output logic accel_valid
);
    // inv_pwr_3d2_unit: 1 cycle (x_reg) + ITERS*RSQRTMULTLATENCY (pipelined newton
    // chain, 18 cyc/step) + 1 cycle (rsqrt_out_reg) + 2*DWORDMULTLATENCY
    // (real inv_pwr^2, inv_pwr^3 multiplies) + 1 cycle (inv_pwr3_reg)
    localparam LATENCY = ITERS*`RSQRTMULTLATENCY + 2*`DWORDMULTLATENCY + 3;
    // mdx/mdy/mdz must stay aligned with inv_res, which trails denom by LATENCY
    // cycles through inv_pwr_3d2_unit *plus* the extra denom_reg stage below
    localparam MD_DELAY = LATENCY + 1;

    dword_t [MD_DELAY-1:0] mdx_reg, mdy_reg, mdz_reg;
    dword_t denom_reg;

    logic valid;
    logic valid_reg;
    logic valid_reg2;

    word_t ax_i_reg;
    word_t ay_i_reg;
    word_t az_i_reg;

    // WORDMULTLATENCY cycle latency from registering d*
    word_t dx, dy, dz;
    dword_t dx2, dy2, dz2, denom, inv_res;

    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) dr2_calc [2:0] (
        .clk,
        .rst,
        .m({dx, dy, dz}),
        .q({dx, dy, dz}),
        .p({dx2, dy2, dz2})
    );

    always_comb begin
        dx = (rx_j) - (rx_i);
        dy = (ry_j) - (ry_i);
        dz = (rz_j) - (rz_i);

        denom = dx2 + dy2 + dz2 + `EPS_SQUARED;
    end


    inv_pwr_3d2_unit #(.ITERS(ITERS), .LATENCY(LATENCY + `WORDMULTLATENCY + `DWORDMULTLATENCY)) ip(
        .clk,
        .rst,
        .x(denom_reg),
        .restart(restart),

        .valid(valid),
        .result(inv_res)
    );

    dword_t mdx_unshifted, mdy_unshifted, mdz_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) mdr_calc [2:0] (
        .clk,
        .rst,
        .m({dx, dy, dz}),
        .q({m_j, m_j, m_j}),
        .p({mdx_unshifted, mdy_unshifted, mdz_unshifted})
    );

    dword_t mdx, mdy, mdz;
    always_comb begin
        // >>> (not >>): dx/dy/dz are frequently negative; >> never sign-extends
        mdx = mdx_unshifted >>> `FRACBITS;
        mdy = mdy_unshifted >>> `FRACBITS;
        mdz = mdz_unshifted >>> `FRACBITS;
    end

    qword_t ax_i_unshifted, ay_i_unshifted, az_i_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`DWORDBITS)) ar_calc [2:0] (
        .clk,
        .rst,
        .q({inv_res, inv_res, inv_res}),
        .m({dword_t'(mdx_reg[MD_DELAY-1]), dword_t'(mdy_reg[MD_DELAY-1]), dword_t'(mdz_reg[MD_DELAY-1])}),
        .p({ax_i_unshifted, ay_i_unshifted, az_i_unshifted})
    );


    always_ff @(posedge clk) begin
        if (rst) begin
            denom_reg <= 0;
            mdx_reg <= 0;
            mdy_reg <= 0;
            mdz_reg <= 0;
            valid_reg <= 0;
            valid_reg2 <= 0;
            ax_i_reg <= 0;
            ay_i_reg <= 0;
            az_i_reg <= 0;
            // dx2_reg <= 0;
            // dy2_reg <= 0;
            // dz2_reg <= 0;
        end else begin
            denom_reg <= denom;
            // inv_pwr_3d2_unit's fill_ctr free-runs (and saturates) while
            // idle between restarts, so the cycle restart actually fires,
            // its combinational `valid` can still read the stale pre-reset
            // (already-saturated) value -- force valid_reg low on that exact
            // cycle so a restart never latches a glitchy "already done" pulse
            valid_reg <= restart ? 1'b0 : valid;
            valid_reg2 <= restart ? 1'b0 : valid_reg;
            ax_i_reg <= word_t'(ax_i_unshifted >>> `SEEDFRAC);
            ay_i_reg <= word_t'(ay_i_unshifted >>> `SEEDFRAC);
            az_i_reg <= word_t'(az_i_unshifted >>> `SEEDFRAC);
            // dx2_reg <= {dx2_reg[`DWORDMULTLATENCY-2:0], dx2};
            // dy2_reg <= {dy2_reg[`DWORDMULTLATENCY-2:0], dy2};
            // dz2_reg <= {dz2_reg[`DWORDMULTLATENCY-2:0], dz2};

            mdx_reg[0] <= mdx;
            mdy_reg[0] <= mdy;
            mdz_reg[0] <= mdz;
            for (int i = 1; i < MD_DELAY; i++) begin
                mdx_reg[i] <= mdx_reg[i-1];
                mdy_reg[i] <= mdy_reg[i-1];
                mdz_reg[i] <= mdz_reg[i-1];
            end
        end
    end

    always_comb begin
        ax_i_out = ax_i_reg;
        ay_i_out = ay_i_reg;
        az_i_out = az_i_reg;
        accel_valid = valid_reg2;
    end

endmodule
