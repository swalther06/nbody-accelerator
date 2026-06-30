#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "orbits.h"

// Orbit configs live in orbits.csv (shared with orbits.py), not here -- add
// a new orbit by appending rows there (same name on each of its particle
// rows), not by editing this file.
#define ORBITS_CSV_PATH "modeling/orbits.csv"

static inline int32_t to_fixed(double x) {
    return (int32_t)llround(x * (double)FRAC_SCALE);
}

double load_orbit_config(const char *name, State *state) {
    FILE *f = fopen(ORBITS_CSV_PATH, "r");
    if (!f) {
        perror("fopen " ORBITS_CSV_PATH);
        exit(1);
    }

    char line[256];
    fgets(line, sizeof(line), f);  // skip header row

    memset(state, 0, sizeof(*state));
    int n = 0;
    double dt = 0.0;
    int found = 0;

    char row_name[64];
    double row_dt, rx, ry, rz, vx, vy, vz, m;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%63[^,],%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                   row_name, &row_dt, &rx, &ry, &rz, &vx, &vy, &vz, &m) != 9) {
            continue;
        }
        if (strcmp(row_name, name) != 0) continue;

        found = 1;
        dt = row_dt;
        if (n >= N) {
            fprintf(stderr, "orbit '%s' needs more than %d bodies\n", name, N);
            exit(1);
        }
        state->rx[n] = to_fixed(rx);
        state->ry[n] = to_fixed(ry);
        state->rz[n] = to_fixed(rz);
        state->vx[n] = to_fixed(vx);
        state->vy[n] = to_fixed(vy);
        state->vz[n] = to_fixed(vz);
        state->m[n]  = to_fixed(m);
        n++;
    }
    fclose(f);

    if (!found) {
        fprintf(stderr, "unknown orbit '%s'\n", name);
        exit(1);
    }

    return dt;
}
