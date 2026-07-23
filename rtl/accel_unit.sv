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
    // inv_pwr_3d2_unit: 1 cycle (x_reg) + 3*ITERS (pipelined newton chain,
    // 3 cyc/step) + 2 cycles (inv_pwr3_reg) from x applied to result valid
    localparam LATENCY = 3*ITERS + 5;
    // mdx/mdy/mdz must stay aligned with inv_res, which trails denom by LATENCY
    // cycles through inv_pwr_3d2_unit *plus* the extra denom_reg stage below
    localparam MD_DELAY = LATENCY + 1;

    dword_t [MD_DELAY-1:0] mdx_reg, mdy_reg, mdz_reg;
    dword_t denom_reg;

    logic valid;
    logic valid_reg;
    // ax_i_reg/ay_i_reg/az_i_reg register the product of mdx_reg[MD_DELAY-1]
    // and inv_res, both of which only become valid the SAME cycle valid_reg
    // itself does -- so accel_valid needs a second stage to match the extra
    // register hop ax_i_reg takes beyond its own inputs settling
    logic valid_reg2;

    word_t ax_i_reg;
    word_t ay_i_reg;
    word_t az_i_reg;

    // 1 cycle latency from registering d*
    dword_t dx, dy, dz, denom, inv_res;
    dword_t dx2, dy2, dz2;
    dword_t dx2_reg, dy2_reg, dz2_reg;
    always_comb begin
        dx = dword_t'(rx_j) - dword_t'(rx_i);
        dy = dword_t'(ry_j) - dword_t'(ry_i);
        dz = dword_t'(rz_j) - dword_t'(rz_i);

        dx2 = dx*dx;
        dy2 = dy*dy;
        dz2 = dz*dz;

        denom = dx2_reg + dy2_reg + dz2_reg + `EPS_SQUARED;
    end

    
    inv_pwr_3d2_unit #(.ITERS(ITERS), .LATENCY(LATENCY)) ip(
        .clk,
        .rst,
        .x(denom_reg),
        .restart(restart),

        .valid(valid),
        .result(inv_res)
    );


    dword_t mdx, mdy, mdz;
    always_comb begin
        // >>> (not >>): dx/dy/dz are frequently negative; >> never sign-extends
        mdx = (dword_t'(m_j) * dx) >>> `FRACBITS;
        mdy = (dword_t'(m_j) * dy) >>> `FRACBITS;
        mdz = (dword_t'(m_j) * dz) >>> `FRACBITS;
    end


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
            dx2_reg <= 0;
            dy2_reg <= 0;
            dz2_reg <= 0;
        end else begin
            denom_reg <= denom;
            // inv_pwr_3d2_unit's fill_ctr free-runs (and saturates) while
            // idle between restarts, so the cycle restart actually fires,
            // its combinational `valid` can still read the stale pre-reset
            // (already-saturated) value -- force valid_reg low on that exact
            // cycle so a restart never latches a glitchy "already done" pulse
            valid_reg <= restart ? 1'b0 : valid;
            valid_reg2 <= restart ? 1'b0 : valid_reg;
            ax_i_reg <= word_t'((mdx_reg[MD_DELAY-1] * inv_res) >>> `SEEDFRAC);
            ay_i_reg <= word_t'((mdy_reg[MD_DELAY-1] * inv_res) >>> `SEEDFRAC);
            az_i_reg <= word_t'((mdz_reg[MD_DELAY-1] * inv_res) >>> `SEEDFRAC);
            dx2_reg <= dx2;
            dy2_reg <= dy2;
            dz2_reg <= dz2;

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
