`include "defs.svh"
`include "inv_pwr_3d2_unit.sv"

module accel_unit #(parameter ITERS = 2, parameter LATENCY = ITERS + 2) (
    input clk,
    input rst,

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
    dword_t [LATENCY-1:0] mdx_reg, mdy_reg, mdz_reg;
    dword_t denom_reg;
    dword_t inv_res_reg;

    logic valid;
    logic valid_reg;

    dword_t dx, dy, dz, denom, inv_res;
    always_comb begin
        dx = dword_t'(rx_j) - dword_t'(rx_i);
        dy = dword_t'(ry_j) - dword_t'(ry_i);
        dz = dword_t'(rz_j) - dword_t'(rz_i);  
        denom = dx*dx + dy*dy + dz*dz + `EPS_SQUARED;
    end

    
    inv_pwr_3d2_unit #(.ITERS(ITERS), .LATENCY(LATENCY)) ip(
        .clk,
        .rst,
        .x(denom_reg),

        .valid(valid),
        .result(inv_res)
    );


    dword_t mdx, mdy, mdz;
    always_comb begin
        mdx = (dword_t'(m_j) * dx) >> `FRACBITS;
        mdy = (dword_t'(m_j) * dy) >> `FRACBITS;
        mdz = (dword_t'(m_j) * dz) >> `FRACBITS;
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            denom_reg <= 0;
            inv_res_reg <= 0;
            mdx_reg <= 0;
            mdy_reg <= 0;
            mdz_reg <= 0;
            valid_reg <= 0;
        end else begin
            denom_reg <= denom;
            inv_res_reg <= inv_res;
            valid_reg <= valid;

            mdx_reg[0] <= mdx;
            mdy_reg[0] <= mdy;
            mdz_reg[0] <= mdz;
            for (int i = 1; i < LATENCY; i++) begin
                mdx_reg[i] <= mdx_reg[i-1];
                mdy_reg[i] <= mdy_reg[i-1];
                mdz_reg[i] <= mdz_reg[i-1];
            end
        end
    end


    assign ax_i_out = word_t'((mdx_reg[LATENCY-1] * inv_res_reg) >> `SEEDFRAC);
    assign ay_i_out = word_t'((mdy_reg[LATENCY-1] * inv_res_reg) >> `SEEDFRAC);
    assign az_i_out = word_t'((mdz_reg[LATENCY-1] * inv_res_reg) >> `SEEDFRAC);

    assign accel_valid = valid_reg;


endmodule
