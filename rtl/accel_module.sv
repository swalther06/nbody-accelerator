`include "defs.svh"

module accel_module(
    input clk,
    input rst,
    input logic restart,
    input word_t [2:0] r_new [`N_PAD-1:0],
    input word_t m [`N_PAD-1:0],
    input [$clog2(`N_PAD)-1:0] p_i,

    output word_t [2:0] a_out,
    output logic acc_valid
);

    localparam num_cycles = (`N_PAD + `NUMLANES - 1)/`NUMLANES;
    localparam ITERS = 2;

    word_t [2:0] a_reg;

    // in_ctr drives which j-batch is fed in, advancing every cycle from restart
    // (NOT gated on au_valid) so a fresh batch is already in flight by the time
    // accel_unit's pipeline first reports valid; cycle_ctr separately counts how
    // many batches' worth of results have actually been accumulated
    word_t in_ctr;
    word_t cycle_ctr;

    genvar i;

    word_t [2:0] a_wire [`NUMLANES-1:0];

    logic [`NUMLANES-1:0] au_valid;
    logic done_accumulating;

    word_t [2:0] a_sum;
    always_comb begin
        a_sum = 0;
        for (int k = 0; k < `NUMLANES; k++) begin
            for (int dir = 0; dir < 3; dir++) begin
                a_sum[dir] += a_wire[k][dir];
            end
        end
    end

    // tracks in_ctr combinationally (a module-scope declaration assignment
    // would only initialize once at time 0, not follow in_ctr)
    int jump;
    always_comb jump = in_ctr*`NUMLANES;

    always_ff @(posedge clk) begin
        if (rst | restart) in_ctr <= 0;
        else in_ctr <= (in_ctr == num_cycles - 1) ? 0 : in_ctr + 1;
    end

    generate
        for (i = 0; i < `NUMLANES; i++) begin
            accel_unit #(.ITERS(ITERS)) au (
                .clk,
                .rst,
                .restart(restart),
                .r_i(r_new[p_i]),
                .r_j(r_new[jump + i]),
                .m_j(m[jump + i]),
                .a_i_out(a_wire[i]),
                .accel_valid(au_valid[i])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst | restart) begin
            a_reg <= 0;
            done_accumulating <= 0;
            cycle_ctr <= 0;
        end else begin
            if (au_valid[0] && cycle_ctr < num_cycles) begin
                for (int dir = 0; dir < 3; dir++) begin
                    a_reg[dir] <= a_reg[dir] + a_sum[dir];
                end
                cycle_ctr <= cycle_ctr + 1;

                if (cycle_ctr == num_cycles - 1) begin
                    done_accumulating <= 1;
                end
            end
        end
    end

    assign a_out = a_reg;
    assign acc_valid = done_accumulating;



endmodule
