`include "defs.svh"

module integrator (
    input clk,
    input rst,

    input State st,
    input [`NBITS-1:0] p_i,

    input word_t dt,

    output word_t rx_ip1_out,
    output word_t ry_ip1_out,
    output word_t rz_ip1_out,

    output word_t vx_ip1_out,
    output word_t vy_ip1_out,
    output word_t vz_ip1_out,

    output word_t ax_ip1_out,
    output word_t ay_ip1_out,
    output word_t az_ip1_out
);

    word_t rx_ip1_reg;
    word_t ry_ip1_reg;
    word_t rz_ip1_reg;

    word_t vx_iphalf_reg;
    word_t vy_iphalf_reg;
    word_t vz_iphalf_reg;

    logic new_accel_ready;
    accel_module am(
        .clk,
        .rst,

        .st(st),
        .p_i(p_i),

        .ax_out(ax_ip1_out),
        .ay_out(ay_ip1_out),
        .az_out(az_ip1_out),
        .acc_valid(new_accel_ready)
    );



    always_ff @(posedge clk) begin
        if (rst) begin
            vx_iphalf_reg <= 0;
            vy_iphalf_reg <= 0;
            vz_iphalf_reg <= 0;

        end else begin
            vx_iphalf_reg <= st.vx[p_i] + word_t'((dword_t'(st.ax[p_i] * dt)) >> (`FRACBITS + 1));
            vy_iphalf_reg <= st.vy[p_i] + word_t'((dword_t'(st.ay[p_i] * dt)) >> (`FRACBITS + 1));
            vz_iphalf_reg <= st.vz[p_i] + word_t'((dword_t'(st.az[p_i] * dt)) >> (`FRACBITS + 1));

            rx_ip1_reg <= st.rx[p_i] + word_t'(dword_t'(vx_iphalf_reg * dt) >> `FRACBITS);
            ry_ip1_reg <= st.ry[p_i] + word_t'(dword_t'(vy_iphalf_reg * dt) >> `FRACBITS);
            rz_ip1_reg <= st.rz[p_i] + word_t'(dword_t'(vz_iphalf_reg * dt) >> `FRACBITS);
        end
    end

    always_comb begin : outputs
        rx_ip1_out = rx_ip1_reg;
        ry_ip1_out = ry_ip1_reg;
        rz_ip1_out = rz_ip1_reg;

        if (new_accel_ready) begin
            vx_ip1_out = vx_iphalf_reg + word_t'(dword_t'(ax_ip1_out * dt) >> (`FRACBITS + 1));
            vy_ip1_out = vy_iphalf_reg + word_t'(dword_t'(ay_ip1_out * dt) >> (`FRACBITS + 1));
            vz_ip1_out = vz_iphalf_reg + word_t'(dword_t'(az_ip1_out * dt) >> (`FRACBITS + 1));
        end else begin
            vx_ip1_out = 0;
            vy_ip1_out = 0;
            vz_ip1_out = 0;
        end
    end

endmodule
