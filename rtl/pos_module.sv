`include "defs.svh"

module pos_module (
    input clk,
    input rst,
    input logic restart,
    input word_t [2:0] r_old,
    input word_t [2:0] v_old,
    input word_t [2:0] a_old,
    input word_t dt,

    output word_t [2:0] r_new,
    output word_t [2:0] v_half,
    output logic pos_valid
);
    word_t [`WORDMULTLATENCY:0][2:0] v_half_reg;
    word_t [2:0] r_new_reg;

    word_t [`WORDMULTLATENCY-1:0][2:0] v_old_delay;
    word_t [2*`WORDMULTLATENCY-1:0][2:0] r_old_delay;

    logic [`WORDMULTLATENCY-1:0] half_valid_reg;
    logic [`WORDMULTLATENCY+1:0] pos_valid_reg;

    always_ff @(posedge clk) begin
        if (rst | restart) begin
            half_valid_reg <= 0;
            pos_valid_reg  <= 0;
        end else begin
            half_valid_reg <= {half_valid_reg[`WORDMULTLATENCY-2:0], 1'b1};
            pos_valid_reg  <= {pos_valid_reg[`WORDMULTLATENCY:0], half_valid_reg[`WORDMULTLATENCY-1]};
        end
    end

    dword_t [2:0] a_dt_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) v_half_calc [2:0] (
        .clk,
        .rst,
        .m(a_old),
        .q({dt, dt, dt}),
        .p(a_dt_unshifted)
    );

    dword_t [2:0] v_half_dt_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) r_new_calc [2:0] (
        .clk,
        .rst,
        .m(v_half_reg[0]),
        .q({dt, dt, dt}),
        .p(v_half_dt_unshifted)
    );

    word_t [2:0] a_dt;
    word_t [2:0] v_half_dt;
    word_t [2:0] v_a_sum;
    always_comb begin
        for (int dir = 0; dir < 3; dir++) begin
            a_dt[dir] = word_t'(`RSHIFT_ROUND(a_dt_unshifted[dir], `FRACBITS + 1));
            v_a_sum[dir] = v_old_delay[`WORDMULTLATENCY-1][dir] + a_dt[dir];
            v_half_dt[dir] = word_t'(`RSHIFT_ROUND(v_half_dt_unshifted[dir], `FRACBITS));
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            v_half_reg <= 0;
            r_new_reg <= 0;
            v_old_delay <= 0;
            r_old_delay <= 0;
        end else begin
            for (int dir = 0; dir < 3; dir++) begin
                r_new_reg[dir] <= r_old_delay[2*`WORDMULTLATENCY-1][dir] + v_half_dt[dir];
            end
            v_half_reg <= {v_half_reg[`WORDMULTLATENCY-1:0], v_a_sum};
            v_old_delay <= {v_old_delay[`WORDMULTLATENCY-2:0], v_old};
            r_old_delay <= {r_old_delay[2*`WORDMULTLATENCY-2:0], r_old};
        end
    end

    always_comb begin
        r_new = r_new_reg;
        v_half = v_half_reg[`WORDMULTLATENCY];
        pos_valid = pos_valid_reg[`WORDMULTLATENCY+1];
    end

endmodule
