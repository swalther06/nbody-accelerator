`include "defs.svh"


module compressor_4_2_tree #(parameter WIDTH = 64, parameter TRIPLES = 16) (
    input clk,
    input rst,

    input logic signed [WIDTH-1:0] partial_prod [TRIPLES-1:0],
    output logic [WIDTH-1:0] sum_out,
    output logic [WIDTH-1:0] carry_out
);  
    localparam LEVELS = $clog2(TRIPLES)-1;

    typedef int size_arr_t [LEVELS:0];
    function automatic size_arr_t generate_arr_sizes();
        size_arr_t tmp;
        tmp[0] = TRIPLES;
        for (int i = 1; i <= LEVELS; i++) begin
            int groups = tmp[i-1] / 4;
            int leftover = tmp[i-1] % 4;
            tmp[i] = groups * 2 + leftover;
        end
        return tmp;
    endfunction

    localparam size_arr_t SIZES = generate_arr_sizes();

    logic [WIDTH-1:0] tree_w [LEVELS:0][TRIPLES-1:0];
    logic [WIDTH-1:0] tree_r [LEVELS:0][TRIPLES-1:0];

    genvar pp;
    generate
        for (pp = 0; pp < TRIPLES; pp++) begin : load
            assign tree_r[0][pp] = partial_prod[pp];
        end
    endgenerate

    genvar lvl, grp, rdr;
    generate 
        for (lvl = 0; lvl < LEVELS; lvl++) begin
            localparam int GROUPS = SIZES[lvl] / 4;
            localparam int REMAINDER = SIZES[lvl] % 4;

            for (grp = 0; grp < GROUPS; grp++) begin : compressor_tree
                logic [WIDTH-1:0] cout_w;
                logic [WIDTH-1:0] carry_w;
                logic [WIDTH-1:0] sum_w;

                // inline compressor_4_2.sv here to reduce port connections and speed up simulation
                always_comb begin
                    for (int b = 0; b < WIDTH; b++) begin
                        logic x1, x2, x3, x4, ci_bit, s;
                        x1 = tree_r[lvl][grp*4+0][b];
                        x2 = tree_r[lvl][grp*4+1][b];
                        x3 = tree_r[lvl][grp*4+2][b];
                        x4 = tree_r[lvl][grp*4+3][b];
                        ci_bit = (b == 0) ? 1'b0 : cout_w[b-1];

                        s = x1 ^ x2 ^ x3;
                        cout_w[b] = (x1 & x2) | (x3 & (x1 ^ x2));

                        sum_w[b]   = s ^ x4 ^ ci_bit;
                        carry_w[b] = (s & x4) | (ci_bit & (s ^ x4));
                    end
                end

                assign tree_w[lvl+1][grp*2] = sum_w;
                assign tree_w[lvl+1][grp*2+1] = {carry_w[WIDTH-2:0], 1'b0};
            end

            for (rdr = 0; rdr < REMAINDER; rdr++) begin : passthrough
                assign tree_w[lvl+1][GROUPS*2 + rdr] = tree_r[lvl][GROUPS*4 + rdr];
            end

            // register every 2nd level
            localparam bit IS_REG_BOUNDARY = (lvl % 2 == 1) || (lvl == LEVELS-1);

            if (IS_REG_BOUNDARY) begin : reg_stage
                always_ff @(posedge clk) begin
                    if (rst) begin
                        for (int i = 0; i < SIZES[lvl+1]; i++) begin
                            tree_r[lvl+1][i] <= '0;
                        end
                    end else begin
                        for (int i = 0; i < SIZES[lvl+1]; i++) begin
                            tree_r[lvl+1][i] <= tree_w[lvl+1][i];
                        end
                    end
                end
            end else begin : wire_stage
                for (genvar i = 0; i < SIZES[lvl+1]; i++) begin : passthru_wire
                    assign tree_r[lvl+1][i] = tree_w[lvl+1][i];
                end
            end
        end
    endgenerate

    assign sum_out = tree_r[LEVELS][0];
    assign carry_out = tree_r[LEVELS][1];

endmodule
