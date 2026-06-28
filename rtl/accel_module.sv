`include "defs.svh"
`include "accel_unit.sv"


module accel_module(
    input clk,
    input rst,
    input logic restart,
    input word_t rx_new [`N_PAD-1:0],
    input word_t ry_new [`N_PAD-1:0],
    input word_t rz_new [`N_PAD-1:0],
    input word_t m [`N_PAD-1:0],
    input [$clog2(`N_PAD)-1:0] p_i,

    output word_t ax_out,
    output word_t ay_out,
    output word_t az_out,

    output logic acc_valid
);
    // tiles the j-loop over the padded array (N_PAD), not the real body count,
    // since rx_new/ry_new/rz_new/m are sized N_PAD; relies on NUMPIPES being a
    // multiple of NUMLANES so N_PAD (a multiple of NUMPIPES) divides evenly here
    localparam num_cycles = (`N_PAD + `NUMLANES - 1)/`NUMLANES;
    localparam ITERS = 2;

    word_t ax_reg;
    word_t ay_reg;
    word_t az_reg;

    // in_ctr drives which j-batch is fed in, advancing every cycle from restart
    // (NOT gated on au_valid) so a fresh batch is already in flight by the time
    // accel_unit's pipeline first reports valid; cycle_ctr separately counts how
    // many batches' worth of results have actually been accumulated
    word_t in_ctr;
    word_t cycle_ctr;

    genvar i;

    word_t ax_wire [`NUMLANES-1:0];
    word_t ay_wire [`NUMLANES-1:0];
    word_t az_wire [`NUMLANES-1:0];

    logic au_valid;
    logic done_accumulating;

    int jump = in_ctr*`NUMLANES;

    always_ff @(posedge clk) begin
        if (rst | restart) in_ctr <= 0;
        else if (in_ctr < num_cycles - 1) in_ctr <= in_ctr + 1;
    end

    generate
        for (i = 0; i < `NUMLANES; i++) begin
            accel_unit #(.ITERS(ITERS)) au (
                .clk,
                .rst,
                .restart(restart),
                .rx_i(rx_new[p_i]),
                .ry_i(ry_new[p_i]),
                .rz_i(rz_new[p_i]),
                .rx_j(rx_new[jump + i]),
                .ry_j(ry_new[jump + i]),
                .rz_j(rz_new[jump + i]),
                .m_j(m[jump + i]),

                .ax_i_out(ax_wire[i]),
                .ay_i_out(ay_wire[i]),
                .az_i_out(az_wire[i]),

                .accel_valid(au_valid)
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst | done_accumulating) begin
            ax_reg <= 0;
            ay_reg <= 0;
            az_reg <= 0;
            done_accumulating <= 0;
            cycle_ctr <= 0;
        end else begin
            if (au_valid && cycle_ctr < num_cycles) begin
                ax_reg <= ax_reg + ax_wire.sum();
                ay_reg <= ay_reg + ay_wire.sum();
                az_reg <= az_reg + az_wire.sum();

                cycle_ctr <= cycle_ctr + 1;

                if (cycle_ctr == num_cycles - 1) begin
                    done_accumulating <= 1;
                end
            end
        end
    end

    assign ax_out = ax_reg;
    assign ay_out = ay_reg;
    assign az_out = az_reg;
    assign acc_valid = done_accumulating;



endmodule
