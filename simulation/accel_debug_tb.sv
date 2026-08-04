`timescale 1ns / 1ps
`include "../rtl/defs.svh"

// Records the observed dynamic range of every variable-shift operand and
// shift amount inside one inv_pwr_3d2_unit over a real figure8 run, so the
// required width of each barrel shifter can be read off measured data rather
// than assumed. Reports the signed bit-width each value actually needs.
module accel_debug_tb;

    logic clk;
    logic rst;
    logic restart;
    State st_init;
    word_t dt;
    word_t tend;
    State st_out;
    logic done;
    word_t state_counter;

    accelerator dut (
        .clk(clk), .rst(rst), .restart(restart), .st_init(st_init),
        .dt(dt), .tend(tend), .st_out(st_out), .done(done),
        .state_counter(state_counter)
    );

    always #5 clk = ~clk;

    word_t st_init_mem [10*`N-1:0];

    // probe one inv_pwr instance
    `define IP dut.FE[0].acc_i.genblk1[0].au.ip

    longint a_min = 0, a_max = 0;
    longint rs_min = 0, rs_max = 0;
    longint x_min = 0, x_max = 0;
    int ns_min = 999, ns_max = -999;
    int half_min = 999, half_max = -999;
    int sh_min = 999, sh_max = -999;
    int msb_min = 999, msb_max = -999;
    int ns_cur, half_cur, sh_cur;
    logic sampling = 0;

    // signed bit-width needed to represent v (including sign bit)
    function automatic int sbits(longint v);
        longint m;
        m = (v < 0) ? -v : v;
        sbits = 1;                       // sign bit
        while (m > 0) begin
            sbits++;
            m = m >> 1;
        end
    endfunction

    always @(posedge clk) begin
        #1;
        if (sampling && !rst) begin
            if (`IP.a       < a_min)  a_min  = `IP.a;
            if (`IP.a       > a_max)  a_max  = `IP.a;
            if (`IP.rsqrt_out < rs_min) rs_min = `IP.rsqrt_out;
            if (`IP.rsqrt_out > rs_max) rs_max = `IP.rsqrt_out;
            if (`IP.x       < x_min)  x_min  = `IP.x;
            if (`IP.x       > x_max)  x_max  = `IP.x;
            ns_cur   = `IP.norm_sign_reg  ? -int'(`IP.norm_mag_reg)  : int'(`IP.norm_mag_reg);
            half_cur = `IP.half_sign_delay[`IP.ITERSCYCLES] ? -int'(`IP.half_mag_delay[`IP.ITERSCYCLES])
                                                            :  int'(`IP.half_mag_delay[`IP.ITERSCYCLES]);
            sh_cur   = `IP.shift_sign_reg ? -int'(`IP.shift_mag_reg) : int'(`IP.shift_mag_reg);
            if (ns_cur < ns_min) ns_min = ns_cur;
            if (ns_cur > ns_max) ns_max = ns_cur;
            if (half_cur < half_min) half_min = half_cur;
            if (half_cur > half_max) half_max = half_cur;
            if (sh_cur < sh_min) sh_min = sh_cur;
            if (sh_cur > sh_max) sh_max = sh_cur;
            if (`IP.msb_abs_reg < msb_min) msb_min = `IP.msb_abs_reg;
            if (`IP.msb_abs_reg > msb_max) msb_max = `IP.msb_abs_reg;
        end
    end

    initial begin
        clk = 0; rst = 1; restart = 0; dt = 0; tend = 0;

        $readmemh("st_init.mem", st_init_mem);
        for (int i = 0; i < `N; i++) begin
            for (int d = 0; d < 3; d++) begin
                st_init.r[i][d] = st_init_mem[d*`N + i];
                st_init.v[i][d] = st_init_mem[(3+d)*`N + i];
                st_init.a[i][d] = st_init_mem[(6+d)*`N + i];
            end
            st_init.m[i] = st_init_mem[9*`N + i];
        end

        #20; rst = 0;
        dt = 32'h000028F6; tend = 32'h00200000;
        #10; restart = 1; #10; restart = 0;

        // skip startup transient, then sample a few hundred real steps
        wait (state_counter >= 2);
        sampling = 1;
        wait (state_counter >= 25);
        sampling = 0;

        $display("");
        $display("=== measured dynamic range over states 2..25 (figure8) ===");
        $display("  x (shifter INPUT)      : [%0d, %0d]  -> needs %0d signed bits", x_min, x_max, sbits(x_max) > sbits(x_min) ? sbits(x_max) : sbits(x_min));
        $display("  msb_abs                : [%0d, %0d]", msb_min, msb_max);
        $display("");
        $display("  -- shift 1: mantissa = x_reg[2] >>/<< shift_reg, masked to %0d bits", `LUTBITS);
        $display("     shift_reg           : [%0d, %0d]", sh_min, sh_max);
        $display("");
        $display("  -- shift 2: a = x_reg[3] >>/<< norm_shift_reg (OUTPUT width in question)");
        $display("     norm_shift_reg      : [%0d, %0d]", ns_min, ns_max);
        $display("     a                   : [%0d, %0d]  -> needs %0d signed bits", a_min, a_max, sbits(a_max) > sbits(a_min) ? sbits(a_max) : sbits(a_min));
        $display("");
        $display("  -- shift 3: rsqrt_out = guess_final >>/<< half_delay (OUTPUT width in question)");
        $display("     half_delay          : [%0d, %0d]", half_min, half_max);
        $display("     rsqrt_out           : [%0d, %0d]  -> needs %0d signed bits", rs_min, rs_max, sbits(rs_max) > sbits(rs_min) ? sbits(rs_max) : sbits(rs_min));
        $finish;
    end
endmodule
