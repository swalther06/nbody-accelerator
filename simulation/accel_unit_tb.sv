`timescale 1ns / 1ps
`include "../rtl/defs.svh"

module accel_unit_tb;

    localparam int ITERS = 2;
    localparam int CLK_PERIOD = 10;

    // best-known pipeline latency (cycles from an (r_i,r_j,m_j) input being
    // applied to a_i_out settling); bump this if latency_probe below reports
    // the DUT settling later than this.
    localparam int LATENCY = 45;

    logic clk;
    logic rst;
    logic restart;
    word_t [2:0] r_i, r_j;
    word_t m_j;
    word_t [2:0] a_i_out;
    logic accel_valid;

    initial clk = 0;

    accel_unit #(.ITERS(ITERS)) dut (
        .clk, .rst, .restart, .r_i, .r_j, .m_j, .a_i_out, .accel_valid
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    int errors = 0;
    int checked = 0;

    function word_t toword(real r);
        longint li;
        li = longint'(r * (2.0**`FRACBITS));
        toword = word_t'(li);
    endfunction
    function real fromword(word_t w);
        fromword = real'(w) / real'(1<<`FRACBITS);
    endfunction

    // reference: a_i = m_j * (r_j - r_i) / |r_j - r_i|^1.5, softened by EPS_SQUARED
    function real expected_a(real ri[3], real rj[3], real mj, int comp);
        real d[3], denom;
        d[0] = rj[0]-ri[0]; d[1] = rj[1]-ri[1]; d[2] = rj[2]-ri[2];
        denom = d[0]*d[0] + d[1]*d[1] + d[2]*d[2] + 1.0/1000000.0;
        expected_a = mj * d[comp] * (denom ** -1.5);
    endfunction

    // all stimulus-driving and output-sampling below happens a hair (#1)
    // after the clock edge, not right at it -- see multiplier_tb.sv for why.

    // applies one (r_i,r_j,m_j), waits LATENCY cycles, and checks a_i_out
    // against the reference acceleration. non-pipelined (one vector fully
    // drains before the next is applied) -- simple and unambiguous while the
    // DUT's timing is still being pinned down.
    task automatic check(real ri[3], real rj[3], real mj);
        real exp[3];
        for (int c = 0; c < 3; c++) exp[c] = expected_a(ri, rj, mj, c);

        @(posedge clk);
        #1;
        for (int c = 0; c < 3; c++) begin
            r_i[c] = toword(ri[c]);
            r_j[c] = toword(rj[c]);
        end
        m_j = toword(mj);

        repeat (LATENCY) @(posedge clk);
        #1;

        checked++;
        for (int c = 0; c < 3; c++) begin
            real got, err;
            got = fromword(a_i_out[c]);
            err = got - exp[c];
            if (err > 0.01 || err < -0.01) begin
                errors++;
                $display("FAIL: ri=(%0f,%0f,%0f) rj=(%0f,%0f,%0f) mj=%0f  comp=%0d expected=%0f got=%0f",
                    ri[0],ri[1],ri[2], rj[0],rj[1],rj[2], mj, c, exp[c], got);
            end
        end
        if (!accel_valid)
            $display("WARNING: accel_valid is low after waiting LATENCY=%0d cycles (ri=(%0f,%0f,%0f))", LATENCY, ri[0],ri[1],ri[2]);
    endtask

    // sweeps LATENCY_MAX cycles after a single fixed input to show exactly
    // when (and whether) a_i_out settles and accel_valid asserts -- run this
    // first if LATENCY above looks wrong.
    localparam int LATENCY_MAX = 90;
    task automatic latency_probe(real ri[3], real rj[3], real mj);
        real exp[3];
        for (int c = 0; c < 3; c++) exp[c] = expected_a(ri, rj, mj, c);

        @(posedge clk);
        #1;
        for (int c = 0; c < 3; c++) begin
            r_i[c] = toword(ri[c]);
            r_j[c] = toword(rj[c]);
        end
        m_j = toword(mj);

        $display("--- latency probe: ri=(%0f,%0f,%0f) rj=(%0f,%0f,%0f) mj=%0f expected=(%0f,%0f,%0f) ---",
            ri[0],ri[1],ri[2], rj[0],rj[1],rj[2], mj, exp[0],exp[1],exp[2]);
        for (int cyc = 1; cyc <= LATENCY_MAX; cyc++) begin
            real got[3];
            bit match;
            @(posedge clk);
            #1;
            match = 1;
            for (int c = 0; c < 3; c++) begin
                got[c] = fromword(a_i_out[c]);
                if (got[c]-exp[c] > 0.001 || got[c]-exp[c] < -0.001) match = 0;
            end
            $display("  cycle %0d: a_i_out=(%0f,%0f,%0f) accel_valid=%0d (%s)",
                cyc, got[0], got[1], got[2], accel_valid, match ? "MATCH" : "no match");
        end
    endtask

    initial begin
        rst = 1;
        restart = 0;
        r_i = '{default:0};
        r_j = '{default:0};
        m_j = 0;
        repeat (3) @(posedge clk);
        #1;
        rst = 0;
        restart = 1;
        @(posedge clk);
        #1;
        restart = 0;

        // uncomment to characterize the DUT's real latency before trusting
        // LATENCY above:
        // latency_probe('{0.0,0.0,0.0}, '{1.5,0.5,0.25}, 1.0);

        // directed cases -- i at origin unless noted, various j offsets/masses
        check('{0.0,0.0,0.0}, '{1.5,0.5,0.25}, 1.0);
        check('{0.0,0.0,0.0}, '{-1.5,0.5,-0.25}, 1.0);
        check('{0.0,0.0,0.0}, '{2.0,0.0,0.0}, 1.0);
        check('{0.0,0.0,0.0}, '{0.0,2.0,0.0}, 2.5);
        check('{0.0,0.0,0.0}, '{0.0,0.0,2.0}, 0.5);
        check('{1.0,-1.0,0.5}, '{-1.0,1.0,-0.5}, 1.0);
        check('{0.97,-0.24,0.0}, '{-0.97,0.24,0.0}, 1.0);   // figure8-scale separation
        check('{0.0,0.0,0.0}, '{10.0,10.0,10.0}, 5.0);      // far/weak
        check('{0.0,0.0,0.0}, '{0.05,0.0,0.0}, 1.0);        // close/strong

        // randomized
        for (int i = 0; i < 100; i++) begin
            real ri[3], rj[3], mj;
            ri[0] = ($urandom_range(0,2000)-1000)/1000.0;
            ri[1] = ($urandom_range(0,2000)-1000)/1000.0;
            ri[2] = ($urandom_range(0,2000)-1000)/1000.0;
            rj[0] = ri[0] + ($urandom_range(0,2000)-1000)/500.0 + 0.5;
            rj[1] = ri[1] + ($urandom_range(0,2000)-1000)/500.0 + 0.5;
            rj[2] = ri[2] + ($urandom_range(0,2000)-1000)/500.0 + 0.5;
            mj = ($urandom_range(1,5000))/1000.0;
            check(ri, rj, mj);
        end

        $display("=== accel_unit_tb: %0d checked, %0d errors ===", checked, errors);
        if (errors == 0 && checked > 0) $display("PASS");
        else $display("FAIL");
        $finish;
    end

endmodule
