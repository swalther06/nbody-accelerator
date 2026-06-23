`include "defs.svh"
`include "inv_pwr_3d2.sv"

module accel_kernel(
    input clk,
    input rst,

    input word_t rx_i,
    input word_t ry_i,
    input word_t rz_i, 

    input word_t rx_j,
    input word_t ry_j, 
    input word_t rz_j,
    input word_t m_j,

    output word_t ax_i,
    output word_t ay_i,
    output word_t az_i,

    output logic inv_valid
);
    dword_t dx, dy, dz, denom;
    
    always_comb begin
        dx = dword_t'(rx_j) - dword_t'(rx_i);
        dy = dword_t'(ry_j) - dword_t'(ry_i);
        dz = dword_t'(rz_j) - dword_t'(rz_i);  
        denom = dx*dx + dy*dy + dz*dz + `EPS_SQUARED;
    end

    dword_t inv_res;
    inv_pwr_3d2 ip(
        .clk,
        .rst,
        
        .x(denom),
        .valid(inv_valid),
        .result(inv_res)
    );


    dword_t mdx, mdy, mdz;
    always_comb begin
        mdx = (dword_t'(m_j) * dx) >> `FRACBITS;
        mdy = (dword_t'(m_j) * dy) >> `FRACBITS;
        mdz = (dword_t'(m_j) * dz) >> `FRACBITS;
    end



    assign ax_i = word_t'((mdx * inv_res) >> `SEEDFRAC);
    assign ay_i = word_t'((mdy * inv_res) >> `SEEDFRAC);
    assign az_i = word_t'((mdz * inv_res) >> `SEEDFRAC);


endmodule
