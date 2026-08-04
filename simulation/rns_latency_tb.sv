`include "defs.svh"

// Measure rsqrt_newton_step's exact a/y-to-step_out latency directly,
// rather than trusting the "3*DWORDMULTLATENCY" comment by hand.
module rns_latency_tb;
    logic clk = 0;
    logic rst;
    dword_t a, y;
    dword_t step_out;

    always #5 clk = ~clk;

    rsqrt_newton_step dut (.clk, .rst, .a, .y, .step_out);

    dword_t aBase, yBase, aMark, yMark;
    int cycn = 0;
    int mark_cyc = -1;

    always @(posedge clk) begin
        #1;
        $display("cyc=%0d a=%0d y=%0d step_out=%0d", cycn, dut.a, dut.y, step_out);
        cycn++;
    end

    initial begin
        aBase = dword_t'(1) <<< `SEEDFRAC;   // ~1.0
        yBase = dword_t'(1) <<< `SEEDFRAC;   // ~1.0
        aMark = dword_t'(3) <<< (`SEEDFRAC-2); // 0.75, distinct
        yMark = dword_t'(1) <<< (`SEEDFRAC-1); // 0.5, distinct

        rst = 1; a = aBase; y = yBase;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (20) @(posedge clk);   // let it settle to steady state on base

        mark_cyc = cycn;
        $display(">>> alternating base/mark continuously from cyc=%0d", cycn);
        for (int i = 0; i < 40; i++) begin
            if (i[0]) begin a = aMark; y = yMark; end
            else begin a = aBase; y = yBase; end
            @(posedge clk);
        end

        repeat (30) @(posedge clk);
        $finish;
    end
endmodule
