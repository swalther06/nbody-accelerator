`include "defs.svh"

module pos_module (
    input clk,
    input rst,
    input logic restart,
    input word_t rx_old,
    input word_t ry_old,
    input word_t rz_old,
    input word_t vx_old,
    input word_t vy_old,
    input word_t vz_old,
    input word_t ax_old,
    input word_t ay_old,
    input word_t az_old,
    input word_t dt,

    output word_t rx_new,
    output word_t ry_new,
    output word_t rz_new,
    output word_t vx_half,
    output word_t vy_half,
    output word_t vz_half,
    output logic pos_valid
);
    word_t vx_half_reg;
    word_t vy_half_reg;
    word_t vz_half_reg;
    word_t rx_new_reg;
    word_t ry_new_reg;
    word_t rz_new_reg;

    logic half_valid_reg;
    logic pos_valid_reg;

    always_ff @(posedge clk) begin
        if (rst | restart) begin
            half_valid_reg <= 0;
            pos_valid_reg  <= 0;
        end else begin
            half_valid_reg <= 1'b1;
            pos_valid_reg  <= half_valid_reg;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            vx_half_reg <= 0;
            vy_half_reg <= 0;
            vz_half_reg <= 0;
            rx_new_reg <= 0;
            ry_new_reg <= 0;
            rz_new_reg <= 0;
        end else begin
            vx_half_reg <= vx_old + word_t'((dword_t'(ax_old) * dt) >>> (`FRACBITS + 1));
            vy_half_reg <= vy_old + word_t'((dword_t'(ay_old) * dt) >>> (`FRACBITS + 1));
            vz_half_reg <= vz_old + word_t'((dword_t'(az_old) * dt) >>> (`FRACBITS + 1));
            rx_new_reg <= rx_old + word_t'((dword_t'(vx_half_reg) * dt) >>> `FRACBITS);
            ry_new_reg <= ry_old + word_t'((dword_t'(vy_half_reg) * dt) >>> `FRACBITS);
            rz_new_reg <= rz_old + word_t'((dword_t'(vz_half_reg) * dt) >>> `FRACBITS);
        end
    end

    always_comb begin
        rx_new = rx_new_reg;
        ry_new = ry_new_reg;
        rz_new = rz_new_reg;

        vx_half = vx_half_reg;
        vy_half = vy_half_reg;
        vz_half = vz_half_reg;

        pos_valid = pos_valid_reg;
    end

endmodule
