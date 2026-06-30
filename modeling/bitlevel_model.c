#include "bitlevel_model.h"
#include "orbits.h"

static void inline copy_state(State *dest, const State *src) {
    for (int i = 0; i < N; i++) {
        dest->rx[i] = src->rx[i];
        dest->ry[i] = src->ry[i];
        dest->rz[i] = src->rz[i];
        dest->vx[i] = src->vx[i];
        dest->vy[i] = src->vy[i];
        dest->vz[i] = src->vz[i];
        dest->ax[i] = src->ax[i];
        dest->ay[i] = src->ay[i];
        dest->az[i] = src->az[i];
        dest->m[i] = src->m[i];
    }
}

static void inline create_particle(State *state, int i, 
    int64_t rx, int64_t ry, int64_t rz, int64_t vx, int64_t vy, int64_t vz, int64_t m) {
    state->rx[i] = rx;
    state->ry[i] = ry;
    state->rz[i] = rz;
    state->vx[i] = vx;
    state->vy[i] = vy;
    state->vz[i] = vz;
    state->m[i] = m;
}

static void inline calculate_new_positions(int32_t rx, int32_t ry, int32_t rz,
    int32_t vx, int32_t vy, int32_t vz, int32_t ax, int32_t ay, int32_t az, int32_t dt,
    int32_t* rx_new, int32_t* ry_new, int32_t* rz_new,
    int32_t* vx_half, int32_t* vy_half, int32_t* vz_half) {

        // first half-kick: v_half = v + (a*dt)/2.  a*dt is Q40; >>(FRAC_BITS+1) -> Q20 and halves.
        *vx_half = vx + (int32_t)(((int64_t)ax * dt) >> (FRAC_BITS + 1));
        *vy_half = vy + (int32_t)(((int64_t)ay * dt) >> (FRAC_BITS + 1));
        *vz_half = vz + (int32_t)(((int64_t)az * dt) >> (FRAC_BITS + 1));

        // drift: r_new = r + v_half*dt.  v_half*dt is Q40; >>FRAC_BITS -> Q20 (no halving).
        *rx_new = rx + (int32_t)(((int64_t)(*vx_half) * dt) >> FRAC_BITS);
        *ry_new = ry + (int32_t)(((int64_t)(*vy_half) * dt) >> FRAC_BITS);
        *rz_new = rz + (int32_t)(((int64_t)(*vz_half) * dt) >> FRAC_BITS);
}

static void inline calculate_new_velocity(int32_t vx_half, int32_t vy_half, int32_t vz_half,
    int32_t ax_new, int32_t ay_new, int32_t az_new,
    int32_t* vx_new, int32_t* vy_new, int32_t* vz_new, int32_t dt) {

        // second half-kick: v_new = v_half + (a_new*dt)/2.  Only the a_new*dt term is shifted/halved.
        *vx_new = vx_half + (int32_t)(((int64_t)ax_new * dt) >> (FRAC_BITS + 1));
        *vy_new = vy_half + (int32_t)(((int64_t)ay_new * dt) >> (FRAC_BITS + 1));
        *vz_new = vz_half + (int32_t)(((int64_t)az_new * dt) >> (FRAC_BITS + 1));
}

static void write_states_csv(const State *states, int32_t count, int32_t dt, const char *path) {
    FILE *f = fopen(path, "w");
    if (!f) {
        perror("fopen");
        return;
    }

    fprintf(f, "step,t,particle,rx,ry,rz,vx,vy,vz,ax,ay,az,m\n");

    double dt_real = (double)dt / (double)FRAC_SCALE;
    for (int32_t step = 0; step < count; ++step) {
        const State *s = &states[step];
        double t = step * dt_real;
        for (int i = 0; i < N; ++i) {
            fprintf(f, "%d,%.10g,%d,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g\n",
                step, t, i,
                s->rx[i] / (double)FRAC_SCALE, s->ry[i] / (double)FRAC_SCALE, s->rz[i] / (double)FRAC_SCALE,
                s->vx[i] / (double)FRAC_SCALE, s->vy[i] / (double)FRAC_SCALE, s->vz[i] / (double)FRAC_SCALE,
                s->ax[i] / (double)FRAC_SCALE, s->ay[i] / (double)FRAC_SCALE, s->az[i] / (double)FRAC_SCALE,
                s->m[i]  / (double)FRAC_SCALE);
        }
    }

    fclose(f);
}

static void inline sweep_rsqrts(){
    for (double x = 0.0001; x <= 1000000.0; x *= 1.7) {     // span the range, hit many k values
        int64_t xf = (int64_t)(x * (1LL << DENOM_FRAC));
        int64_t r  = fixed_rsqrt(xf);
        double  got = (double)r / (1LL << SEED_FRAC);
        double  tru = 1.0 / sqrt(x);
        double  rel = (got - tru) / tru;
        printf("x=%9.4f  rsqrt got=%.6f true=%.6f  relerr=%+.2e\n", x, got, tru, rel);
    }
}

int main(int argc, char *argv[]){
    const char *orbit_name = (argc > 1) ? argv[1] : "figure8";

    int32_t t = 0;
    int32_t t_end = 10 << FRAC_BITS;

    State state;
    double dt_real = load_orbit_config(orbit_name, &state);
    int32_t dt = (int32_t)llround(dt_real * (double)FRAC_SCALE);

    seed_accelerations(&state);
    static State states[10000];
    int32_t size = 0;
    states[size++] = state;

    while (t < t_end) {
        State new_state = state;

        State st_half;
        init_state(&st_half);

        for (int i = 0; i < N; ++i) {
            calculate_new_positions(state.rx[i], state.ry[i], state.rz[i],
                state.vx[i], state.vy[i], state.vz[i],
                state.ax[i], state.ay[i], state.az[i], dt,
                &new_state.rx[i], &new_state.ry[i], &new_state.rz[i], 
                &st_half.vx[i], &st_half.vy[i], &st_half.vz[i]);
        }

        for (int i = 0; i < N; ++i) {
            int32_t ax = 0, ay = 0, az = 0;
            calculate_particle_acceleration(i, &new_state, &ax, &ay, &az);
            new_state.ax[i] = ax;
            new_state.ay[i] = ay;
            new_state.az[i] = az;
        }

        for (int i = 0; i < N; ++i) {
            calculate_new_velocity(st_half.vx[i], st_half.vy[i], st_half.vz[i],
                new_state.ax[i], new_state.ay[i], new_state.az[i],
                &new_state.vx[i], &new_state.vy[i], &new_state.vz[i], dt);
        }

        t += dt;
        state = new_state;
        states[size++] = state;
    }

    write_states_csv(states, size, dt, "output/states.csv");

    return 0;
}





