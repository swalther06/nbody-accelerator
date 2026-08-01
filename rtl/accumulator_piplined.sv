`include "defs.svh"

module accumulator_piplined #(parameter WIDTH = 32, parameter NUM_INPS = 4) (
    input clk,
    input rst,
    input logic signed [WIDTH-1:0] inp [NUM_INPS-1:0],
    output logic signed [WIDTH-1:0] acc
);
    localparam LEVELS = $clog2(NUM_INPS)-1;
    localparam LATENCY = (LEVELS+1)/2 + 1;

    logic [WIDTH-1:0] sum_out;
    logic [WIDTH-1:0] carry_out;

    compressor_4_2_tree #(.WIDTH(WIDTH), .TRIPLES(NUM_INPS)) compressor_tree (
        .clk,
        .rst,

        .partial_prod(inp),
        .sum_out,
        .carry_out
    );

    logic signed [WIDTH-1:0] acc_reg;
    always_ff @(posedge clk) begin
        if (rst) acc_reg <= 0;
        else acc_reg <= sum_out + carry_out;
    end

    assign acc = acc_reg;

endmodule