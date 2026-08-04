`include "defs.svh"

// Steady-state alternation test: feed two DISTINCT values (not related by a
// power-of-4 factor, so `a`/mantissa/guess actually differ between them --
// consecutive powers of 4 keep `a` invariant since the msb shift by 2 is
// exactly canceled by norm_shift, which made earlier test runs degenerate)
// continuously, one per cycle, and check the tail of the output stream
// settles into the correct alternating pattern.
module inv_pwr_3d2_tb;
    localparam ITERS = 2;
    localparam EXP_LATENCY = ITERS*`RSQRTMULTLATENCY + 2*`DWORDMULTLATENCY + 6;
    localparam NALT = 80;

    logic clk = 0;
    logic rst;
    logic restart;
    dword_t x;
    logic valid;
    dword_t result;

    always #5 clk = ~clk;

    inv_pwr_3d2_unit #(.ITERS(ITERS), .LATENCY(EXP_LATENCY)) dut (
        .clk, .rst, .x, .restart, .valid, .result
    );

    dword_t altA, altB;
    // altA = 1.0 -> expect 1.0 in Q(SEEDFRAC) = 268435456
    // altB = 2.0 -> expect 2**-1.5 = 0.35355339 in Q(SEEDFRAC) ~= 94906266

    int in_idx, out_idx;
    dword_t results_q [$];
    int cycn = 0;

    always @(posedge clk) begin
        if (valid) results_q.push_back(result);
    end

    always @(posedge clk) begin
        #1;
        $display("cyc=%0d x=%0d msb_reg=%0d a=%0d a_delay0=%0d a_delay12=%0d guess=%0d guess_reg0=%0d guess_reg1=%0d stage0=%0d stage1=%0d rsqrt_out=%0d valid=%b result=%0d",
            cycn, dut.x, dut.msb_reg, dut.a, dut.a_delay[0], dut.a_delay[12], dut.guess, dut.guess_reg[0], dut.guess_reg[1],
            dut.stage_out[0], dut.stage_out[1], dut.rsqrt_out, dut.valid, dut.result);
        cycn++;
    end

    initial begin
        altA = dword_t'(1) <<< `DENOMFRAC;
        altB = dword_t'(1) <<< (`DENOMFRAC + 1);

        rst = 1; restart = 0; x = altA; in_idx = 0;
        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);
        restart = 1;
        @(posedge clk);
        restart = 0;

        for (in_idx = 0; in_idx < NALT; in_idx++) begin
            x = in_idx[0] ? altB : altA;
            @(posedge clk);
        end

        repeat (EXP_LATENCY + 10) @(posedge clk);

        $display("collected %0d results (expected ~%0d)", results_q.size(), NALT);
        $display("altExpA(1.0)=268435456  altExpB(2**-1.5)~=94906266");
        for (out_idx = results_q.size() > 16 ? results_q.size()-16 : 0; out_idx < results_q.size(); out_idx++) begin
            $display("result[%0d]=%0d", out_idx, results_q[out_idx]);
        end
        $finish;
    end
endmodule
