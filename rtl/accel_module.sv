`include "defs.svh"

module accel_module #(parameter NUMLANES = `NUMLANES) (
    input clk,
    input rst,
    input logic restart,
    input word_t [2:0] r_new [`N_PAD-1:0],
    input word_t m [`N_PAD-1:0],
    input [$clog2(`N_PAD)-1:0] p_i,
    input word_t j_tiles,

    output word_t [2:0] a_out,
    output logic acc_valid
);

    localparam ITERS = 2;

    word_t [2:0] a_reg;

    // in_ctr drives which j-batch is fed in, advancing every cycle from restart
    // (NOT gated on au_valid) so a fresh batch is already in flight by the time
    // accel_unit's pipeline first reports valid; cycle_ctr separately counts how
    // many batches' worth of results have actually been accumulated
    word_t in_ctr;
    word_t cycle_ctr;

    genvar i;

    word_t [2:0] a_wire [NUMLANES-1:0];

    logic [NUMLANES-1:0] au_valid;

    // au_valid has to be delayed by exactly the accumulator's latency so the
    // accumulate below fires on the cycle a_sum is actually valid. That depth
    // varies with NUMLANES (1 for <=2 lanes, 2 for 4/8, 3 for 16), so take it
    // from `ACC_LATENCY instead of hardcoding it. VALID_W floors the vector at
    // 2 bits purely to keep the [VALID_W-2:0] part-select below legal when the
    // latency is 1; the tap is always at ACC_LATENCY-1.
    localparam ACC_LATENCY = `ACC_LATENCY(NUMLANES);
    localparam VALID_W = (ACC_LATENCY < 2) ? 2 : ACC_LATENCY;

    logic [VALID_W-1:0] au_valid_reg [NUMLANES-1:0];
    logic done_accumulating;

    // rewiring to satisfy systemverilog
    word_t a_wire_t [2:0][NUMLANES-1:0];
    always_comb begin
        for (int k = 0; k < NUMLANES; k++) begin
            for (int d = 0; d < 3; d++) begin
                a_wire_t[d][k] = a_wire[k][d];
            end
        end
    end

    // 2 cycle latency here
    word_t [2:0] a_sum;
    accumulator_piplined #(.WIDTH(`WORDBITS), .NUM_INPS(NUMLANES)) accel_accumulator [2:0] (
        .clk,
        .rst,
        .inp(a_wire_t),
        .acc(a_sum)
    );

    // tracks in_ctr combinationally (a module-scope declaration assignment
    // would only initialize once at time 0, not follow in_ctr)
    int jump;
    always_comb jump = in_ctr*NUMLANES;

    always_ff @(posedge clk) begin
        if (rst | restart) in_ctr <= 0;
        else in_ctr <= (in_ctr == j_tiles - 1) ? 0 : in_ctr + 1;
    end

    generate
        for (i = 0; i < NUMLANES; i++) begin
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
            au_valid_reg <= '{default : 0};
        end else begin
            if (au_valid_reg[0][ACC_LATENCY-1]) begin
                for (int dir = 0; dir < 3; dir++) begin
                    a_reg[dir] <= a_reg[dir] + a_sum[dir];
                end
                cycle_ctr <= cycle_ctr + 1;

                if (cycle_ctr == j_tiles - 1) begin
                    done_accumulating <= 1;
                end
            end
            for (int lane = 0; lane < NUMLANES; lane++) begin
                au_valid_reg[lane] <= {au_valid_reg[lane][VALID_W-2:0], au_valid[lane]};
            end
        end
    end

    assign a_out = a_reg;
    assign acc_valid = done_accumulating;



endmodule
