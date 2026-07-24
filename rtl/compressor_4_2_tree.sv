`include "defs.svh"


module compressor_4_2_tree #(parameter WIDTH = 64, parameter TRIPLES = 16) (
    input clk,
    input rst,

    input logic [WIDTH-1:0] partial_prod [TRIPLES-1:0],
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

                for (genvar b = 0; b < WIDTH; b++) begin : col
                    wire s_bit, c_bit, co_bit;    // individual wires per instance
                    wire ci_bit;

                    if (b == 0) begin : ci_head
                        assign ci_bit = 1'b0;
                    end else begin : ci_tail
                        assign ci_bit = cout_w[b-1];
                    end

                    compressor_4_2 u_comp (
                        .x1   (tree_r[lvl][grp*4+0][b]),
                        .x2   (tree_r[lvl][grp*4+1][b]),
                        .x3   (tree_r[lvl][grp*4+2][b]),
                        .x4   (tree_r[lvl][grp*4+3][b]),
                        .ci  (ci_bit),
                        .sum  (s_bit),
                        .carry(c_bit),
                        .co (co_bit)
                    );

                    assign sum_w[b]   = s_bit;
                    assign carry_w[b] = c_bit;
                    assign cout_w[b]  = co_bit;
                end

                assign tree_w[lvl+1][grp*2] = sum_w;
                assign tree_w[lvl+1][grp*2+1] = {carry_w[WIDTH-2:0], 1'b0};
            end

            for (rdr = 0; rdr < REMAINDER; rdr++) begin : passthrough
                assign tree_w[lvl+1][GROUPS*2 + rdr] = tree_r[lvl][GROUPS*4 + rdr];
            end

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
        end
    endgenerate 

    assign sum_out = tree_r[LEVELS][0];
    assign carry_out = tree_r[LEVELS][1];

endmodule
