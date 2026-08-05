#include "reference_sim.h"
#include "orbits.h"

// Runs `steps` steps from a pristine copy of `init`; returns elapsed seconds.
// Seeding the accelerations is done before the clock starts so the measurement
// covers steady-state stepping only.
static double time_run(Sim *work, const Sim *init, int steps, double dt,
                       void (*forces)(Sim *)) {
    sim_copy(work, init);
    forces(work);
    const double t0 = now_sec();
    for (int s = 0; s < steps; s++) step(work, dt, forces);
    const double t1 = now_sec();
    return t1 - t0;
}

static void write_csv_row(FILE *fp, const Sim *s, int step_idx, double t) {
    for (int i = 0; i < s->n; i++)
        fprintf(fp, "%d,%.10g,%d,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g,%.10g\n",
                step_idx, t, i, s->rx[i], s->ry[i], s->rz[i],
                s->vx[i], s->vy[i], s->vz[i], s->ax[i], s->ay[i], s->az[i], s->m[i]);
}

int main(int argc, char *argv[]) {
    const char *orbit_name = "figure8";
    const char *csv_path = NULL;
    // REF_STEPS is set by the build (-DREF_STEPS=<n>) so it can be kept in step
    // with the RTL testbench's +steps=<n>; 1500 matches tend=15.0 at dt=0.01.
    #ifndef REF_STEPS
    #define REF_STEPS 1500
    #endif
    int steps = REF_STEPS, reps = 5, synth = 0;
    double hw_cycles = 0.0, hw_period = 0.0, cpu_ghz = 0.0;

    if (steps < 1 || reps < 1) { fprintf(stderr, "--steps and --reps must be >= 1\n"); return 1; }

    Sim init, work;
    double dt;

    if (synth > 0) {
        // Deterministic pseudo-random cloud for scaling studies. All masses are
        // 1.0, unlike the zero-mass padding an orbit config leaves behind.
        sim_alloc(&init, synth);
        sim_alloc(&work, synth);
        uint64_t seed = 0x9E3779B97F4A7C15ULL;
        #define NEXT() (seed = seed*6364136223846793005ULL + 1442695040888963407ULL, \
                        (double)((seed >> 11) & 0xFFFFFFFFULL) / (double)0xFFFFFFFFULL - 0.5)
        for (int i = 0; i < synth; i++) {
            init.rx[i] = NEXT(); init.ry[i] = NEXT(); init.rz[i] = NEXT();
            init.vx[i] = NEXT() * 0.1; init.vy[i] = NEXT() * 0.1; init.vz[i] = NEXT() * 0.1;
            init.ax[i] = init.ay[i] = init.az[i] = 0.0;
            init.m[i]  = 1.0;
        }
        #undef NEXT
        dt = 0.01;
        orbit_name = "(synthetic)";
    } else {
        // Start from the same Q(FRAC_BITS)-quantized values the hardware loads,
        // so this trajectory is directly comparable to the RTL/bitlevel output
        // rather than diverging from a different initial state.
        State st;
        dt = load_orbit_config(orbit_name, &st);
        sim_alloc(&init, N);
        sim_alloc(&work, N);
        for (int i = 0; i < N; i++) {
            init.rx[i] = (double)st.rx[i] / (double)FRAC_SCALE;
            init.ry[i] = (double)st.ry[i] / (double)FRAC_SCALE;
            init.rz[i] = (double)st.rz[i] / (double)FRAC_SCALE;
            init.vx[i] = (double)st.vx[i] / (double)FRAC_SCALE;
            init.vy[i] = (double)st.vy[i] / (double)FRAC_SCALE;
            init.vz[i] = (double)st.vz[i] / (double)FRAC_SCALE;
            init.ax[i] = init.ay[i] = init.az[i] = 0.0;
            init.m[i]  = (double)st.m[i]  / (double)FRAC_SCALE;
        }
    }

    const int n = init.n;
    const double pairs_full = (double)n * (double)(n - 1);
    const double pairs_sym  = pairs_full / 2.0;

    printf("=== software reference: double precision, O(N^2) ===\n");
    printf("orbit=%s  N=%d  steps=%d  dt=%.6g  reps=%d\n\n",
           orbit_name, n, steps, dt, reps);

    // --- correctness: energy drift over the same run ---
    sim_copy(&work, &init);
    forces_full(&work);
    const double e0 = total_energy(&work);
    for (int s = 0; s < steps; s++) step(&work, dt, forces_full);
    const double ef = total_energy(&work);
    printf("Initial energy: %.6f\n", e0);
    printf("Final energy:   %.6f\n", ef);
    printf("Relative drift: %.3f%%\n\n", 100.0 * (ef - e0) / fabs(e0));

    if (csv_path) {
        FILE *fp = fopen(csv_path, "w");
        if (!fp) { perror("fopen"); return 1; }
        fprintf(fp, "step,t,particle,rx,ry,rz,vx,vy,vz,ax,ay,az,m\n");
        Sim out;
        sim_alloc(&out, n);
        sim_copy(&out, &init);
        forces_full(&out);
        write_csv_row(fp, &out, 0, 0.0);
        for (int s = 1; s <= steps; s++) {
            step(&out, dt, forces_full);
            write_csv_row(fp, &out, s, s * dt);
        }
        fclose(fp);
        sim_free(&out);
        printf("wrote %s\n\n", csv_path);
    }

    // --- timing: best of `reps` ---
    double best_full = 1e300, best_sym = 1e300;
    for (int r = 0; r < reps; r++) {
        const double tf = time_run(&work, &init, steps, dt, forces_full);
        const double ts = time_run(&work, &init, steps, dt, forces_sym);
        if (tf < best_full) best_full = tf;
        if (ts < best_sym)  best_sym  = ts;
    }

    const double ns_step_full = 1e9 * best_full / steps;
    const double ns_step_sym  = 1e9 * best_sym  / steps;
    const double ns_pair_full = ns_step_full / pairs_full;
    const double ns_pair_sym  = ns_step_sym  / pairs_sym;

    printf("%-12s %12s %13s %11s %14s\n", "kernel", "ns/step", "pairs/step", "ns/pair", "pairs/sec");
    printf("%-12s %12.1f %13.0f %11.3f %14.3g\n",
           "full_N^2", ns_step_full, pairs_full, ns_pair_full, 1e9 / ns_pair_full);
    printf("%-12s %12.1f %13.0f %11.3f %14.3g\n",
           "symmetric", ns_step_sym, pairs_sym, ns_pair_sym, 1e9 / ns_pair_sym);

    // Mirror everything into sim_log/software.log next to the RTL's
    // hardware.log, ending with a key=value block for modeling/compare.py.
    {
        FILE *lg = fopen("sim_log/software.log", "w");
        if (!lg) {
            fprintf(stderr, "warning: could not open sim_log/software.log "
                            "(run 'make sw_metrics', which creates the dir)\n");
        } else {
            fprintf(lg, "=== software reference: double precision, O(N^2) ===\n");
            fprintf(lg, "orbit=%s  N=%d  steps=%d  dt=%.6g  reps=%d\n\n",
                    orbit_name, n, steps, dt, reps);
            fprintf(lg, "Initial energy: %.6f\n", e0);
            fprintf(lg, "Final energy:   %.6f\n", ef);
            fprintf(lg, "Relative drift: %.3f%%\n\n", 100.0 * (ef - e0) / fabs(e0));
            fprintf(lg, "%-12s %12s %13s %11s %14s\n",
                    "kernel", "ns/step", "pairs/step", "ns/pair", "pairs/sec");
            fprintf(lg, "%-12s %12.1f %13.0f %11.3f %14.3g\n",
                    "full_N^2", ns_step_full, pairs_full, ns_pair_full, 1e9 / ns_pair_full);
            fprintf(lg, "%-12s %12.1f %13.0f %11.3f %14.3g\n",
                    "symmetric", ns_step_sym, pairs_sym, ns_pair_sym, 1e9 / ns_pair_sym);

            fprintf(lg, "\n[metrics]\n");
            fprintf(lg, "impl=software\n");
            fprintf(lg, "orbit=%s\n", orbit_name);
            fprintf(lg, "n=%d\n", n);
            fprintf(lg, "steps=%d\n", steps);
            fprintf(lg, "reps=%d\n", reps);
            fprintf(lg, "pairs_per_step=%.0f\n", pairs_full);
            fprintf(lg, "ns_per_step=%.6f\n", ns_step_full);
            fprintf(lg, "ns_per_pair=%.6f\n", ns_pair_full);
            fprintf(lg, "sym_pairs_per_step=%.0f\n", pairs_sym);
            fprintf(lg, "sym_ns_per_step=%.6f\n", ns_step_sym);
            fprintf(lg, "sym_ns_per_pair=%.6f\n", ns_pair_sym);
            fprintf(lg, "drift_pct=%.6f\n", 100.0 * (ef - e0) / fabs(e0));
            fclose(lg);
            printf("\nwrote sim_log/software.log\n");
        }
    }

    if (cpu_ghz > 0.0)
        printf("\nat %.2f GHz: %.1f cpu-cycles/pair (full), %.1f (symmetric)\n",
               cpu_ghz, ns_pair_full * cpu_ghz, ns_pair_sym * cpu_ghz);

    if (hw_cycles > 0.0 && hw_period > 0.0) {
        const double hw_ns_step = hw_cycles * hw_period;
        const double hw_ns_pair = hw_ns_step / pairs_full;   // accelerator evaluates ordered pairs
        printf("\n=== vs accelerator (%.0f cycles/step @ %.2f ns) ===\n", hw_cycles, hw_period);
        printf("accelerator: %.1f ns/step, %.3f ns/pair, %.2f cycles/pair\n",
               hw_ns_step, hw_ns_pair, hw_cycles / pairs_full);
        printf("speedup vs full N^2 : %.2fx\n", ns_step_full / hw_ns_step);
        printf("speedup vs symmetric: %.2fx\n", ns_step_sym  / hw_ns_step);
        printf("\nnote: wall-clock speedup is dominated by process node -- the RTL targets a\n");
        printf("0.25um library, so cycles/pair is the process-independent comparison.\n");
    }

    sim_free(&init);
    sim_free(&work);
    return 0;
}
