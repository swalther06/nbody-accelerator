`include "defs.svh"

module accelerator(
    input clk,
    input rst,

    input logic restart,
    input State st_init,

    input word_t dt,
    input word_t tend,

    output State st_out,
    output logic done
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

    PaddedState cur_state;
    PaddedState next_state;

    int jump = cycle_ctr*`NUMPIPES;

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
                .rx_new(next_state.rx[jump+i]),  .ry_new(next_state.ry[jump+i]),  .rz_new(next_state.rz[jump+i]),
                .vx_half(vx_half[jump+i]), .vy_half(vy_half[jump+i]), .vz_half(vz_half[jump+i]),
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
                .ax_out(next_state.ax[jump+i]), .ay_out(next_state.ay[jump+i]), .az_out(next_state.az[jump+i]),
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
                .vx_new(next_state.vx[jump+i]), .vy_new(next_state.vy[jump+i]), .vz_new(next_state.vz[jump+i]),
                .vel_valid(vel_v[i])
            );
        end
    endgenerate


    logic more_steps;
    logic last_cycle;

    always_comb begin
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
                kd_restart = sk_done && last_cycle && more_steps;
            end

            default: ;
        endcase
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
                S_SECONDKICK: if (sk_done) cycle_ctr <= last_cycle ? 0 : cycle_ctr + 1;
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
                    if (sk_done && last_cycle) begin
                        cur_state <= next_state;
                        t    <= t + dt;
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

    // pass in initial state
    // define `NUMPIPES pos_modules
    // replace state.postitions with nwe positions
    // feed new positions into `NUMPIPES accel_modules
    // replace state.accel with new accelerations
    // feed new accelerations into `NUMPIPES vel_modules
    // replace state.vel with new velocities
    // write state to memory

endmodule
