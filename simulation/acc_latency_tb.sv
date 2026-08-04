`include "defs.svh"

// Measures accumulator_piplined's true input->output latency by impulse, for
// each NUM_INPS the design might use, and prints it next to the module's own
// LATENCY formula so the two can be checked against each other.
module acc_latency_tb;
    logic clk = 0;
    logic rst;
    always #5 clk = ~clk;

    localparam int K = 12345;

    // one instance per NUM_INPS of interest
    logic signed [`WORDBITS-1:0] in1  [0:0];
    logic signed [`WORDBITS-1:0] in2  [1:0];
    logic signed [`WORDBITS-1:0] in4  [3:0];
    logic signed [`WORDBITS-1:0] in8  [7:0];
    logic signed [`WORDBITS-1:0] in16 [15:0];

    logic signed [`WORDBITS-1:0] acc1, acc2, acc4, acc8, acc16;

    accumulator_piplined #(.WIDTH(`WORDBITS), .NUM_INPS(1))  a1  (.clk, .rst, .inp(in1),  .acc(acc1));
    accumulator_piplined #(.WIDTH(`WORDBITS), .NUM_INPS(2))  a2  (.clk, .rst, .inp(in2),  .acc(acc2));
    accumulator_piplined #(.WIDTH(`WORDBITS), .NUM_INPS(4))  a4  (.clk, .rst, .inp(in4),  .acc(acc4));
    accumulator_piplined #(.WIDTH(`WORDBITS), .NUM_INPS(8))  a8  (.clk, .rst, .inp(in8),  .acc(acc8));
    accumulator_piplined #(.WIDTH(`WORDBITS), .NUM_INPS(16)) a16 (.clk, .rst, .inp(in16), .acc(acc16));

    int c1 = -1, c2 = -1, c4 = -1, c8 = -1, c16 = -1;
    int cyc = 0;
    logic measuring = 0;

    always @(posedge clk) begin
        #1;
        if (measuring) begin
            if (c1  < 0 && acc1  == K) c1  = cyc;
            if (c2  < 0 && acc2  == K) c2  = cyc;
            if (c4  < 0 && acc4  == K) c4  = cyc;
            if (c8  < 0 && acc8  == K) c8  = cyc;
            if (c16 < 0 && acc16 == K) c16 = cyc;
            cyc++;
        end
    end

    int fails = 0;
    task automatic check(int n, int measured, int expected);
        if (measured == expected)
            $display("  NUM_INPS=%0d\t measured=%0d  macro=%0d   OK", n, measured, expected);
        else begin
            $display("  NUM_INPS=%0d\t measured=%0d  macro=%0d   *** MISMATCH ***", n, measured, expected);
            fails++;
        end
    endtask

    task automatic zero_all();
        for (int i = 0; i < 1;  i++) in1[i]  = 0;
        for (int i = 0; i < 2;  i++) in2[i]  = 0;
        for (int i = 0; i < 4;  i++) in4[i]  = 0;
        for (int i = 0; i < 8;  i++) in8[i]  = 0;
        for (int i = 0; i < 16; i++) in16[i] = 0;
    endtask

    initial begin
        rst = 1; zero_all();
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (10) @(negedge clk);   // settle to 0

        // drive on negedge so inputs are stable well before the posedge that
        // samples them (driving at the posedge itself races the always_ff).
        // cyc counts posedges from the first one that sees the impulse, so a
        // single register reports 1, two registers in series report 2.
        cyc = 1;
        measuring = 1;
        in1[0] = K; in2[0] = K; in4[0] = K; in8[0] = K; in16[0] = K;
        @(negedge clk);
        zero_all();

        repeat (20) @(negedge clk);

        $display("measured input->output latency vs `ACC_LATENCY macro:");
        check(1,  c1,  `ACC_LATENCY(1));
        check(2,  c2,  `ACC_LATENCY(2));
        check(4,  c4,  `ACC_LATENCY(4));
        check(8,  c8,  `ACC_LATENCY(8));
        check(16, c16, `ACC_LATENCY(16));
        $display(fails == 0 ? "ALL MATCH" : "%0d MISMATCH(ES)", fails);
        $finish;
    end
endmodule
