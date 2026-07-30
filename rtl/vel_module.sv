`include "defs.svh"

module vel_module(
    input clk,
    input rst,
    input logic restart,
    input word_t [2:0] v_half,
    input word_t [2:0] a_new,
    input word_t dt,

    output word_t [2:0] v_new,
    output logic vel_valid
);
    word_t [2:0] v_new_reg;

    word_t [`WORDMULTLATENCY-1:0][2:0] v_half_delay;

    logic [`WORDMULTLATENCY:0] vel_valid_reg;

    always_ff @(posedge clk) begin
        if (rst | restart) vel_valid_reg <= 0;
        else vel_valid_reg <= {vel_valid_reg[`WORDMULTLATENCY-1:0], 1'b1};
    end

    dword_t [2:0] a_dt_unshifted;
    rad4_booth_reduction_multiplier #(.WIDTH(`WORDBITS)) vx_half [2:0] (
        .clk,
        .rst,
        .m(a_new),
        .q({dt, dt, dt}),
        .p(a_dt_unshifted)
    );

    word_t [2:0] a_dt;
    always_comb begin
        for (int dir = 0; dir < 3; dir++) begin
            a_dt[dir] = word_t'(`RSHIFT_ROUND(a_dt_unshifted[dir], `FRACBITS + 1));
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            v_new_reg <= 0;
            v_half_delay <= 0;
        end else begin
            for (int dir = 0; dir < 3; dir++) begin
                v_new_reg[dir] <= v_half_delay[`WORDMULTLATENCY-1][dir] + a_dt[dir];
            end
            v_half_delay <= {v_half_delay[`WORDMULTLATENCY-2:0], v_half};
        end
    end

    always_comb begin
        v_new = v_new_reg;
        vel_valid = vel_valid_reg[`WORDMULTLATENCY];
    end


endmodule
