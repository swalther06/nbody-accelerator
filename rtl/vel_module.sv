`include "defs.svh"

module vel_module(
    input clk,
    input rst,
    input logic restart,
    input word_t vx_half,
    input word_t vy_half,
    input word_t vz_half,
    input word_t ax_new,
    input word_t ay_new,
    input word_t az_new,
    input word_t dt,

    output word_t vx_new,
    output word_t vy_new,
    output word_t vz_new,
    output logic vel_valid
);
    word_t vx_new_reg;
    word_t vy_new_reg;
    word_t vz_new_reg;

    logic vel_valid_reg;

    always_ff @(posedge clk) begin
        if (rst | restart) vel_valid_reg <= 0;
        else vel_valid_reg <= 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            vx_new_reg <= 0;
            vy_new_reg <= 0;
            vz_new_reg <= 0;
        end else begin
            vx_new_reg <= vx_half + word_t'((dword_t'(ax_new) * dt) >>> (`FRACBITS + 1));
            vy_new_reg <= vy_half + word_t'((dword_t'(ay_new) * dt) >>> (`FRACBITS + 1));
            vz_new_reg <= vz_half + word_t'((dword_t'(az_new) * dt) >>> (`FRACBITS + 1));
        end
    end

    always_comb begin
        vx_new = vx_new_reg;
        vy_new = vy_new_reg;
        vz_new = vz_new_reg;
        vel_valid = vel_valid_reg;
    end


endmodule
