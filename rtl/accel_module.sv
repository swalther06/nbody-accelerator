`include "defs.svh"
`include "accel_unit.sv"


module accel_module(
    input clk,
    input rst,

    input word_t [`N-1:0] rx_new,
    input word_t [`N-1:0] ry_new,
    input word_t [`N-1:0] rz_new,
    input word_t [`N-1:0] m,
    input [`NBITS-1:0] p_i,

    output word_t ax_out,
    output word_t ay_out,
    output word_t az_out,

    output logic acc_valid
);
    localparam num_cycles = $ceil(`N / `NUMLANES);

    word_t ax_reg;
    word_t ay_reg;
    word_t az_reg;

    word_t cycle_ctr;

    genvar i;

    word_t ax_wire [`NUMLANES-1:0];
    word_t ay_wire [`NUMLANES-1:0];
    word_t az_wire [`NUMLANES-1:0];

    logic au_valid;
    logic done_accumulating;
    
    generate
        for (i = 0; i < `NUMLANES; i++) begin
            accel_unit au (
                .clk,
                .rst,

                .rx_i(rx_new[p_i]),
                .ry_i(ry_new[p_i]),
                .rz_i(rz_new[p_i]),

                .rx_j(rx_new[cycle_ctr*`NUMLANES + i]),
                .ry_j(ry_new[cycle_ctr*`NUMLANES + i]),
                .rz_j(rz_new[cycle_ctr*`NUMLANES + i]),
                .m_j(m[cycle_ctr*`NUMLANES + i]),

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
        end

        else begin
            if (au_valid) begin
                ax_reg <= ax_reg + ax_wire.sum();
                ay_reg <= ay_reg + ay_wire.sum();
                az_reg <= az_reg + az_wire.sum();

                cycle_ctr <= cycle_ctr + 1;
            end

            if (cycle_ctr == num_cycles) begin
                done_accumulating <= 1;
                cycle_ctr <= 0;
            end
            
        end
    end

    assign ax_out = ax_reg;
    assign ay_out = ay_reg;
    assign az_out = az_reg;
    assign acc_valid = done_accumulating;



endmodule
