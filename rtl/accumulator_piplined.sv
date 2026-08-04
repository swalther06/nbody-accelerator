`include "defs.svh"

module accumulator_piplined #(parameter WIDTH = 32, parameter NUM_INPS = 4) (
    input clk,
    input rst,
    input logic signed [WIDTH-1:0] inp [NUM_INPS-1:0],
    output logic signed [WIDTH-1:0] acc
);
    // This module's input->output latency is `ACC_LATENCY(NUM_INPS) in
    // defs.svh -- deliberately not restated as a localparam here, since a
    // second copy would be dead code that silently disagrees once edited.
    // Consumers size their handshake from the macro; acc_latency_tb.sv checks
    // the macro against this module's measured latency.
    logic signed [WIDTH-1:0] acc_reg;

    generate
    if (NUM_INPS == 1) begin : passthrough

        always_ff @(posedge clk) begin
            if (rst) acc_reg <= 0;
            else acc_reg <= inp[0];
        end
    end else begin : tree
        logic [WIDTH-1:0] sum_out;
        logic [WIDTH-1:0] carry_out;

        compressor_4_2_tree #(.WIDTH(WIDTH), .TRIPLES(NUM_INPS)) compressor_tree (
            .clk,
            .rst,

            .partial_prod(inp),
            .sum_out,
            .carry_out
        );

        always_ff @(posedge clk) begin
            if (rst) acc_reg <= 0;
            else acc_reg <= sum_out + carry_out;
        end
    end
    endgenerate

    assign acc = acc_reg;

endmodule
