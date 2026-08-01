`timescale 1ns / 1ps

module multiplier_tb;

    localparam int WIDTH = 32;
    localparam int CLK_PERIOD = 10;

    // best-known pipeline latency (cycles from an input being applied to its
    // result appearing on p); bump this if latency_probe below reports the
    // DUT settling later than this.
    localparam int LATENCY = 4;

    logic clk;
    logic rst;
    logic signed [WIDTH-1:0] m, q;
    logic signed [2*WIDTH-1:0] p;

    initial clk = 0;

    rad4_booth_reduction_multiplier #(.WIDTH(WIDTH)) dut (
        .clk, .rst, .m, .q, .p
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    int errors = 0;
    int checked = 0;

    // all stimulus-driving and p-sampling below happens a hair (#1) after the
    // clock edge, not right at it -- driving/sampling exactly at the same
    // edge the DUT's always_ff blocks trigger on is a classic blocking-vs-
    // nonblocking race that can silently shift the apparent latency by a
    // cycle depending on simulator scheduling order.

    // applies one (m,q) pair, waits LATENCY cycles, and checks p against the
    // reference product. non-pipelined (one vector fully drains before the
    // next is applied) -- simple and unambiguous while the DUT's timing is
    // still being pinned down.
    task automatic check(input logic signed [WIDTH-1:0] m_in, input logic signed [WIDTH-1:0] q_in);
        logic signed [2*WIDTH-1:0] expected;
        expected = m_in * q_in;

        @(posedge clk);
        #1;
        m = m_in;
        q = q_in;

        repeat (LATENCY) @(posedge clk);
        #1;

        checked++;
        if (p !== expected) begin
            errors++;
            $display("FAIL: m=%0d q=%0d  expected=%0d  got=%0d (hex exp=%h got=%h)",
                m_in, q_in, expected, p, expected, p);
        end
    endtask

    // sweeps LATENCY_MAX cycles after a single fixed input to show exactly
    // when (and whether) p settles to the correct value -- run this first if
    // LATENCY above looks wrong.
    localparam int LATENCY_MAX = 20;
    task automatic latency_probe(input logic signed [WIDTH-1:0] m_in, input logic signed [WIDTH-1:0] q_in);
        logic signed [2*WIDTH-1:0] expected;
        expected = m_in * q_in;

        @(posedge clk);
        #1;
        m = m_in;
        q = q_in;

        $display("--- latency probe: m=%0d q=%0d expected=%0d ---", m_in, q_in, expected);
        for (int cyc = 1; cyc <= LATENCY_MAX; cyc++) begin
            @(posedge clk);
            #1;
            $display("  cycle %0d: p=%0d (%s)", cyc, p, (p === expected) ? "MATCH" : (p === 'x ? "X" : "no match"));
        end
    endtask

    initial begin
        rst = 1;
        m = 0; q = 0;
        repeat (3) @(posedge clk);
        #1;
        rst = 0;

        // uncomment to characterize the DUT's real latency before trusting
        //LATENCY above:
        //latency_probe(64'sd5, 64'sd7);

        // directed edge cases
        check(64'sd0,  64'sd0);
        check(64'sd1,  64'sd1);
        check(64'sd1,  -64'sd1);
        check(-64'sd1, -64'sd1);
        check(64'sd5,  64'sd7);
        check(-64'sd5, 64'sd7);
        check(64'sd5,  -64'sd7);
        check(-64'sd5, -64'sd7);
        check({1'b0, {(WIDTH-1){1'b1}}}, 64'sd1);                    // max positive * 1
        check({1'b1, {(WIDTH-1){1'b0}}}, 64'sd1);                    // min negative * 1
        check({1'b0, {(WIDTH-1){1'b1}}}, -64'sd1);                   // max positive * -1
        check({1'b1, {(WIDTH-1){1'b0}}}, {1'b1, {(WIDTH-1){1'b0}}}); // min negative * min negative
        check(64'sd123456789, -64'sd987654321);

        // randomized
        for (int i = 0; i < 200; i++) begin
            logic signed [WIDTH-1:0] rm, rq;
            rm = {$urandom, $urandom};
            rq = {$urandom, $urandom};
            check(rm, rq);
        end

        $display("=== multiplier_tb: %0d checked, %0d errors ===", checked, errors);
        if (errors == 0 && checked > 0) $display("PASS");
        else $display("FAIL");
        $finish;
    end

endmodule
