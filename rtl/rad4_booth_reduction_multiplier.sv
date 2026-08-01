`include "defs.svh"

module rad4_booth_reduction_multiplier #(parameter WIDTH=32)(
    input clk,
    input rst,
    input logic signed [WIDTH-1:0] m,
    input logic signed [WIDTH-1:0] q,

    output logic signed [2*WIDTH-1:0] p
);  
    localparam TRIPLES = WIDTH/2;
    logic [2:0] triplet [TRIPLES-1:0];
    logic signed [2*WIDTH-1:0] partial_prod [TRIPLES-1:0];
    logic signed [2*WIDTH-1:0] partial_prod_reg [TRIPLES-1:0];

    always_comb begin : triplet_muxing
        for (int i = 0; i < TRIPLES; i++) begin
            if (i == 0) triplet[i][0] = 1'b0;
            else triplet[i][0] = q[2*i-1];

            triplet[i][1] = q[2*i];
            triplet[i][2] = q[2*i+1];
        end
    end

    always_comb begin : partial_product_generation
        for (int i = 0; i < TRIPLES; i++) begin
            case (triplet[i])
                3'b000: partial_prod[i] = '0;
                3'b001: partial_prod[i] = {{WIDTH{m[WIDTH-1]}},m};
                3'b010: partial_prod[i] = {{WIDTH{m[WIDTH-1]}},m};
                3'b011: partial_prod[i] = {{(WIDTH-1){m[WIDTH-1]}},m, 1'b0};
                3'b100: partial_prod[i] = ~{{(WIDTH-1){m[WIDTH-1]}},m, 1'b0} + 1;
                3'b101: partial_prod[i] = ~{{WIDTH{m[WIDTH-1]}},m} + 1;
                3'b110: partial_prod[i] = ~{{WIDTH{m[WIDTH-1]}},m} + 1;
                3'b111: partial_prod[i] = '0;
                default: partial_prod[i] = '0; // never gets here
            endcase

            partial_prod[i] = partial_prod[i] <<< (2*i);
        end
    end

    logic [2*WIDTH-1:0] sum_out;
    logic [2*WIDTH-1:0] carry_out; 
    compressor_4_2_tree #(.WIDTH(2*WIDTH), .TRIPLES(TRIPLES)) compressor_tree  (
        .clk,
        .rst,

        .partial_prod(partial_prod_reg),
        .sum_out,
        .carry_out
    );

    logic signed [2*WIDTH-1:0] p_reg;
    always_ff @(posedge clk) begin
        if (rst) begin
            partial_prod_reg <= '{default: 0};
            p_reg <= '0;
        end else begin
            partial_prod_reg <= partial_prod;
            p_reg <= sum_out + carry_out;
        end
    end


    assign p = p_reg;


endmodule
