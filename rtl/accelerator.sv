`include "defs.svh"

module accelerator(
    input clk,
    input rst,

    input logic restart,
    input State st_init,

    input word_t dt,
    input word_t tend,

    output State st_out,
    output logic done,
    output word_t state_counter
);

    localparam num_cycles = (`N + `NUMPIPES - 1)/`NUMPIPES;

    // FSM STATES
    localparam logic [2:0] S_IDLE       = 3'd0;
    localparam logic [2:0] S_KICKDRIFT  = 3'd1;
    localparam logic [2:0] S_FORCE      = 3'd2;
    localparam logic [2:0] S_SECONDKICK = 3'd3;
    localparam logic [2:0] S_DONE       = 3'd4;
    logic [2:0] fsm;

    word_t [2:0] v_half [`N_PAD-1:0];

    logic pos_v [`NUMPIPES-1:0];
    logic acc_v [`NUMPIPES-1:0];
    logic vel_v [`NUMPIPES-1:0];

    logic kd_restart, fe_restart, sk_restart;
    logic kd_done, fe_done, sk_done;
    word_t cycle_ctr;
    word_t t;
    word_t t_next;

    logic commit_ready;

    localparam NUM_DIV_STAGES = 8;
    word_t num_total_steps;
    word_t num_total_steps_m1;
    word_t div_remainder;
    logic div_by_zero;

    DW_div_pipe #(
        .a_width(`WORDBITS),
        .b_width(`WORDBITS),
        .tc_mode(1),
        .rem_mode(1),
        .num_stages(NUM_DIV_STAGES),
        .stall_mode(1),
        .rst_mode(1)
    ) total_steps_div (
        .clk(clk),
        .rst_n(~rst),
        .en(1'b1),
        .a(tend + dt - 1),
        .b(dt),
        .quotient(num_total_steps),
        .remainder(div_remainder),
        .divide_by_0(div_by_zero)
    );

    // num_total_steps - 1 precomputed once so more_steps is a bare compare
    // against state_counter, no per-cycle addition at all.
    assign num_total_steps_m1 = num_total_steps - 1;

    PaddedState cur_state;
    PaddedState next_state;

    // tracks cycle_ctr combinationally (a module-scope declaration assignment
    // would only initialize once at time 0, not follow cycle_ctr) so it's
    // always the base index of the batch currently in flight
    int jump;

    // per-lane outputs for the jump-indexed array fields below: a module
    // output port can't connect directly to a variable-indexed array element
    // (the connection is resolved at elaboration time, before jump has a
    // value), so each lane drives a fixed (genvar-indexed) wire here and a
    // always_ff scatters it into the padded array using jump
    word_t [2:0] r_new_lane [`NUMPIPES-1:0];
    word_t [2:0] v_half_lane [`NUMPIPES-1:0];

    word_t [2:0] a_out_lane [`NUMPIPES-1:0];

    word_t [2:0] v_new_lane [`NUMPIPES-1:0];

    genvar i;
    generate
        for (i = 0; i < `NUMPIPES; i++) begin : KD
            pos_module pos_i (
                .clk,
                .rst,
                .restart(kd_restart),
                .r_old(cur_state.r[jump+i]),
                .v_old(cur_state.v[jump+i]),
                .a_old(cur_state.a[jump+i]),
                .dt(dt),
                .r_new(r_new_lane[i]),
                .v_half(v_half_lane[i]),
                .pos_valid(pos_v[i])
            );
        end
    endgenerate

    generate
        for (i = 0; i < `NUMPIPES; i++) begin : FE
            accel_module acc_i (
                .clk,
                .rst,
                .restart(fe_restart),
                .r_new(next_state.r),
                .m(cur_state.m),
                .p_i($clog2(`N_PAD)'(jump+i)),
                .a_out(a_out_lane[i]),
                .acc_valid(acc_v[i])
            );
        end
    endgenerate

    generate
        for (i = 0; i < `NUMPIPES; i++) begin : SK
            vel_module vel_i (
                .clk,
                .rst,
                .restart(sk_restart),
                .v_half(v_half[jump+i]),
                .a_new(next_state.a[jump+i]),
                .dt(dt),
                .v_new(v_new_lane[i]),
                .vel_valid(vel_v[i])
            );
        end
    endgenerate

    // scatter each batch's lane outputs into their jump-indexed slot, gated
    // on both that phase's own done pulse AND the FSM actually being in that
    // phase -- pos_valid/acc_valid/vel_valid latch high and never self-clear,
    // and accel_module's in_ctr saturates instead of idling once its own
    // restart input drops, so it can spuriously re-accumulate (over the
    // zero-mass padding bodies) and re-pulse acc_valid well after the FSM
    // has already moved to the next phase; scoping each scatter to its phase
    // matches how kd_restart/fe_restart/sk_restart are already scoped above
    always_ff @(posedge clk) begin
        if (restart) begin
            for (int k = `N; k < `N_PAD; k++) begin
                next_state.r[k] <= 0;
                next_state.m[k]  <= 0;
            end
        end

        if (fsm == S_KICKDRIFT && kd_done) begin
            for (int lane = 0; lane < `NUMPIPES; lane++) begin
                next_state.r[jump+lane] <= r_new_lane[lane];
                v_half[jump+lane] <= v_half_lane[lane];
                next_state.m[jump+lane] <= cur_state.m[jump+lane];
            end
        end

        if (fsm == S_FORCE && fe_done) begin
            for (int lane = 0; lane < `NUMPIPES; lane++) begin
                next_state.a[jump+lane] <= a_out_lane[lane];
            end
        end

        if (fsm == S_SECONDKICK && sk_done) begin
            for (int lane = 0; lane < `NUMPIPES; lane++) begin
                next_state.v[jump+lane] <= v_new_lane[lane];
            end
        end
    end


    logic more_steps;
    logic last_cycle;

    always_comb begin
        jump = cycle_ctr*`NUMPIPES;

        kd_done = pos_v[0];
        fe_done = acc_v[0];
        sk_done = vel_v[0];
        more_steps = state_counter < num_total_steps_m1;
        last_cycle = (cycle_ctr == num_cycles-1);

        kd_restart = 0;
        fe_restart = 0;
        sk_restart = 0;

        case (fsm)
            S_IDLE: kd_restart = restart;

            S_KICKDRIFT: begin
                kd_restart = kd_done && !last_cycle;   // next batch, same phase
                fe_restart = kd_done && last_cycle;    // all batches tiled, start force on batch 0
            end

            S_FORCE: begin
                fe_restart = fe_done && !last_cycle;
                sk_restart = fe_done && last_cycle;
            end

            S_SECONDKICK: begin
                sk_restart = sk_done && !last_cycle;
                kd_restart = commit_ready && more_steps;
            end

            default: ;
        endcase
    end

    // delaying the commit by one cycle lets the scatter land first
    always_ff @(posedge clk) begin
        if (rst) commit_ready <= 0;
        else commit_ready <= (fsm == S_SECONDKICK) && sk_done && last_cycle;
    end

    // t+dt computed continuously (not gated on commit_ready) so it's already
    // settled -- with the full slack of a KICKDRIFT+FORCE+SECONDKICK step to
    // spare -- by the time S_SECONDKICK's commit actually needs it, instead
    // of racing the clock on the same cycle as the commit.
    always_ff @(posedge clk) begin
        if (rst) t_next <= 0;
        else t_next <= t + dt;
    end

    // tiling N to NUMPIPES: advance cycle_ctr through each batch of a phase,
    // wrapping back to 0 once the phase has covered all N particles
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_ctr <= 0;
        end else begin
            case (fsm)
                S_KICKDRIFT:  if (kd_done) cycle_ctr <= last_cycle ? 0 : cycle_ctr + 1;
                S_FORCE:      if (fe_done) cycle_ctr <= last_cycle ? 0 : cycle_ctr + 1;
                S_SECONDKICK: if (sk_done && !commit_ready) cycle_ctr <= last_cycle ? 0 : cycle_ctr + 1;
                default: ;
            endcase
        end
    end


    // control FSM + buffer latching
    always_ff @(posedge clk) begin
        if (rst) begin
            fsm  <= S_IDLE;
            t    <= 0;
            done <= 0;
            state_counter <= 0;
        end else begin
            case (fsm)
                S_IDLE: begin
                    if (restart) begin
                        // copy the real N bodies in; zero-pad the rest (mass 0 -> no force in or out)
                        for (int k = 0; k < `N_PAD; k++) begin
                            if (k < `N) begin
                                cur_state.r[k] <= st_init.r[k];
                                cur_state.v[k] <= st_init.v[k];
                                cur_state.a[k] <= st_init.a[k];
                                cur_state.m[k]  <= st_init.m[k];
                            end else begin
                                cur_state.r[k] <= 0;
                                cur_state.v[k] <= 0;
                                cur_state.a[k] <= 0;
                                cur_state.m[k]  <= 0;
                            end
                        end
                        t    <= 0;
                        done <= 0;
                        state_counter <= 0;
                        fsm  <= S_KICKDRIFT;
                    end
                end

                // reads A; on done with the last batch, latch r_new + v_half into B, launch force
                S_KICKDRIFT: begin
                    if (kd_done && last_cycle) fsm <= S_FORCE;
                end

                // reads B.r/.m; on done with the last batch, latch a_new into B, launch second kick
                S_FORCE: begin
                    if (fe_done && last_cycle) fsm <= S_SECONDKICK;
                end

                // reads B.v(=v_half) + B.a; overwrite B.v with v_new, commit B -> A, tick t
                S_SECONDKICK: begin
                    if (commit_ready) begin
                        cur_state <= next_state;
                        t    <= t_next;
                        state_counter <= state_counter + 1;
                        if (more_steps) begin
                            fsm <= S_KICKDRIFT;
                        end else begin
                            done <= 1;
                            fsm  <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    done <= 1;
                end

                default: fsm <= S_IDLE;
            endcase
        end
    end

    // only the first N entries of the padded state are real bodies
    generate
        for (i = 0; i < `N; i++) begin : COPYOUT
            assign st_out.r[i] = cur_state.r[i];
            assign st_out.v[i] = cur_state.v[i];
            assign st_out.a[i] = cur_state.a[i];
            assign st_out.m[i]  = cur_state.m[i];
        end
    endgenerate

endmodule
