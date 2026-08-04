`include "defs.svh"

// Checks inv_pwr_3d2_unit's staged msb scan + absolute-msb reduction against a
// straightforward reference scan of the whole 64-bit word, including the
// all-zeros case and every single-bit position.
module msb_abs_tb;
    logic clk = 0;
    logic rst;
    dword_t x;
    logic valid;
    dword_t result;

    always #5 clk = ~clk;

    inv_pwr_3d2_unit #(.ITERS(2), .LATENCY(50)) dut (
        .clk, .rst, .x, .restart(1'b0), .valid, .result
    );

    function automatic int ref_msb(dword_t v);
        ref_msb = -1;
        for (int i = 0; i < `DWORDBITS; i++) if (v[i]) ref_msb = i;
    endfunction

    int fails = 0;
    task automatic check(dword_t v, string label);
        int expect_msb;
        x = v;
        @(posedge clk);          // latch msb_reg for this x
        #1;                      // msb_abs is comb off msb_reg
        expect_msb = ref_msb(v);
        if (dut.msb_abs !== word_t'(expect_msb)) begin
            $display("  FAIL %-24s x=%h  msb_abs=%0d  expected=%0d", label, v, dut.msb_abs, expect_msb);
            fails++;
        end
    endtask

    initial begin
        rst = 1; x = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("checking absolute msb (MSB_STAGES=%0d, MSB_SLICE=%0d):", dut.MSB_STAGES, dut.MSB_SLICE);

        // every single-bit position
        for (int b = 0; b < `DWORDBITS; b++) begin
            check(dword_t'(1) << b, $sformatf("single bit %0d", b));
        end

        // all zeros -> -1
        check(64'h0, "all zeros");

        // a set bit in a low window plus the true msb in a higher window:
        // catches a reduction that returns the lowest hit instead of highest
        check(64'h0000_0000_0000_8001, "bits 0,15");
        check(64'h0000_0001_0000_8001, "bits 0,15,32");
        check(64'h0080_0001_0000_8001, "bits 0,15,32,55");
        check(64'hFFFF_FFFF_FFFF_FFFF, "all ones");
        check(64'h8000_0000_0000_0000, "top bit only");
        // window-boundary neighbours
        for (int b = 1; b < `DWORDBITS/16; b++) begin
            check(dword_t'(1) << (16*b - 1), $sformatf("bit %0d (window end)", 16*b - 1));
            check(dword_t'(1) << (16*b),     $sformatf("bit %0d (window start)", 16*b));
        end

        if (fails == 0) $display("  ALL PASS");
        else            $display("  %0d FAILURE(S)", fails);
        $finish;
    end
endmodule
