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

    word_t vx_half [`N_PAD-1:0];
    word_t vy_half [`N_PAD-1:0];
    word_t vz_half [`N_PAD-1:0];

    logic [`NUMPIPES-1:0] pos_v;
    logic [`NUMPIPES-1:0] acc_v;
    logic [`NUMPIPES-1:0] vel_v;

    logic kd_restart, fe_restart, sk_restart;
    logic kd_done, fe_done, sk_done;
    word_t cycle_ctr;
    word_t t;

    logic commit_ready;

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
    word_t rx_new_lane [`NUMPIPES-1:0];
    word_t ry_new_lane [`NUMPIPES-1:0];
    word_t rz_new_lane [`NUMPIPES-1:0];
    word_t vx_half_lane [`NUMPIPES-1:0];
    word_t vy_half_lane [`NUMPIPES-1:0];
    word_t vz_half_lane [`NUMPIPES-1:0];

    word_t ax_out_lane [`NUMPIPES-1:0];
    word_t ay_out_lane [`NUMPIPES-1:0];
    word_t az_out_lane [`NUMPIPES-1:0];

    word_t vx_new_lane [`NUMPIPES-1:0];
    word_t vy_new_lane [`NUMPIPES-1:0];
    word_t vz_new_lane [`NUMPIPES-1:0];

    genvar i;
    generate
        for (i = 0; i < `NUMPIPES; i++) begin : KD
            pos_module pos_i (
                .clk,
                .rst,
                .restart(kd_restart),
                .rx_old(cur_state.rx[jump+i]), .ry_old(cur_state.ry[jump+i]), .rz_old(cur_state.rz[jump+i]),
                .vx_old(cur_state.vx[jump+i]), .vy_old(cur_state.vy[jump+i]), .vz_old(cur_state.vz[jump+i]),
                .ax_old(cur_state.ax[jump+i]), .ay_old(cur_state.ay[jump+i]), .az_old(cur_state.az[jump+i]),
                .dt(dt),
                .rx_new(rx_new_lane[i]),  .ry_new(ry_new_lane[i]),  .rz_new(rz_new_lane[i]),
                .vx_half(vx_half_lane[i]), .vy_half(vy_half_lane[i]), .vz_half(vz_half_lane[i]),
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
                .rx_new(next_state.rx), .ry_new(next_state.ry), .rz_new(next_state.rz),
                .m(cur_state.m),
                .p_i($clog2(`N_PAD)'(jump+i)),
                .ax_out(ax_out_lane[i]), .ay_out(ay_out_lane[i]), .az_out(az_out_lane[i]),
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
                .vx_half(vx_half[jump+i]), .vy_half(vy_half[jump+i]), .vz_half(vz_half[jump+i]),
                .ax_new(next_state.ax[jump+i]), .ay_new(next_state.ay[jump+i]), .az_new(next_state.az[jump+i]),
                .dt(dt),
                .vx_new(vx_new_lane[i]), .vy_new(vy_new_lane[i]), .vz_new(vz_new_lane[i]),
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
                next_state.rx[k] <= 0;
                next_state.ry[k] <= 0;
                next_state.rz[k] <= 0;
                next_state.m[k]  <= 0;
            end
        end

        if (fsm == S_KICKDRIFT && kd_done) begin
            for (int lane = 0; lane < `NUMPIPES; lane++) begin
                next_state.rx[jump+lane] <= rx_new_lane[lane];
                next_state.ry[jump+lane] <= ry_new_lane[lane];
                next_state.rz[jump+lane] <= rz_new_lane[lane];
                vx_half[jump+lane] <= vx_half_lane[lane];
                vy_half[jump+lane] <= vy_half_lane[lane];
                vz_half[jump+lane] <= vz_half_lane[lane];
                next_state.m[jump+lane] <= cur_state.m[jump+lane];
            end
        end

        if (fsm == S_FORCE && fe_done) begin
            for (int lane = 0; lane < `NUMPIPES; lane++) begin
                next_state.ax[jump+lane] <= ax_out_lane[lane];
                next_state.ay[jump+lane] <= ay_out_lane[lane];
                next_state.az[jump+lane] <= az_out_lane[lane];
            end
        end

        if (fsm == S_SECONDKICK && sk_done) begin
            for (int lane = 0; lane < `NUMPIPES; lane++) begin
                next_state.vx[jump+lane] <= vx_new_lane[lane];
                next_state.vy[jump+lane] <= vy_new_lane[lane];
                next_state.vz[jump+lane] <= vz_new_lane[lane];
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
        more_steps = (t + dt) < tend;
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
                                cur_state.rx[k] <= st_init.rx[k];
                                cur_state.ry[k] <= st_init.ry[k];
                                cur_state.rz[k] <= st_init.rz[k];
                                cur_state.vx[k] <= st_init.vx[k];
                                cur_state.vy[k] <= st_init.vy[k];
                                cur_state.vz[k] <= st_init.vz[k];
                                cur_state.ax[k] <= st_init.ax[k];
                                cur_state.ay[k] <= st_init.ay[k];
                                cur_state.az[k] <= st_init.az[k];
                                cur_state.m[k]  <= st_init.m[k];
                            end else begin
                                cur_state.rx[k] <= 0;
                                cur_state.ry[k] <= 0;
                                cur_state.rz[k] <= 0;
                                cur_state.vx[k] <= 0;
                                cur_state.vy[k] <= 0;
                                cur_state.vz[k] <= 0;
                                cur_state.ax[k] <= 0;
                                cur_state.ay[k] <= 0;
                                cur_state.az[k] <= 0;
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
                        t    <= t + dt;
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
            assign st_out.rx[i] = cur_state.rx[i];
            assign st_out.ry[i] = cur_state.ry[i];
            assign st_out.rz[i] = cur_state.rz[i];
            assign st_out.vx[i] = cur_state.vx[i];
            assign st_out.vy[i] = cur_state.vy[i];
            assign st_out.vz[i] = cur_state.vz[i];
            assign st_out.ax[i] = cur_state.ax[i];
            assign st_out.ay[i] = cur_state.ay[i];
            assign st_out.az[i] = cur_state.az[i];
            assign st_out.m[i]  = cur_state.m[i];
        end
    endgenerate

endmodule
